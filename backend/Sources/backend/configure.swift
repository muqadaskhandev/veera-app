import Fluent
import FluentPostgresDriver
import Foundation
import JWT
import Vapor

/// Configures the Vapor application: database, migrations, and middleware.
func configure(_ app: Application) async throws {
    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PATCH, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin]
    )))

    let jwtSecret = Environment.get("JWT_SECRET") ?? "verra-local-dev-secret-change-me"
    app.jwt.signers.use(.hs256(key: jwtSecret))

    let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
    let port = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber
    let username = Environment.get("DATABASE_USERNAME") ?? NSUserName()
    let password = Environment.get("DATABASE_PASSWORD").flatMap { $0.isEmpty ? nil : $0 }
    let database = Environment.get("DATABASE_NAME") ?? "verra_dev"

    app.databases.use(
        DatabaseConfigurationFactory.postgres(configuration: .init(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )),
        as: .psql
    )

    app.migrations.add(CreateTrainer())
    app.migrations.add(CreateClient())
    app.migrations.add(CreateSession())
    app.migrations.add(CreateConversation())
    app.migrations.add(CreateMessage())
    app.migrations.add(CreateUser())
    app.migrations.add(CreateAuthSession())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateInviteCode())
    app.migrations.add(CreateTrainerOnboarding())
    app.migrations.add(AddUserForeignKeys())
    app.migrations.add(CreateEmailVerificationCode())
    app.migrations.add(AddGoogleSubjectToUser())
    app.migrations.add(SeedDefaultTrainer())

    try await app.autoMigrate()

    if SESEmailService.isConfigured() {
        app.logger.info("Amazon SES email delivery is enabled")
    } else if app.environment == .development {
        app.logger.warning("SES is not configured — verification emails are logged locally in development")
    } else {
        app.logger.warning("SES is not configured — email delivery will fail in production")
    }

    try routes(app)
}
