import Vapor

enum WearableProvider: String, Codable, CaseIterable {
    case appleHealth = "apple_health"
    case oura = "oura"

    var displayName: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .oura: return "Oura"
        }
    }
}
