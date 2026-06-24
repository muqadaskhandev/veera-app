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
    let clientName: String

    @Environment(ScheduleStore.self) private var store
    @Environment(ClientStore.self) private var clientStore

    @State private var selectedDay: Int = 17
    @State private var mode: ScheduleMode = .day
    @State private var detailSession: Session?
    @State private var toast: ToastData?

    private let week: [(day: String, date: Int)] = [
        ("Mon", 15), ("Tue", 16), ("Wed", 17), ("Thu", 18), ("Fri", 19), ("Sat", 20), ("Sun", 21)
    ]

    /// Only this client's sessions.
    private var mySessions: [Session] {
        store.sessions.filter { $0.clientName == clientName }
    }

    private var daySessions: [Session] {
        mySessions.filter { $0.dayOfMonth == selectedDay }.sorted { $0.startMinutes < $1.startMinutes }
    }

    private var weeklyCount: Int {
        mySessions.filter { (15...21).contains($0.dayOfMonth) && !$0.isSkipped }.count
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
            .padding(.bottom, 110)
        }
        .toast($toast)
        .sheet(item: $detailSession) { session in
            detailCard(for: session)
        }
        .onAppear { store.reconcilePastSessions(clientStore: clientStore) }
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
                    Text(weeklyCount == 1 ? "session" : "sessions")
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
                selectedDay: $selectedDay,
                sessions: daySessions,
                onSelectSession: { detailSession = $0 }
            )
        case .month:
            MonthGridView(sessions: mySessions, selectedDay: selectedDay) { day in
                selectedDay = day
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { mode = .day }
            }
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
