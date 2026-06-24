//
//  ScheduleView.swift
//  VerraOS
//

import SwiftUI

/// Density mode for the schedule calendar.
enum ScheduleMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case month = "Month"
    var id: String { rawValue }
}

/// Flagship screen: a quick-glance business dashboard, a Day/Week/Month view
/// switcher with calendar sync state, and a clean color-coded calendar.
struct ScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(ClientStore.self) private var clientStore
    @State private var selectedDay: Int = 17
    @State private var mode: ScheduleMode = .day

    @State private var detailSession: Session?
    @State private var editorSession: Session?
    @State private var showingEditor = false
    @State private var showingSync = false
    @State private var pendingEdit: Session?
    @State private var toast: ToastData?

    /// Mon–Sun for the visible week (June 15–21, 2026).
    private let week: [(day: String, date: Int)] = [
        ("Mon", 15), ("Tue", 16), ("Wed", 17), ("Thu", 18), ("Fri", 19), ("Sat", 20), ("Sun", 21)
    ]

    private var daySessions: [Session] { store.sessions(on: selectedDay) }

    private var weeklyVolume: Int {
        store.sessions.filter { (15...21).contains($0.dayOfMonth) }.count
    }

    /// Live remaining sessions for the selected day: scheduled, not skipped,
    /// not completed, and not yet elapsed — ordered by start time.
    private var remainingToday: [Session] {
        daySessions
            .filter { !$0.isCompleted && !$0.isSkipped && !store.hasPassed($0) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                greeting
                pacingHeader
                switcherRow
                calendar
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 96)
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .toast($toast)
        .sheet(item: $detailSession, onDismiss: presentPendingEdit) { session in
            detailCard(for: session)
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editorSession = nil }) {
            AddEditAppointmentView(existing: editorSession) { message in
                toast = ToastData(message: message)
            }
        }
        .sheet(isPresented: $showingSync) {
            CalendarSyncSettingsView()
        }
        .onAppear {
            store.reconcilePastSessions(clientStore: clientStore)
        }
    }

    // MARK: Floating add button

    private var addButton: some View {
        Button {
            editorSession = nil
            showingEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 58, height: 58)
                .background(Theme.Color.accent, in: Circle())
                .overlay(Circle().stroke(Theme.Color.accentInk.opacity(0.12), lineWidth: 1))
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityLabel("Add appointment")
    }

    // MARK: Detail card wiring

    private func detailCard(for session: Session) -> some View {
        let live = store.sessions.first { $0.id == session.id } ?? session
        return SessionDetailCard(
            session: live,
            remaining: store.remainingSessions(for: live),
            onCheckIn: {
                store.checkIn(live)
                toast = ToastData(message: "\(live.clientName) checked in")
                detailSession = nil
            },
            onEdit: {
                pendingEdit = live
                detailSession = nil
            },
            onSendReminder: {
                toast = ToastData(message: "Reminder sent", icon: "paperplane.fill")
                detailSession = nil
            },
            onCancel: {
                store.cancel(live)
                toast = ToastData(message: "Session cancelled · client notified", icon: "xmark.circle.fill")
                detailSession = nil
            },
            onSkip: {
                store.skip(live, clientStore: clientStore)
                toast = ToastData(message: "\(live.clientName) marked skipped", icon: "slash.circle.fill")
                detailSession = nil
            },
            onUnskip: {
                store.unskip(live)
                toast = ToastData(message: "\(live.clientName) restored to schedule", icon: "arrow.uturn.backward")
                detailSession = nil
            }
        )
    }

    private func presentPendingEdit() {
        guard let pending = pendingEdit else { return }
        pendingEdit = nil
        editorSession = pending
        showingEditor = true
    }

    // MARK: Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
            Text(timeOfDayGreeting)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Time-of-day greeting with no personal name.
    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: Pacing header (2-card dashboard)

    private var pacingHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            PacingCard(title: "Weekly Volume") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(weeklyVolume)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.background)
                    TrendBadge(isUp: true, value: 4)
                }
                Text("sessions this week")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.background.opacity(0.6))
            }
            .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))

            PacingCard(title: "Sessions Remaining") {
                Text(remainingToday.isEmpty ? "All done" : "\(remainingToday.count) Left")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: remainingToday.count)
                HStack(spacing: 5) {
                    Image(systemName: remainingToday.isEmpty ? "checkmark.circle" : "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(remainingToday.first.map { "Next: \(Session.display($0.startMinutes))" } ?? "No sessions left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Color.inkMuted)
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(Theme.Color.hairline, lineWidth: 1)
            )
            .cardShadow()
        }
    }

    // MARK: View switcher + sync

    private var switcherRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            ModeSwitcher(mode: $mode)
            Spacer(minLength: 0)
            Button {
                showingSync = true
            } label: {
                SyncIndicator(isSynced: store.isSynced)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Calendar (mode-driven)

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
            MonthGridView(sessions: store.sessions, selectedDay: selectedDay) { day in
                selectedDay = day
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    mode = .day
                }
            }
        }
    }
}

// MARK: - Pacing card shell

private struct PacingCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.Color.inkMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
    }
}

private struct TrendBadge: View {
    let isUp: Bool
    let value: Int

    private var color: Color { isUp ? Color(hex: 0x57C77B) : Theme.Color.danger }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .heavy))
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Mode switcher

private struct ModeSwitcher: View {
    @Binding var mode: ScheduleMode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScheduleMode.allCases) { item in
                let isActive = item == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        mode = item
                    }
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
                                    .matchedGeometryEffect(id: "modePill", in: ns)
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

private struct SyncIndicator: View {
    let isSynced: Bool

    private var color: Color { isSynced ? Color(hex: 0x57C77B) : Theme.Color.inkFaint }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(isSynced ? "Synced" : "Offline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.Color.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
    }
}
