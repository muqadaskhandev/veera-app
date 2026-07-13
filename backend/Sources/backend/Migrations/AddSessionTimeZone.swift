import Fluent
import Foundation
import SQLKit

struct AddSessionTimeZone: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard try await MigrationSupport.tableExists(Session.schema, on: database) else { return }
        if try await !MigrationSupport.columnExists("time_zone_identifier", on: Session.schema, database: database) {
            try await database.schema(Session.schema)
                .field("time_zone_identifier", .string)
                .update()
        }

        // Legacy rows: pin to the server's local zone so trainer + client agree on wall-clock time.
        if let sql = database as? any SQLDatabase {
            let zone = TimeZone.current.identifier
            try await sql.raw(
                """
                UPDATE sessions
                SET time_zone_identifier = \(bind: zone)
                WHERE time_zone_identifier IS NULL
                """
            ).run()
        }
    }

    func revert(on database: any Database) async throws {
        if try await MigrationSupport.columnExists("time_zone_identifier", on: Session.schema, database: database) {
            try await database.schema(Session.schema)
                .deleteField("time_zone_identifier")
                .update()
        }
    }
}
