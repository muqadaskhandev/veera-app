import Foundation

struct HealthDailyMetricInput: Encodable {
    let date: String
    let sleepMinutes: Int?
    let steps: Int?
    let restingHR: Int?
    let hrv: Double?
    let activeCalories: Int?
}

struct HealthDailyMetricDTO: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let sleepMinutes: Int?
    let steps: Int?
    let restingHR: Int?
    let hrv: Double?
    let activeCalories: Int?
    let source: String
}

struct WearableConnectionDTO: Codable, Hashable {
    let provider: String
    let connectedAt: Date
    let lastSyncedAt: Date?
}

struct HealthMeResponse: Codable {
    let connections: [WearableConnectionDTO]
    let metrics: [HealthDailyMetricDTO]
}

struct HealthSyncBody: Encodable {
    let provider: String
    let metrics: [HealthDailyMetricInput]
}

struct HealthConnectBody: Encodable {
    let provider: String
}

/// Cached health metrics for charts and summaries.
@Observable
final class HealthDataStore {
    var metrics: [HealthDailyMetricDTO] = []
    var connections: [WearableConnectionDTO] = []
    var isLoading = false
    var lastError: String?

    var hasMetrics: Bool {
        metrics.contains { $0.steps != nil || $0.sleepMinutes != nil || $0.restingHR != nil }
    }

    @MainActor
    func refreshForClient(clientID: UUID, trainerView: Bool) async {
        guard let token = AuthStore.accessToken else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let response: HealthMeResponse
            if trainerView {
                response = try await VerraAPI.fetchClientHealth(clientID: clientID, accessToken: token)
            } else {
                response = try await VerraAPI.fetchMyHealth(accessToken: token)
            }
            metrics = response.metrics.sorted { $0.date < $1.date }
            connections = response.connections
        } catch {
            lastError = error.localizedDescription
        }
    }

    func metrics(for timeframe: WearableTimeframe) -> [HealthDailyMetricDTO] {
        let sorted = metrics.sorted { $0.date < $1.date }
        return Array(sorted.suffix(timeframe.days))
    }

    func averageSleepMinutes(in metrics: [HealthDailyMetricDTO]) -> Int? {
        let values = metrics.compactMap(\.sleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    func averageSteps(in metrics: [HealthDailyMetricDTO]) -> Int? {
        let values = metrics.compactMap(\.steps)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    func averageRestingHR(in metrics: [HealthDailyMetricDTO]) -> Int? {
        let values = metrics.compactMap(\.restingHR)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    func averageHRV(in metrics: [HealthDailyMetricDTO]) -> Double? {
        let values = metrics.compactMap(\.hrv)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func dayLabels(for metrics: [HealthDailyMetricDTO]) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "EEE"
        return metrics.map { metric in
            guard let date = formatter.date(from: metric.date) else { return "" }
            return labelFormatter.string(from: date)
        }
    }
}
