//
//  FinancialsView.swift
//  VerraOS
//
//  The Financials tab: a live business scoreboard, an income-vs-volume trend
//  chart, and an automatic master ledger aggregated from every client profile
//  and the schedule. All numbers are derived — nothing is entered twice.
//

import SwiftUI

struct FinancialsView: View {
    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile
    @Environment(ScheduleStore.self) private var schedule

    @State private var filter: FinTimeFilter = .all
    @State private var ledgerKind: LedgerKindFilter = .all
    @State private var ledgerExpanded: Bool = false

    /// How many entries to preview while the ledger is collapsed.
    private let ledgerPreviewCount = 4

    // MARK: Derived data

    /// Every financial event across all clients + consult comps, newest first.
    private var allEvents: [FinEvent] {
        var events: [FinEvent] = []

        for client in clientStore.clients {
            for entry in profile.ledgerSnapshot(for: client) {
                switch entry.kind {
                case .packageAdded:
                    events.append(FinEvent(
                        date: entry.date,
                        clientName: client.name,
                        detail: "bought \(entry.delta)-Pack",
                        amount: entry.amount,
                        kind: .income
                    ))
                case .sessionUsed:
                    events.append(FinEvent(
                        date: entry.date,
                        clientName: client.name,
                        detail: "Session Used",
                        amount: nil,
                        kind: .usage
                    ))
                case .adjustment:
                    continue
                }
            }
        }

        // Free consultations from the schedule count as comps ($0).
        for session in schedule.sessions where session.accent == .consult {
            events.append(FinEvent(
                date: sessionDate(session),
                clientName: session.clientName,
                detail: "Consult",
                amount: 0,
                kind: .comp
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    private var filteredEvents: [FinEvent] {
        allEvents.filter { filter.contains($0.date) }
    }

    /// Events after applying both the time window and the ledger kind chip.
    private var ledgerEvents: [FinEvent] {
        filteredEvents.filter { ledgerKind.matches($0.kind) }
    }

    /// The slice actually rendered — capped to the preview count when collapsed.
    private var visibleLedgerEvents: [FinEvent] {
        ledgerExpanded ? ledgerEvents : Array(ledgerEvents.prefix(ledgerPreviewCount))
    }

    private var totalRevenue: Double {
        filteredEvents.filter { $0.kind == .income }.compactMap(\.amount).reduce(0, +)
    }

    private var totalVolume: Int {
        filteredEvents.filter { $0.kind == .usage }.count
    }

    private var totalComps: Int {
        filteredEvents.filter { $0.kind == .comp }.count
    }

    private var avgPrice: Double {
        totalVolume > 0 ? totalRevenue / Double(totalVolume) : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.md) {
                filterBar
                scoreboard
                trendCard
                ledgerCard
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 110)
        }
        .background(Theme.Color.background)
    }

    // MARK: Time filter

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(FinTimeFilter.allCases) { option in
                let isSelected = filter == option
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { filter = option }
                } label: {
                    Text(option.short)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.Color.accent)
                                    .matchedGeometryEffect(id: "filterPill", in: filterNS)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Color.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }

    @Namespace private var filterNS

    // MARK: Scoreboard

    private var scoreboard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                BigStatCard(
                    label: "Total Revenue",
                    value: currency(totalRevenue, fraction: 0),
                    caption: "Packages sold",
                    icon: "dollarsign.circle.fill",
                    style: .accentDark
                )
                BigStatCard(
                    label: "Total Volume",
                    value: "\(totalVolume)",
                    caption: totalVolume == 1 ? "Session done" : "Sessions done",
                    icon: "checkmark.seal.fill",
                    style: .surface
                )
            }
            HStack(spacing: Theme.Spacing.sm) {
                BigStatCard(
                    label: "Freebies / Comps",
                    value: "\(totalComps)",
                    caption: "Free consults",
                    icon: "gift.fill",
                    style: .surface
                )
                BigStatCard(
                    label: "Avg / Session",
                    value: avgPrice > 0 ? currency(avgPrice, fraction: 2) : "—",
                    caption: "Are you charging enough?",
                    icon: "chart.line.uptrend.xyaxis",
                    style: .surface
                )
            }
        }
    }

    // MARK: Trend chart

    private var trendCard: some View {
        SectionCard(title: "Income vs. Volume", icon: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    legendDot(color: Color(hex: 0x57C77B), label: "Revenue $")
                    legendDot(color: Color(hex: 0x6FB3F2), label: "Sessions", line: true)
                    Spacer()
                }
                DualTrendChart(buckets: buckets)
                Text("See if you're working harder but earning less.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
        }
    }

    private func legendDot(color: Color, label: String, line: Bool = false) -> some View {
        HStack(spacing: 6) {
            if line {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 16, height: 3)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 11, height: 11)
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        }
    }

    // MARK: Master ledger

    private var ledgerCard: some View {
        SectionCard(title: "Master Ledger", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                ledgerKindChips

                if ledgerEvents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkFaint)
                        Text(ledgerKind == .all ? "No transactions in this period" : "No \(ledgerKind.label.lowercased()) in this period")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleLedgerEvents.enumerated()), id: \.element.id) { index, event in
                            ledgerRow(event)
                            if index < visibleLedgerEvents.count - 1 {
                                Rectangle().fill(Theme.Color.hairline).frame(height: 1)
                            }
                        }
                    }

                    if ledgerEvents.count > ledgerPreviewCount {
                        ledgerToggle
                    }

                    Text("Automatic — adding a package inside a client's profile appears here instantly.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
    }

    private var ledgerKindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LedgerKindFilter.allCases) { kind in
                    let isSelected = ledgerKind == kind
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            ledgerKind = kind
                            ledgerExpanded = false
                        }
                    } label: {
                        Text(kind.label)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Theme.Color.accent : Theme.Color.surfaceMuted,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : Theme.Color.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ledgerToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { ledgerExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(ledgerExpanded ? "Show less" : "Show all \(ledgerEvents.count)")
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: ledgerExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.Color.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func ledgerRow(_ event: FinEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(event.kind.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.clientName.firstWord) · \(event.detail)")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer(minLength: 6)
            ledgerAmount(event)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func ledgerAmount(_ event: FinEvent) -> some View {
        switch event.kind {
        case .income:
            Text("+\(currency(event.amount ?? 0, fraction: 0))")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x57C77B))
        case .usage:
            Text("1 Session")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        case .comp:
            Text("$0 Free")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
        }
    }

    // MARK: Helpers

    private func currency(_ value: Double, fraction: Int) -> String {
        let rounded = value.rounded(toPlaces: fraction)
        return rounded.formatted(.currency(code: "USD").precision(.fractionLength(fraction)))
    }

    /// Maps a schedule session (current month, by day-of-month) to a Date.
    private func sessionDate(_ session: Session) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.day = session.dayOfMonth
        comps.hour = session.startMinutes / 60
        comps.minute = session.startMinutes % 60
        return cal.date(from: comps) ?? Date()
    }

    // MARK: Trend buckets

    private var buckets: [FinBucket] {
        let cal = Calendar.current
        let now = Date()

        switch filter {
        case .week:
            // 7 daily buckets, oldest → today.
            return (0..<7).reversed().map { back in
                let day = cal.date(byAdding: .day, value: -back, to: now) ?? now
                let start = cal.startOfDay(for: day)
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                let label = day.formatted(.dateTime.weekday(.narrow))
                return bucket(label: label, start: start, end: end)
            }
        case .month:
            // Weekly slices of the current month.
            let comps = cal.dateComponents([.year, .month], from: now)
            let monthStart = cal.date(from: comps) ?? now
            return (0..<4).map { week in
                let start = cal.date(byAdding: .day, value: week * 7, to: monthStart) ?? monthStart
                let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
                return bucket(label: "W\(week + 1)", start: start, end: end)
            }
        case .ytd:
            // Months from January → current month.
            let year = cal.component(.year, from: now)
            let currentMonth = cal.component(.month, from: now)
            return (1...currentMonth).map { month in
                let start = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
                let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
                let label = start.formatted(.dateTime.month(.narrow))
                return bucket(label: label, start: start, end: end)
            }
        case .all:
            // Last 6 months including the current one.
            return (0..<6).reversed().map { back in
                let monthDate = cal.date(byAdding: .month, value: -back, to: now) ?? now
                let comps = cal.dateComponents([.year, .month], from: monthDate)
                let start = cal.date(from: comps) ?? monthDate
                let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
                let label = start.formatted(.dateTime.month(.narrow))
                return bucket(label: label, start: start, end: end)
            }
        }
    }

    private func bucket(label: String, start: Date, end: Date) -> FinBucket {
        let slice = allEvents.filter { $0.date >= start && $0.date < end }
        let revenue = slice.filter { $0.kind == .income }.compactMap(\.amount).reduce(0, +)
        let sessions = slice.filter { $0.kind == .usage }.count
        return FinBucket(label: label, revenue: revenue, sessions: sessions)
    }
}

