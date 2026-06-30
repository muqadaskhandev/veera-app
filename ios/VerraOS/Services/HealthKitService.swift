import Foundation
import HealthKit

/// A single day's aggregated health metrics from HealthKit.
struct DailyHealthMetric: Identifiable, Hashable {
    var id: String { date }
    let date: String
    let sleepMinutes: Int?
    let steps: Int?
    let restingHR: Int?
    let hrv: Double?
    let activeCalories: Int?

    func asSyncInput() -> HealthDailyMetricInput {
        HealthDailyMetricInput(
            date: date,
            sleepMinutes: sleepMinutes,
            steps: steps,
            restingHR: restingHR,
            hrv: hrv,
            activeCalories: activeCalories
        )
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Health data is not available on this device."
        case .authorizationDenied: return "Apple Health access was denied. Enable it in Settings → Health → Data Access."
        }
    }
}

/// Reads daily health summaries from Apple HealthKit.
enum HealthKitService {
    private static let store = HKHealthStore()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
        ]
        for id in quantityIDs {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Presents the system Health permission sheet for the read types we use.
    @MainActor
    static func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
    }

    /// Pulls daily summaries for the last `days` calendar days (inclusive of today).
    static func fetchDailyMetrics(days: Int = 30) async throws -> [DailyHealthMetric] {
        guard isAvailable else { throw HealthKitError.unavailable }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else {
            return []
        }
        let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: end)!)

        async let steps = dailyQuantitySum(.stepCount, unit: .count(), interval: interval)
        async let calories = dailyQuantitySum(.activeEnergyBurned, unit: .kilocalorie(), interval: interval)
        async let restingHR = dailyQuantityAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), interval: interval)
        async let hrv = dailyQuantityAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), interval: interval)
        async let sleep = dailySleepMinutes(interval: interval)

        let merged = try await mergeDaily(
            days: days,
            end: end,
            steps: steps,
            calories: calories,
            restingHR: restingHR,
            hrv: hrv,
            sleep: sleep
        )
        return merged
    }

    // MARK: - Queries

    private static func dailyQuantitySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await statisticsCollection(
            type: type,
            options: .cumulativeSum,
            unit: unit,
            interval: interval
        )
    }

    private static func dailyQuantityAverage(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await statisticsCollection(
            type: type,
            options: .discreteAverage,
            unit: unit,
            interval: interval
        )
    }

    private static func statisticsCollection(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        unit: HKUnit,
        interval: DateInterval
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let anchor = Calendar.current.startOfDay(for: interval.start)
            let daily = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(
                    withStart: interval.start,
                    end: interval.end,
                    options: .strictStartDate
                ),
                options: options,
                anchorDate: anchor,
                intervalComponents: daily
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var values: [String: Double] = [:]
                collection?.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
                    let day = dayFormatter.string(from: stats.startDate)
                    if options.contains(.cumulativeSum), let sum = stats.sumQuantity() {
                        values[day] = sum.doubleValue(for: unit)
                    } else if options.contains(.discreteAverage), let avg = stats.averageQuantity() {
                        values[day] = avg.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private static func dailySleepMinutes(interval: DateInterval) async throws -> [String: Double] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: interval.start,
                end: interval.end,
                options: .strictStartDate
            )
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var minutesByDay: [String: Double] = [:]
                let samples = (samples as? [HKCategorySample]) ?? []
                for sample in samples where asleepValues.contains(sample.value) {
                    let wakeDay = Calendar.current.startOfDay(for: sample.endDate)
                    let day = dayFormatter.string(from: wakeDay)
                    let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
                    minutesByDay[day, default: 0] += minutes
                }
                continuation.resume(returning: minutesByDay)
            }
            store.execute(query)
        }
    }

    private static func mergeDaily(
        days: Int,
        end: Date,
        steps: [String: Double],
        calories: [String: Double],
        restingHR: [String: Double],
        hrv: [String: Double],
        sleep: [String: Double]
    ) -> [DailyHealthMetric] {
        let calendar = Calendar.current
        return (0..<days).compactMap { offset -> DailyHealthMetric? in
            guard let dayDate = calendar.date(byAdding: .day, value: -((days - 1) - offset), to: end) else {
                return nil
            }
            let key = dayFormatter.string(from: dayDate)
            return DailyHealthMetric(
                date: key,
                sleepMinutes: sleep[key].map { Int($0.rounded()) },
                steps: steps[key].map { Int($0.rounded()) },
                restingHR: restingHR[key].map { Int($0.rounded()) },
                hrv: hrv[key],
                activeCalories: calories[key].map { Int($0.rounded()) }
            )
        }
    }
}
