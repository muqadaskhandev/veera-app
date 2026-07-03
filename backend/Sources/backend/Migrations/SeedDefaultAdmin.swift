import Fluent
import Vapor

/// Creates a default platform admin for local development and admin UI login.
struct SeedDefaultAdmin: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard shouldSeedAdmin else { return }

        let email = (Environment.get("SEED_ADMIN_EMAIL") ?? "admin@verra.test").lowercased()
        let password = Environment.get("SEED_ADMIN_PASSWORD") ?? "password123"
        let displayName = Environment.get("SEED_ADMIN_NAME") ?? "Platform Admin"

        if try await User.query(on: database).filter(\.$role == UserRole.admin.rawValue).first() != nil {
            return
        }

        if try await User.query(on: database).filter(\.$email == email).first() != nil {
            return
        }

        let user = User(
            email: email,
            passwordHash: try Bcrypt.hash(password),
            role: .admin,
            displayName: displayName,
            isEmailVerified: true,
            isActive: true
        )
        try await user.save(on: database)
    }

    func revert(on database: any Database) async throws {
        let email = (Environment.get("SEED_ADMIN_EMAIL") ?? "admin@verra.test").lowercased()
        try await User.query(on: database)
            .filter(\.$email == email)
            .filter(\.$role == UserRole.admin.rawValue)
            .delete()
    }

    private var shouldSeedAdmin: Bool {
        if Environment.get("SEED_ADMIN") == "false" { return false }
        if Environment.get("SEED_ADMIN") == "true" { return true }
        return (try? Environment.detect()) == .some(.development)
    }
}
