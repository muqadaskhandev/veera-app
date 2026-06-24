//
//  SessionDetailCard.swift
//  VerraOS
//

import SwiftUI

/// Sliding detail card for a tapped session: time, location, client, type, and
/// notes, plus quick actions (check-in, edit, text reminder, cancel) and a
/// stubbed view-profile link.
struct SessionDetailCard: View {
    let session: Session
    let remaining: Int?
    var onCheckIn: () -> Void
    var onEdit: () -> Void
    var onSendReminder: () -> Void
    var onCancel: () -> Void
    var onSkip: () -> Void
    var onUnskip: () -> Void
    /// When true, the card is shown to a client: only Skip / Cancel of their own
    /// session is offered (no Check In, Edit, Remind, or profile link).
    var clientMode: Bool = false

    @State private var confirmingCancel = false
    @State private var showingReminder = false
    @State private var showProfileNote = false

    private var isPersonal: Bool { session.accent == .personal }
    private var firstName: String { session.clientName.split(separator: " ").first.map(String.init) ?? session.clientName }
    private var reminderText: String {
        "Hey \(firstName), see you at \(Session.display(session.startMinutes))!"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                accentBar
                heading
                infoRows
                if !session.notes.isEmpty { notesBlock }
                actions
                if !isPersonal && !clientMode { viewProfile }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(Theme.Color.background)
    }

    private var accentBar: some View {
        Capsule()
            .fill(session.accent.tint)
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(session.accent.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(session.accent.tint)
                statusPill
            }
            Text(session.clientName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusPill: some View {
        let (label, icon, color): (String, String, Color) = {
            if session.isSkipped { return ("Skipped", "slash.circle.fill", Color(hex: 0xE08A3C)) }
            if session.isCompleted { return ("Checked in", "checkmark.seal.fill", Color(hex: 0x57C77B)) }
            return ("Scheduled", "calendar", Theme.Color.inkMuted)
        }()
        return Label(label, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var infoRows: some View {
        VStack(spacing: 0) {
            InfoRow(icon: "clock", label: "Time", value: session.timeRange)
            if let remaining, !isPersonal {
                divider
                InfoRow(icon: "ticket", label: "Package", value: "\(remaining) sessions left")
            }
        }
        .padding(.vertical, 4)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.leading, 50)
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.inkFaint)
            Text(session.notes)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if session.isSkipped {
                skippedBanner
            } else {
                if !isPersonal && !clientMode {
                    PrimaryActionButton(
                        title: session.isCompleted ? "Checked In" : "Check In",
                        icon: session.isCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                        disabled: session.isCompleted,
                        action: onCheckIn
                    )
                }
                if !clientMode {
                    HStack(spacing: Theme.Spacing.sm) {
                        SecondaryActionButton(title: "Edit", icon: "pencil", action: onEdit)
                        if !isPersonal {
                            SecondaryActionButton(title: "Remind", icon: "message") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showingReminder = true }
                            }
                        }
                    }
                    if showingReminder { reminderPreview }
                }
                if !isPersonal {
                    Button {
                        onSkip()
                    } label: {
                        Label("Skip Session", systemImage: "slash.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xE08A3C))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(hex: 0xE08A3C).opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if confirmingCancel {
                    cancelConfirm
                } else {
                    Button(role: .destructive) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { confirmingCancel = true }
                    } label: {
                        Label("Cancel Session", systemImage: "xmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Color.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var skippedBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE08A3C))
                Text("This session is skipped — it won't count against \(firstName)'s package.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUnskip) {
                Label("Un-skip Session", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Color.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Color(hex: 0xE08A3C).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var reminderPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEXT REMINDER")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.inkFaint)
            Text(reminderText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xE4F0FC), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: Theme.Spacing.sm) {
                Button("Dismiss") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showingReminder = false }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Theme.Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                .buttonStyle(.plain)

                Button(action: onSendReminder) {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var cancelConfirm: some View {
        VStack(spacing: 12) {
            Text(clientMode ? "Cancel this session? Your trainer will be notified." : "Cancel this session? The client will be notified.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.sm) {
                Button("Keep") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { confirmingCancel = false }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Cancel Session")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.Color.danger, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var viewProfile: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showProfileNote = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("View \(firstName)'s Profile")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 14)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if showProfileNote {
                Text("Client profiles coming soon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Building blocks

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 14)
    }
}

private struct PrimaryActionButton: View {
    let title: String
    let icon: String
    var disabled: Bool = false
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(disabled ? Theme.Color.inkMuted : Theme.Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(disabled ? Theme.Color.surfaceMuted : Theme.Color.accent, in: Capsule())
                .scaleEffect(pressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { pressed = false } }
        )
    }
}

private struct SecondaryActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                .scaleEffect(pressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { pressed = false } }
        )
    }
}
