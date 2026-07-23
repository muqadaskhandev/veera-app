//
//  ClientScheduleView.swift
//  VerraOS
//
//  The client's schedule — a clone of the trainer's Day / Month calendar,
//  filtered to just this client's own sessions. They can skip or cancel an
//  upcoming session, but cannot create or edit appointments.
//

import SwiftUI

struct ClientScheduleView: View {
    let clientID: UUID
    let clientName: String

    @Environment(ScheduleStore.self) private var store
    @Environment(ClientStore.self) private var clientStore

    @State private var selectedDate = Date()
    @State private var monthAnchor = Date()
    @State private var mode: ScheduleMode = .day
    @State private var detailSession: Session?
    @State private var toast: ToastData?

    private var week: [Date] { ScheduleCalendar.week(containing: selectedDate) }

    /// Only this client's sessions.
    private var mySessions: [Session] {
        store.sessions.filter { session in
            if let sessionClientID = session.clientID {
                return sessionClientID == clientID
            }
            return session.clientName == clientName
        }
    }

    private var daySessions: [Session] {
        ScheduleCalendar.sessions(mySessions, on: selectedDate)
    }

    private var weeklyCount: Int {
        ScheduleCalendar.sessionsInWeek(mySessions, containing: selectedDate)
            .filter { !$0.isSkipped }
            .count
    }

    private var weekSessions: [Session] {
        ScheduleCalendar.sessionsInWeek(mySessions, containing: selectedDate)
    }

    private var nextUpcoming: Session? {
        let now = Date()
        return mySessions
            .filter { !$0.isCompleted && !$0.isSkipped && $0.scheduledAt >= Calendar.current.startOfDay(for: now) }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                summaryCard
                switcherRow
                calendar
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        .tabScrollContent()
        .toast($toast)
        .sheet(item: $detailSession) { session in
            detailCard(for: session)
        }
        .task {
            store.reconcilePastSessions(clientStore: clientStore)
            await store.refreshFromServer()
            focusOnRelevantDay()
        }
    }

    /// Open on today when it has sessions; otherwise jump to the next booked day
    /// so a Monday appointment isn't hidden behind Sunday's empty day strip.
    private func focusOnRelevantDay() {
        let calendar = Calendar.current
        let today = Date()
        let todaySessions = ScheduleCalendar.sessions(mySessions, on: today, calendar: calendar)
            .filter { !$0.isSkipped }
        if !todaySessions.isEmpty {
            selectedDate = today
            monthAnchor = today
            return
        }
        if let next = nextUpcoming {
            selectedDate = next.scheduledAt
            monthAnchor = next.scheduledAt
        } else {
            selectedDate = today
            monthAnchor = today
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
            Text("Training Schedule")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Color.background.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(weeklyCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.background)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: weeklyCount)
                    Text(weeklyCount == 1 ? "appointment scheduled" : "appointments scheduled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.background.opacity(0.6))
                }
            }
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardShadow()
    }

    private var switcherRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ClientModeSwitcher(mode: $mode)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var calendar: some View {
        switch mode {
        case .day:
            DayTimelineView(
                week: week,
                selectedDate: $selectedDate,
                sessions: daySessions,
                weekSessions: weekSessions,
                onSelectSession: { detailSession = $0 }
            )
        case .month:
            MonthGridView(
                sessions: mySessions,
                monthAnchor: monthAnchor,
                selectedDate: selectedDate,
                onSelectDate: { date in
                    selectedDate = date
                    monthAnchor = date
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { mode = .day }
                },
                onChangeMonth: { next in
                    let cal = Calendar.current
                    let delta = cal.dateComponents([.month], from: monthAnchor, to: next).month ?? 0
                    monthAnchor = next
                    selectedDate = cal.date(byAdding: .month, value: delta, to: selectedDate) ?? next
                }
            )
        }
    }

    private func detailCard(for session: Session) -> some View {
        let live = store.sessions.first { $0.id == session.id } ?? session
        return SessionDetailCard(
            session: live,
            remaining: store.remainingSessions(for: live),
            onCheckIn: {},
            onEdit: {},
            onSendReminder: {},
            onCancel: {
                store.cancel(live)
                toast = ToastData(message: "Session cancelled · your trainer was notified", icon: "xmark.circle.fill")
                detailSession = nil
            },
            onSkip: {
                store.skip(live, clientStore: clientStore)
                toast = ToastData(message: "Session skipped", icon: "slash.circle.fill")
                detailSession = nil
            },
            onUnskip: {
                store.unskip(live)
                toast = ToastData(message: "Session restored", icon: "arrow.uturn.backward")
                detailSession = nil
            },
            clientMode: true
        )
    }
}

// MARK: - Mode switcher

private struct ClientModeSwitcher: View {
    @Binding var mode: ScheduleMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleMode.allCases) { item in
                let isActive = item == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { mode = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if isActive {
                                Capsule()
                                    .fill(Theme.Color.accent)
                                    .matchedGeometryEffect(id: "clientModePill", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Color.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
    }
}
