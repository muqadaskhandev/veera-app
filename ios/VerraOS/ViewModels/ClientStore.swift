//
//  ClientStore.swift
//  VerraOS
//

import SwiftUI

/// Sort dimension for the client directory.
enum ClientSort: String, CaseIterable, Identifiable {
    case status = "Status"
    case name = "Name"
    case sessions = "Sessions Left"
    var id: String { rawValue }
}

/// Owns the mutable client roster shared by the directory list, the add-client
/// flow, and the archive view.
@Observable
final class ClientStore {
    var clients: [Client]

    init(clients: [Client] = Client.roster) {
        self.clients = clients
    }

    /// Active (non-archived) clients only.
    var activeClients: [Client] {
        clients.filter { !$0.isArchived }
    }

    var archivedCount: Int {
        clients.filter { $0.isArchived }.count
    }

    /// Filtered + sorted roster for the directory.
    func roster(search: String, sort: ClientSort, showArchived: Bool) -> [Client] {
        var result = showArchived ? clients.filter { $0.isArchived } : activeClients

        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        switch sort {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .sessions:
            result.sort { $0.sessionsRemaining < $1.sessionsRemaining }
        case .status:
            result.sort {
                if $0.effectiveStatus.priority != $1.effectiveStatus.priority {
                    return $0.effectiveStatus.priority > $1.effectiveStatus.priority
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return result
    }

    // MARK: Mutations

    func add(_ client: Client) {
        clients.insert(client, at: 0)
    }

    func archive(_ client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index].isArchived = true
    }

    func restore(_ client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index].isArchived = false
        if clients[index].status == .archived {
            clients[index].status = .active
        }
    }

    func delete(_ client: Client) {
        clients.removeAll { $0.id == client.id }
    }

    func setNote(_ note: String, for client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index].note = note
    }

    func setNote(_ note: String, forID id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].note = note
    }

    /// Updates a client's editable biometric fields. `nil` clears a field.
    func updateBiometrics(age: Int?, heightCm: Int?, weightKg: Int?, for id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].age = age
        clients[index].heightCm = heightCm
        clients[index].weightKg = weightKg
    }

    /// Deducts one session from the first client matching this name, clamped at
    /// zero. Used when a past session auto-completes on the schedule.
    func deductSession(forName name: String) {
        guard let index = clients.firstIndex(where: { $0.name == name }) else { return }
        clients[index].sessionsRemaining = max(0, clients[index].sessionsRemaining - 1)
    }

    /// Refunds one session to the first client matching this name. Used when a
    /// previously auto-counted session is skipped.
    func refundSession(forName name: String) {
        guard let index = clients.firstIndex(where: { $0.name == name }) else { return }
        clients[index].sessionsRemaining += 1
    }

    /// Adjusts a client's session bank by a delta, clamped at zero. Used by the
    /// profile financials ledger ([+] / [-] and package top-ups).
    func adjustSessions(by delta: Int, for id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].sessionsRemaining = max(0, clients[index].sessionsRemaining + delta)
    }
}
