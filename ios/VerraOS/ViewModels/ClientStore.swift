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
    var isLoadedFromServer = false

    init(clients: [Client] = Client.roster) {
        self.clients = clients
    }

    @MainActor
    func refreshFromServer() async {
        guard let token = AuthStore.accessToken else { return }
        do {
            async let active = VerraAPI.fetchClients(accessToken: token, archived: false)
            async let archived = VerraAPI.fetchClients(accessToken: token, archived: true)
            let dtos = try await active + archived
            clients = dtos.map(ClientLoader.client(from:))
            isLoadedFromServer = true
        } catch {
            // Keep existing roster when offline.
        }
    }

    func updateVisibleModules(_ modules: [String], for id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].visibleModules = modules
    }

    var activeClients: [Client] {
        clients.filter { !$0.isArchived }
    }

    var archivedCount: Int {
        clients.filter { $0.isArchived }.count
    }

    func syncRoster(to schedule: ScheduleStore) {
        schedule.clients = activeClients
    }

    func roster(search: String, sort: ClientSort, showArchived: Bool) -> [Client] {
        var result = showArchived ? clients.filter { $0.isArchived } : activeClients

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query)
                    || $0.email.lowercased().contains(query)
                    || $0.phone.contains(query)
            }
        }

        switch sort {
        case .status:
            result.sort { $0.effectiveStatus.priority > $1.effectiveStatus.priority }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .sessions:
            result.sort { $0.sessionsRemaining > $1.sessionsRemaining }
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
        Task { @MainActor in
            await persistArchive(true, for: client.id)
        }
    }

    func restore(_ client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index].isArchived = false
        if clients[index].status == .archived {
            clients[index].status = .active
        }
        Task { @MainActor in
            await persistArchive(false, for: client.id)
        }
    }

    func delete(_ client: Client) {
        clients.removeAll { $0.id == client.id }
        Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            try? await VerraAPI.deleteClient(id: client.id, accessToken: token)
        }
    }

    func setNote(_ note: String, for client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index].note = note
    }

    func setNote(_ note: String, forID id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].note = note
        Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            if let dto = try? await VerraAPI.updateClient(id: id, note: note, accessToken: token),
               let refreshed = clients.firstIndex(where: { $0.id == id }) {
                clients[refreshed] = ClientLoader.client(from: dto)
            }
        }
    }

    func updateBiometrics(
        age: Int?,
        heightCm: Int?,
        weightKg: Int?,
        goalWeightKg: Int? = nil,
        startWeightKg: Double? = nil,
        for id: UUID
    ) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].age = age
        clients[index].heightCm = heightCm
        clients[index].weightKg = weightKg
        if let goalWeightKg { clients[index].goalWeightKg = goalWeightKg }
        if let startWeightKg { clients[index].startWeightKg = startWeightKg }
        Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            if let dto = try? await VerraAPI.updateClient(
                id: id,
                age: age,
                heightCm: heightCm,
                weightKg: weightKg,
                goalWeightKg: goalWeightKg,
                startWeightKg: startWeightKg,
                accessToken: token
            ) {
                if let refreshed = clients.firstIndex(where: { $0.id == id }) {
                    clients[refreshed] = ClientLoader.client(from: dto)
                }
            }
        }
    }

    /// Optimistically nudges a client's session bank by `delta` (clamped to
    /// zero), ahead of the server round-trip confirming the change.
    func adjustSessionsRemaining(by delta: Int, for id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].sessionsRemaining = max(0, clients[index].sessionsRemaining + delta)
    }

    func deductSession(forName name: String) {
        guard let index = clients.firstIndex(where: { $0.name == name }) else { return }
        clients[index].sessionsRemaining = max(0, clients[index].sessionsRemaining - 1)
    }

    func refundSession(forName name: String) {
        guard let index = clients.firstIndex(where: { $0.name == name }) else { return }
        clients[index].sessionsRemaining += 1
    }

    func applyClientDTO(_ dto: ClientDTO) {
        let client = ClientLoader.client(from: dto)
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
        }
    }

    @MainActor
    private func persistArchive(_ archived: Bool, for id: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        if let dto = try? await VerraAPI.updateClient(id: id, isArchived: archived, accessToken: token) {
            applyClientDTO(dto)
        }
    }
}
