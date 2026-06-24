//
//  ScheduleCalendarViews.swift
//  VerraOS
//
//  Day / Week / Month renderings for the Schedule hub.
//

import SwiftUI

// MARK: - Day timeline

/// Minimalist vertical timeline: a week date strip plus color-coded session
/// blocks (time on the left, client name on the right).
struct DayTimelineView: View {
    let week: [(day: String, date: Int)]
    @Binding var selectedDay: Int
    let sessions: [Session]
    var onSelectSession: (Session) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            dateStrip
            if sessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(sessions) { session in
                        TimelineRow(session: session) { onSelectSession(session) }
                    }
                }
            }
        }
    }

    private var dateStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, item in
                let isActive = item.date == selectedDay
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedDay = item.date
                    }
                } label: {
                    VStack(spacing: 7) {
                        Text(item.day)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isActive ? Theme.Color.accentInk.opacity(0.7) : Theme.Color.inkFaint)
                        Text("\(item.date)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(isActive ? Theme.Color.accent : Theme.Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(isActive ? .clear : Theme.Color.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text("Rest day")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text("No sessions scheduled")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// A single minimalist timeline row: time on the left, tinted client block right.
private struct TimelineRow: View {
    let session: Session
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.start)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(timeMeridiem)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .frame(width: 48, alignment: .trailing)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(session.accent.tint)
                        .frame(width: 4)

                    Text(session.clientName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .strikethrough(session.isCompleted || session.isSkipped, color: Theme.Color.inkMuted)
                    Spacer(minLength: 0)
                    if session.isSkipped {
                        Text("Skipped")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0xE08A3C))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xE08A3C).opacity(0.16), in: Capsule())
                    } else if session.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: 0x57C77B))
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(session.accent.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .opacity(session.isSkipped ? 0.5 : 1)
            }
        }
        .buttonStyle(PressableRowStyle())
    }

    private var timeMeridiem: String {
        session.startMinutes < 720 ? "AM" : "PM"
    }
}

/// Button style that gives a subtle press scale without intercepting the
/// surrounding ScrollView's drag gesture.
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Month grid

/// A full month grid (June 2026) with colored dots under days that have
/// sessions. Tapping a day opens it in Day view.
struct MonthGridView: View {
    let sessions: [Session]
    let selectedDay: Int
    let onSelectDay: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]
    // June 1, 2026 is a Monday → no leading blanks.
    private let leadingBlanks = 0
    private let daysInMonth = 30

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("June 2026")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 46)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    MonthCell(
                        day: day,
                        isSelected: day == selectedDay,
                        tints: dotTints(for: day)
                    )
                    .onTapGesture { onSelectDay(day) }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Color.hairline, lineWidth: 1)
        )
        .cardShadow()
    }

    private func dotTints(for day: Int) -> [Color] {
        sessions
            .filter { $0.dayOfMonth == day }
            .sorted { $0.startMinutes < $1.startMinutes }
            .prefix(3)
            .map { $0.accent.tint }
    }
}

private struct MonthCell: View {
    let day: Int
    let isSelected: Bool
    let tints: [Color]

    var body: some View {
        VStack(spacing: 5) {
            Text("\(day)")
                .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.ink)

            HStack(spacing: 3) {
                ForEach(Array(tints.enumerated()), id: \.offset) { _, tint in
                    Circle().fill(tint).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(isSelected ? Theme.Color.accent : Color.clear)
        )
    }
}
