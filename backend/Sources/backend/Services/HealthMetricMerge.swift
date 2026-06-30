import Vapor

/// Per-field precedence when Apple Health and Oura both sync the same day.
enum HealthMetricMerge {
    enum Field {
        case sleepMinutes
        case steps
        case restingHR
        case hrv
        case activeCalories
    }

    /// Preferred provider for each metric type.
    static func preferredProvider(for field: Field) -> WearableProvider {
        switch field {
        case .sleepMinutes, .restingHR, .hrv:
            return .oura
        case .steps, .activeCalories:
            return .appleHealth
        }
    }

    /// Whether an incoming value from `provider` should be written over `existing`.
    static func shouldApply<T>(
        field: Field,
        provider: WearableProvider,
        existing: T?,
        incoming: T?
    ) -> Bool {
        guard incoming != nil else { return false }
        if existing == nil { return true }
        return provider == preferredProvider(for: field)
    }

    static func provider(from source: String) -> WearableProvider? {
        WearableProvider(rawValue: source)
    }

    static func mergedSource(existing: String, incoming: String) -> String {
        if existing == incoming || existing.isEmpty { return incoming }
        if existing == "merged" || incoming == "merged" { return "merged" }
        return "merged"
    }
}
