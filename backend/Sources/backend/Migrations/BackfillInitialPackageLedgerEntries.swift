import Fluent
import Foundation

/// One-time data backfill: clients that already have a non-zero session
/// balance but no financial event at all (created before ledger entries were
/// recorded for initial invite balances) get a synthetic "Package Added"
/// entry so the client's ledger "Packages" filter isn't empty.
struct BackfillInitialPackageLedgerEntries: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let clients = try await Client.query(on: database)
            .filter(\.$sessionsRemaining > 0)
            .all()

        for client in clients {
            guard let clientID = client.id else { continue }
            let hasAnyEvent = try await FinancialEvent.query(on: database)
                .filter(\.$client.$id == clientID)
                .first() != nil
            guard !hasAnyEvent else { continue }

            try await FinancialService.recordInitialPackage(
                client: client,
                trainerID: client.$trainer.id,
                sessionsRemaining: client.sessionsRemaining,
                on: database
            )
        }
    }

    func revert(on database: any Database) async throws {
        // Data backfill only — nothing to revert (removing entries could hide
        // legitimate usage layered on top since).
    }
}
