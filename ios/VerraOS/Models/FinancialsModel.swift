//
//  FinancialsModel.swift
//  VerraOS
//

import SwiftUI

/// Global time window for the Financials scoreboard, trend chart, and ledger.
enum FinTimeFilter: String, CaseIterable, Identifiable {
    case week = "This Week"
    case month = "This Month"
    case ytd = "YTD"
    case all = "All Time"

    var id: String { rawValue }

    /// Compact label for the segmented control.
    var short: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .ytd: return "YTD"
        case .all: return "All"
        }
    }

    /// API query parameter for `/api/financials`.
    var apiFilter: String {
        switch self {
        case .week: return "week"
        case .month: return "month"
        case .ytd: return "ytd"
        case .all: return "all"
        }
    }

    /// Whether the given date falls inside this window, relative to `now`.
    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .week:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= weekAgo && date <= now
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .ytd:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now) && date <= now
        case .all:
            return date <= now
        }
    }
}

/// The nature of a financial event in the master ledger.
enum FinEventKind: Equatable {
    case income
    case usage
    case credit
    case comp

    var tint: Color {
        switch self {
        case .income: return Color(hex: 0x57C77B)
        case .usage: return Theme.Color.inkMuted
        case .credit: return Color(hex: 0xE8893C)
        case .comp: return Theme.Color.inkFaint
        }
    }

    var icon: String {
        switch self {
        case .income: return "plus.circle.fill"
        case .usage: return "minus.circle.fill"
        case .credit: return "slider.horizontal.3"
        case .comp: return "gift.fill"
        }
    }
}

/// Chip filter that narrows the master ledger to a single kind of event.
enum LedgerKindFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case usage
    case credit
    case comp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .income: return "Income"
        case .usage: return "Sessions"
        case .credit: return "Credits"
        case .comp: return "Free / Comps"
        }
    }

    /// Whether the given event kind passes this filter.
    func matches(_ kind: FinEventKind) -> Bool {
        switch self {
        case .all: return true
        case .income: return kind == .income
        case .usage: return kind == .usage
        case .credit: return kind == .credit
        case .comp: return kind == .comp
        }
    }
}

/// A single chronological entry in the read-only master ledger, aggregated from
/// every client profile and the schedule.
struct FinEvent: Identifiable {
    let id: UUID
    let date: Date
    let clientName: String
    let detail: String
    let amount: Double?
    let kind: FinEventKind

    init(id: UUID = UUID(), date: Date, clientName: String, detail: String, amount: Double?, kind: FinEventKind) {
        self.id = id
        self.date = date
        self.clientName = clientName
        self.detail = detail
        self.amount = amount
        self.kind = kind
    }

    /// Maps a per-client ledger row into a trainer dashboard event.
    static func from(ledger entry: LedgerEntry, clientName: String) -> FinEvent? {
        switch entry.kind {
        case .packageAdded:
            let detail = entry.delta > 0 ? "bought \(entry.delta)-Pack" : entry.title
            return FinEvent(
                id: entry.id,
                date: entry.date,
                clientName: clientName,
                detail: detail,
                amount: entry.amount,
                kind: .income
            )
        case .sessionUsed:
            return FinEvent(
                id: entry.id,
                date: entry.date,
                clientName: clientName,
                detail: "Session Used",
                amount: nil,
                kind: .usage
            )
        case .adjustment:
            let detail = entry.delta > 0
                ? "Manual credit (+\(entry.delta))"
                : "Manual adjustment (\(entry.delta))"
            return FinEvent(
                id: entry.id,
                date: entry.date,
                clientName: clientName,
                detail: detail,
                amount: entry.amount,
                kind: .credit
            )
        }
    }
}

/// One column of the Income-vs-Volume trend chart.
struct FinBucket: Identifiable {
    let id = UUID()
    let label: String
    var revenue: Double
    var sessions: Int
}
