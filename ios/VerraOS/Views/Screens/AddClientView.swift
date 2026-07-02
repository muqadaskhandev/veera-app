//
//  AddClientView.swift
//  VerraOS
//

import SwiftUI

/// Invite a new client, optionally pre-filling their profile to reduce
/// onboarding friction. Adds the client to the roster as Pending.
struct AddClientView: View {
    @Environment(ClientStore.self) private var store
    @Environment(TrainerStore.self) private var trainer
    @Environment(\.dismiss) private var dismiss

    private var unit: WeightUnit { trainer.units }

    var onInvited: (String) -> Void

    @State private var name: String = ""
    @State private var channel: InviteChannel = .email
    @State private var contact: String = ""

    @State private var preFill: Bool = false
    @State private var age: String = ""
    @State private var gender: String = ""
    @State private var height: String = ""
    @State private var weight: String = ""
    @State private var injuries: String = ""
    @State private var goal: String = ""
    @State private var skill: String = "Beginner"
    @State private var sessionBalance: Int = 8
    @State private var isInviting = false

    private let skillLevels = ["Beginner", "Intermediate", "Advanced"]

    private var canInvite: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !contact.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    contactSection
                    channelSection
                    preFillToggle
                    if preFill { preFillFields }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.background)
            .navigationTitle("Add Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite", action: invite)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canInvite && !isInviting ? Theme.Color.ink : Theme.Color.inkFaint)
                        .disabled(!canInvite || isInviting)
                }
            }
        }
    }

    // MARK: Sections

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Client Name")
            field("Full name", text: $name)
                .textInputAutocapitalization(.words)
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Invite Via")
            HStack(spacing: 6) {
                ForEach(InviteChannel.allCases) { item in
                    let isActive = item == channel
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { channel = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item == .email ? "envelope.fill" : "message.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(item.label)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(isActive ? Theme.Color.accent : Theme.Color.surface, in: Capsule())
                        .overlay(Capsule().stroke(isActive ? .clear : Theme.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            field(channel == .email ? "name@email.com" : "Phone number", text: $contact)
                .keyboardType(channel == .email ? .emailAddress : .phonePad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var preFillToggle: some View {
        Toggle(isOn: $preFill.animation(.spring(response: 0.34, dampingFraction: 0.84))) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pre-fill their profile now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                Text("Save them a step — their data is ready on first login.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
        }
        .tint(Theme.Color.accent)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var preFillFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Demographics")
                HStack(spacing: 10) {
                    field("Age", text: $age).keyboardType(.numberPad)
                    field("Gender", text: $gender)
                }
                field("Height (cm)", text: $height).keyboardType(.numberPad)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Starting Point")
                field("Current weight (\(unit.short))", text: $weight).keyboardType(.numberPad)
                field("Injury history", text: $injuries, axis: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Goals")
                field("Primary goal (e.g. Fat Loss)", text: $goal)
                skillPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Session Balance")
                stepperRow
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var skillPicker: some View {
        HStack(spacing: 6) {
            ForEach(skillLevels, id: \.self) { level in
                let isActive = level == skill
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { skill = level }
                } label: {
                    Text(level)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isActive ? Theme.Color.accent : Theme.Color.surface, in: Capsule())
                        .overlay(Capsule().stroke(isActive ? .clear : Theme.Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stepperRow: some View {
        HStack {
            Text("\(sessionBalance)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text("pre-paid sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
            Spacer()
            HStack(spacing: 4) {
                stepButton("minus") { sessionBalance = max(0, sessionBalance - 1) }
                stepButton("plus") { sessionBalance = min(99, sessionBalance + 1) }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 36, height: 36)
                .background(Theme.Color.accent, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Reusable field

    private func field(_ placeholder: String, text: Binding<String>, axis: Bool = false) -> some View {
        Group {
            if axis {
                TextField(placeholder, text: text, axis: .vertical).lineLimit(2...4)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: Actions

    private func invite() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let contactValue = contact.trimmingCharacters(in: .whitespaces)

        Task {
            isInviting = true
            defer { isInviting = false }

            guard let token = AuthStore.accessToken else {
                onInvited("Sign in again to send invites")
                return
            }

            do {
                let response = try await VerraAPI.createInvite(
                    clientEmail: channel == .email ? contactValue : nil,
                    clientName: trimmed,
                    clientPhone: channel == .sms ? contactValue : nil,
                    sessionsRemaining: preFill ? sessionBalance : 0,
                    age: preFill ? Int(age) : nil,
                    gender: preFill && !gender.isEmpty ? gender : nil,
                    heightCm: preFill ? Int(height) : nil,
                    weightKg: preFill ? weightInKg : nil,
                    injuryHistory: preFill && !injuries.isEmpty ? injuries : nil,
                    primaryGoal: preFill && !goal.isEmpty ? goal : nil,
                    skillLevel: preFill ? skill : nil,
                    accessToken: token
                )

                if let saved = response.client {
                    let client = ClientLoader.client(from: saved)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        if let index = store.clients.firstIndex(where: { $0.id == client.id }) {
                            store.clients[index] = client
                        } else {
                            store.add(client)
                        }
                    }
                } else {
                    await store.refreshFromServer()
                }

                if channel == .email && response.emailSent {
                    onInvited("Invite email sent to \(trimmed.split(separator: " ").first.map(String.init) ?? trimmed)")
                } else if channel == .email {
                    onInvited("Invite created for \(trimmed.split(separator: " ").first.map(String.init) ?? trimmed)")
                } else {
                    onInvited("Invite saved for \(trimmed.split(separator: " ").first.map(String.init) ?? trimmed) — share the code via \(channel.label)")
                }
                dismiss()
            } catch {
                onInvited("Could not save invite — \(error.localizedDescription)")
            }
        }
    }

    /// Parses the entered weight (in the trainer's unit) and converts it to kg.
    private var weightInKg: Int? {
        guard let value = Double(weight.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return Int(unit.toKg(value).rounded())
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }
}
