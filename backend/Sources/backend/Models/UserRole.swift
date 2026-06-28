import Vapor

enum UserRole: String, Codable, CaseIterable {
    case trainer
    case client
    case admin

    var canManageUsers: Bool { self == .admin }
    var canManageInvites: Bool { self == .trainer || self == .admin }
    var canAccessTrainerData: Bool { self == .trainer || self == .admin }
    var canAccessClientData: Bool { self == .client || self == .admin }
}
