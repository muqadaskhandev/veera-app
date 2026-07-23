//
//  ClientFinancialsView.swift
//  VerraOS
//

import SwiftUI

struct ClientFinancialsView: View {
    let clientID: UUID
    var onBack: () -> Void

    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var priceText = "800"
    @State private var countText = "40"
    @State private var calculatorCollapsed = false
    @State private var historyFilter: HistoryFilter = .all
    @State private var newestFirst = true
    @State private var showAllHistory = false
    @State private var toast: ToastData?

    private enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case packages = "Packages"
        case sessions = "Sessions"
        case adjustments = "Adjust"
        var id: String { rawValue }

        func matches(_ entry: LedgerEntry) -> Bool {
            switch self {
            case .all: return true
            case .packages: return entry.kind == .packageAdded
            case .sessions: return entry.kind == .sessionUsed
            case .adjustments: return entry.kind == .adjustment
            }
        }
    }

    private let historyPreviewCount = 4

    private var client: Client? { clientStore.clients.first { $0.id == clientID } }

    private var pricePerSession: Double {
        let price = Double(priceText) ?? 0
        let count = Double(countText) ?? 0
        guard count > 0 else { return 0 }
        return price / count
    }

    var body: some View {
        Group {
            if let client {
                content(client)
            } else {
                VStack { Spacer(); Text("Client unavailable").foregroundStyle(Theme.Color.inkMuted); Spacer() }
            }
        }
        .background(Theme.Color.background)
        .preferredColorScheme(.light)
        .toast($toast)
        .task {
            await refreshFinancials()
        }
    }

    @MainActor
    private func refreshFinancials() async {
        await profile.refreshLedger(for: clientID)
        await refreshLinkedClientIfNeeded()
    }

    /// Client app only — refreshes session bank from profile API without requiring ClientAccountStore.
    @MainActor
    private func refreshLinkedClientIfNeeded() async {
        guard isReadOnly, let token = AuthStore.accessToken else { return }
        guard let response = try? await VerraAPI.fetchProfile(accessToken: token),
              let clientDTO = response.client else { return }
        let loaded = ProfileLoader.client(from: clientDTO)
        clientStore.clients = [loaded]
    }

    private func content(_ client: Client) -> some View {
        VStack(spacing: 0) {
            ProfileTopBar(title: "Financials", subtitle: client.name.firstWord, onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    sessionBank(client)
                    if isReadOnly {
                        clientPackageInfo(client)
                    } else {
                        packageCalculator(client)
                    }
                    usageHistory(client)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            }
            .frame(maxHeight: .infinity)
            .tabScrollContent()
            .dismissKeyboardOnScroll()
            .refreshable {
                await refreshFinancials()
            }
        }
    }

    // MARK: Client read-only package info

    private func clientPackageInfo(_ client: Client) -> some View {
        let packages = profile.ledger(for: client).filter { $0.kind == .packageAdded }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sessions are added by your trainer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Text("When you purchase a package, your coach records it in their app and credits appear here automatically.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if client.sessionsRemaining == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Color.danger)
                    Text("You're out of sessions — message your trainer to buy a new package.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            if !packages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR PACKAGES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.Color.inkFaint)
                    ForEach(packages.prefix(3)) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color(hex: 0x57C77B))
                            Text("+\(entry.delta) sessions")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                            if let amount = entry.amount {
                                Text(String(format: "$%.0f", amount))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Color.inkMuted)
                            }
                            Spacer()
                            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.Color.inkFaint)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }

    // MARK: Session bank

    private func sessionBank(_ client: Client) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("SESSION BANK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.accent.opacity(0.8))
                Text("\(client.sessionsRemaining)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: client.sessionsRemaining)
            }
            if !isReadOnly {
                HStack(spacing: 12) {
                    adjustButton(icon: "minus", client: client) { adjust(-1, client) }
                    adjustButton(icon: "plus", client: client) { adjust(1, client) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardShadow()
    }

    private func adjustButton(icon: String, client: Client, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Color.background)
                .frame(width: 54, height: 44)
                .background(Theme.Color.background.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Package calculator

    private func packageCalculator(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { calculatorCollapsed.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Text("PACKAGE CALCULATOR")
                        .font(.system(size: 11.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.Color.inkMuted)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .rotationEffect(.degrees(calculatorCollapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !calculatorCollapsed {
                calculatorBody(client)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.6)
    }

    private func calculatorBody(_ client: Client) -> some View {
        Group {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    inputField(title: "Total Price", text: $priceText, prefix: "$")
                    inputField(title: "Sessions", text: $countText, prefix: nil)
                }
                HStack {
                    Text("Price per session")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Spacer()
                    Text(pricePerSession > 0 ? String(format: "$%.0f", pricePerSession.rounded()) : "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

                Button { addPackage(client) } label: {
                    Text("Add Package")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled((Int(countText) ?? 0) <= 0)
                .opacity((Int(countText) ?? 0) <= 0 ? 0.5 : 1)
            }
        }
    }

    private func inputField(title: String, text: Binding<String>, prefix: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.Color.inkFaint)
            HStack(spacing: 3) {
                if let prefix {
                    Text(prefix)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                TextField("0", text: text)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
    }

    // MARK: Usage history

    private func filteredEntries(_ client: Client) -> [LedgerEntry] {
        let base = profile.ledger(for: client).filter { historyFilter.matches($0) }
        return newestFirst ? base.sorted { $0.date > $1.date } : base.sorted { $0.date < $1.date }
    }

    private func usageHistory(_ client: Client) -> some View {
        let entries = filteredEntries(client)
        let visible = showAllHistory ? entries : Array(entries.prefix(historyPreviewCount))
        return SectionCard(title: "Usage History", icon: "clock.arrow.circlepath") {
            VStack(spacing: 12) {
                filterRow
                if entries.isEmpty {
                    Text(emptyHistoryMessage)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            compactRow(entry)
                            if index < visible.count - 1 {
                                Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                            }
                        }
                    }
                    if entries.count > historyPreviewCount {
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { showAllHistory.toggle() }
                        } label: {
                            Text(showAllHistory ? "Show less" : "Show all \(entries.count)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.Color.accentInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Theme.Color.surfaceMuted, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyHistoryMessage: String {
        switch historyFilter {
        case .all:
            return isReadOnly
                ? "No activity yet. Package purchases and completed sessions will show here."
                : "No entries yet — add a package or log a session."
        case .packages:
            return isReadOnly
                ? "No packages yet. Your trainer adds these after you purchase a session pack."
                : "No packages yet — use the calculator above to add one."
        case .sessions:
            return "No completed sessions logged yet."
        case .adjustments:
            return "No manual adjustments yet."
        }
    }

    private var filterRow: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HistoryFilter.allCases) { item in
                        let isActive = item == historyFilter
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                historyFilter = item
                                showAllHistory = false
                            }
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(isActive ? Theme.Color.accent : Theme.Color.surfaceMuted, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { newestFirst.toggle() }
            } label: {
                Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func compactRow(_ entry: LedgerEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.kind.tint)
                .frame(width: 20)
            Text(entry.kind == .packageAdded ? "Package added" : entry.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(entry.delta > 0 ? Color(hex: 0x57C77B) : Theme.Color.ink)
                .frame(minWidth: 28, alignment: .trailing)
            if let amount = entry.amount {
                Text(String(format: "$%.0f", amount))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: Actions

    private func adjust(_ delta: Int, _ client: Client) {
        // Update the bank and toast immediately so the UI feels instant, then
        // sync with the backend and roll back if the request fails.
        clientStore.adjustSessionsRemaining(by: delta, for: client.id)
        let optimisticRemaining = clientStore.clients.first(where: { $0.id == client.id })?.sessionsRemaining ?? 0
        toast = ToastData(message: "Bank: \(optimisticRemaining) left", icon: delta > 0 ? "plus.circle.fill" : "minus.circle.fill")

        Task { @MainActor in
            guard let token = AuthStore.accessToken else {
                clientStore.adjustSessionsRemaining(by: -delta, for: client.id)
                return
            }
            let kind = delta > 0 ? "adjustment" : "usage"
            let title = delta > 0 ? "Manual Adjustment" : "Session Used"
            do {
                let event = try await VerraAPI.createFinancialEvent(
                    VerraAPI.CreateFinancialEventBody(
                        clientID: client.id,
                        kind: kind,
                        title: title,
                        detail: title,
                        amount: nil,
                        sessionDelta: delta
                    ),
                    accessToken: token
                )
                if let dto = try? await VerraAPI.fetchClients(accessToken: token).first(where: { $0.id == client.id }) {
                    clientStore.applyClientDTO(dto)
                }
                let entry = LedgerEntry(
                    id: event.id,
                    date: event.occurredAt,
                    title: event.title,
                    delta: event.sessionDelta,
                    amount: event.amount,
                    kind: delta > 0 ? .adjustment : .sessionUsed
                )
                profile.addLedgerEntry(entry, for: client.id)
            } catch {
                // Roll back the optimistic change since the server never confirmed it.
                clientStore.adjustSessionsRemaining(by: -delta, for: client.id)
                toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.circle.fill")
            }
        }
    }

    private func addPackage(_ client: Client) {
        let count = Int(countText) ?? 0
        let price = Double(priceText) ?? 0
        guard count > 0 else { return }

        // Optimistic bump — the calculator input is cleared right away too.
        clientStore.adjustSessionsRemaining(by: count, for: client.id)
        toast = ToastData(message: "Added \(count) sessions", icon: "plus.circle.fill")

        Task { @MainActor in
            guard let token = AuthStore.accessToken else {
                clientStore.adjustSessionsRemaining(by: -count, for: client.id)
                return
            }
            do {
                let event = try await VerraAPI.createFinancialEvent(
                    VerraAPI.CreateFinancialEventBody(
                        clientID: client.id,
                        kind: "income",
                        title: "Package Added",
                        detail: "Package Added",
                        amount: price > 0 ? price : nil,
                        sessionDelta: count
                    ),
                    accessToken: token
                )
                if let dto = try? await VerraAPI.fetchClients(accessToken: token).first(where: { $0.id == client.id }) {
                    clientStore.applyClientDTO(dto)
                }
                let entry = LedgerEntry(
                    id: event.id,
                    date: event.occurredAt,
                    title: event.title,
                    delta: event.sessionDelta,
                    amount: event.amount,
                    kind: .packageAdded
                )
                profile.addLedgerEntry(entry, for: client.id)
            } catch {
                // Roll back the optimistic bump since the server never confirmed it.
                clientStore.adjustSessionsRemaining(by: -count, for: client.id)
                toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.circle.fill")
            }
        }
    }
}
