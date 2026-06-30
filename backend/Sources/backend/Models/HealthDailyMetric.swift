import Fluent
import Vapor

final class HealthDailyMetric: Model, @unchecked Sendable {
    static let schema = "health_daily_metrics"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "date")
    var date: Date

    @OptionalField(key: "sleep_minutes")
    var sleepMinutes: Int?

    @OptionalField(key: "steps")
    var steps: Int?

    @OptionalField(key: "resting_hr")
    var restingHR: Int?

    @OptionalField(key: "hrv")
    var hrv: Double?

    @OptionalField(key: "active_calories")
    var activeCalories: Int?

    @Field(key: "source")
    var source: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        date: Date,
        sleepMinutes: Int? = nil,
        steps: Int? = nil,
        restingHR: Int? = nil,
        hrv: Double? = nil,
        activeCalories: Int? = nil,
        source: String
    ) {
        self.id = id
        self.$user.id = userID
        self.date = date
        self.sleepMinutes = sleepMinutes
        self.steps = steps
        self.restingHR = restingHR
        self.hrv = hrv
        self.activeCalories = activeCalories
        self.source = source
    }
}

struct HealthDailyMetricDTO: Content {
    let date: String
    let sleepMinutes: Int?
    let steps: Int?
    let restingHR: Int?
    let hrv: Double?
    let activeCalories: Int?
    let source: String

    init(from metric: HealthDailyMetric) {
        self.date = HealthDateCodec.dayString(from: metric.date)
        self.sleepMinutes = metric.sleepMinutes
        self.steps = metric.steps
        self.restingHR = metric.restingHR
        self.hrv = metric.hrv
        self.activeCalories = metric.activeCalories
        self.source = metric.source
    }
}

struct HealthDailyMetricInput: Content {
    let date: String
    let sleepMinutes: Int?
    let steps: Int?
    let restingHR: Int?
    let hrv: Double?
    let activeCalories: Int?
}

struct HealthSyncRequest: Content {
    let provider: String
    let metrics: [HealthDailyMetricInput]
}

struct HealthMeResponse: Content {
    let connections: [WearableConnectionDTO]
    let metrics: [HealthDailyMetricDTO]
}

enum HealthDateCodec {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func parseDay(_ value: String) throws -> Date {
        guard let date = formatter.date(from: value) else {
            throw Abort(.badRequest, reason: "Invalid date: \(value). Expected yyyy-MM-dd.")
        }
        return date
    }

    static func startOfDayUTC(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    static func daysAgo(_ days: Int, from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -days, to: start) ?? start
    }
}
