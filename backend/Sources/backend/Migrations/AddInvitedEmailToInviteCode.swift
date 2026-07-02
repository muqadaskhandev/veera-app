import Fluent
import SQLKit

struct AddInvitedEmailToInviteCode: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(InviteCode.schema)
            .field("invited_email", .string)
            .update()

        if let sql = database as? any SQLDatabase {
            try await sql.raw("""
                UPDATE invite_codes
                SET invited_email = LOWER(TRIM(clients.email))
                FROM clients
                WHERE invite_codes.client_id = clients.id
                  AND invite_codes.invited_email IS NULL
                  AND clients.email <> ''
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(InviteCode.schema)
            .deleteField("invited_email")
            .update()
    }
}