// MARK: - Big stat card

private struct BigStatCard: View {
    enum Style { case accentDark, surface }

    let label: String
    let value: String
    let caption: String
    let icon: String
    let style: Style

    private var isDark: Bool { style == .accentDark }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(isDark ? Theme.Color.accent.opacity(0.85) : Theme.Color.inkFaint)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDark ? Theme.Color.accent : Theme.Color.inkFaint)
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(isDark ? Theme.Color.accent : Theme.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isDark ? Theme.Color.background.opacity(0.6) : Theme.Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            isDark ? Theme.Color.ink : Theme.Color.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isDark ? Color.clear : Theme.Color.hairline, lineWidth: 1)
        )
        .cardShadow(isDark ? 1 : 0.6)
    }
}

// MARK: - Dual trend chart

/// Green revenue bars with a blue completed-sessions line on a second scale.
private struct DualTrendChart: View {
    let buckets: [FinBucket]
    var height: CGFloat = 150

    private var maxRevenue: Double { max(buckets.map(\.revenue).max() ?? 1, 1) }
    private var maxSessions: Int { max(buckets.map(\.sessions).max() ?? 1, 1) }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let plotHeight = geo.size.height
                let count = max(buckets.count, 1)
                let slot = geo.size.width / CGFloat(count)
                let barWidth = min(slot * 0.5, 26)

                ZStack(alignment: .bottom) {
                    // Revenue bars
                    HStack(spacing: 0) {
                        ForEach(buckets) { b in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: 0x57C77B), Color(hex: 0x57C77B).opacity(0.55)],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .frame(
                                        width: barWidth,
                                        height: max(3, CGFloat(b.revenue / maxRevenue) * plotHeight)
                                    )
                            }
                            .frame(width: slot)
                        }
                    }

                    // Sessions line
                    let points: [CGPoint] = buckets.enumerated().map { index, b in
                        let x = slot * (CGFloat(index) + 0.5)
                        let y = plotHeight - CGFloat(Double(b.sessions) / Double(maxSessions)) * plotHeight
                        return CGPoint(x: x, y: y)
                    }
                    if points.count > 1 {
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Color(hex: 0x6FB3F2), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                        Circle()
                            .fill(Color(hex: 0x6FB3F2))
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 1.5))
                            .position(pt)
                    }
                }
            }
            .frame(height: height)

            HStack(spacing: 0) {
                ForEach(buckets) { b in
                    Text(b.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Rounding helper

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
