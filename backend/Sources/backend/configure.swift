import Fluent
import FluentPostgresDriver
import Foundation
import JWT
import NIOSSL
import Vapor

/// Configures the Vapor application: database, migrations, and middleware.
func configure(_ app: Application) async throws {
    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PATCH, .PUT, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .upgrade, .connection, .secWebSocketKey, .secWebSocketVersion, .secWebSocketProtocol]
    )))

    let jwtSecret = Environment.get("JWT_SECRET") ?? "verra-local-dev-secret-change-me"
    app.jwt.signers.use(.hs256(key: jwtSecret))

    let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
    let port = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber
    let username = Environment.get("DATABASE_USERNAME") ?? NSUserName()
    let password = Environment.get("DATABASE_PASSWORD").flatMap { $0.isEmpty ? nil : $0 }
    let database = Environment.get("DATABASE_NAME") ?? "verra_dev"
    // Supabase / managed Postgres require TLS; local Homebrew Postgres usually does not.
    let useTLS = Environment.get("DATABASE_SSL").map { ["1", "true", "yes"].contains($0.lowercased()) }
        ?? !(hostname == "localhost" || hostname == "127.0.0.1")

    let postgresTLS: PostgresConnection.Configuration.TLS
    if useTLS {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        let skipVerify = Environment.get("DATABASE_SSL_VERIFY").map { ["0", "false", "no"].contains($0.lowercased()) }
            ?? hostname.contains("pooler.supabase.com")
        if skipVerify {
            tlsConfig.certificateVerification = .none
        }
        postgresTLS = try .require(.init(configuration: tlsConfig))
    } else {
        postgresTLS = .disable
    }

    app.databases.use(
        DatabaseConfigurationFactory.postgres(configuration: .init(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: postgresTLS
        )),
        as: .psql
    )

    app.migrations.add(CreateTrainer())
    app.migrations.add(CreateClient())
    app.migrations.add(CreateSession())
    app.migrations.add(CreateConversation())
    app.migrations.add(CreateMessage())
    app.migrations.add(CreateUser())
    app.migrations.add(AddLastSeenToUser())
    app.migrations.add(CreateAuthSession())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateInviteCode())
    app.migrations.add(AddInvitedEmailToInviteCode())
    app.migrations.add(CreateTrainerOnboarding())
    app.migrations.add(AddUserForeignKeys())
    app.migrations.add(AddGoogleSubjectToUser())
    app.migrations.add(CreateEmailVerificationCode())
    app.migrations.add(EnhanceChatMessaging())
    app.migrations.add(CreatePushDeviceToken())
    app.migrations.add(AddProfileFields())
    app.migrations.add(CreateProfile())
    app.migrations.add(MigrateExistingProfiles())
    app.migrations.add(CreateWearableConnection())
    app.migrations.add(CreateHealthDailyMetrics())
    app.migrations.add(CreateOuraToken())
    app.migrations.add(CreateOuraOAuthState())
    app.migrations.add(AddGoalWeightToClient())
    app.migrations.add(AddVisibleModulesToClient())
    app.migrations.add(CreatePlatformFeatures())
    app.migrations.add(ExtendPlatformSettings())
    app.migrations.add(ExtendSubscriptionLifecycle())
    app.migrations.add(AddExerciseLibraryFields())
    app.migrations.add(CreateNotificationOutbox())
    app.migrations.add(CreateGoogleCalendarTables())
    app.migrations.add(CreateStripePayments())
    app.migrations.add(SeedDefaultTrainer())
    app.migrations.add(SeedDefaultAdmin())
    app.migrations.add(AddSessionTimeZone())

    app.lifecycle.use(ReminderPollingService())

    try await app.autoMigrate()

    // Idempotent — fills empty exercise library / client workout plans after DB resets.
    try await MigrationSupport.seedExercisesIfNeeded(on: app.db)
    try await MigrationSupport.seedSampleWorkoutsIfNeeded(on: app.db)

    if SESEmailService.isConfigured() {
        app.logger.info("Amazon SES email delivery is enabled")
    } else if app.environment == .development {
        app.logger.warning("SES is not configured — verification emails are logged locally in development")
    } else {
        app.logger.warning("SES is not configured — email delivery will fail in production")
    }

    if APNsService.isConfigured(on: app) {
        app.logger.info("Apple Push Notification service is enabled")
    } else if app.environment == .development {
        app.logger.warning("APNs is not configured — background push will not be delivered")
    } else {
        app.logger.warning("APNs is not configured — background push will fail in production")
    }

    if TwilioService.isConfigured() {
        app.logger.info("Twilio SMS delivery is enabled")
    } else if app.environment == .development {
        app.logger.warning("Twilio is not configured — SMS messages are logged locally in development")
    }

    if StripeService.isConfigured() {
        app.logger.info("Stripe payments are enabled")
    } else if app.environment == .development {
        app.logger.warning("Stripe is not configured — card and Apple Pay checkout will be unavailable")
    }

    try routes(app)
}
