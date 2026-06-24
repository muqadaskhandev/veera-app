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
        .toast($toast)
    }

    private func content(_ client: Client) -> some View {
        VStack(spacing: 0) {
            ProfileTopBar(title: "Financials", subtitle: client.name.firstWord, onBack: onBack)
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    sessionBank(client)
                    if !isReadOnly { packageCalculator(client) }
                    usageHistory(client)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: Session bank

    private func sessionBank(_ client: Client) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("SESSION BANK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.accent.opacity(0.8))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(client.sessionsRemaining)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: client.sessionsRemaining)
                    Text("left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.background.opacity(0.7))
                }
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
                    Text(pricePerSession > 0 ? String(format: "$%.2f", pricePerSession) : "—")
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
                    Text("No entries for this filter.")
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
            Text(entry.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkFaint)
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
        clientStore.adjustSessions(by: delta, for: client.id)
        guard let updated = self.client else { return }
        let entry = LedgerEntry(
            date: Date(),
            title: delta > 0 ? "Manual Adjustment" : "Session Used",
            delta: delta,
            kind: delta > 0 ? .adjustment : .sessionUsed
        )
        profile.addLedgerEntry(entry, for: client.id)
        toast = ToastData(message: "Bank: \(updated.sessionsRemaining) left", icon: delta > 0 ? "plus.circle.fill" : "minus.circle.fill")
    }

    private func addPackage(_ client: Client) {
        let count = Int(countText) ?? 0
        let price = Double(priceText) ?? 0
        guard count > 0 else { return }
        clientStore.adjustSessions(by: count, for: client.id)
        let entry = LedgerEntry(
            date: Date(),
            title: "Package Added",
            delta: count,
            amount: price,
            kind: .packageAdded
        )
        profile.addLedgerEntry(entry, for: client.id)
        toast = ToastData(message: "Added \(count) sessions", icon: "plus.circle.fill")
    }
}
