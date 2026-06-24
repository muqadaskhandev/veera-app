//
//  ClientProfileView.swift
//  VerraOS
//
//  Level 2 — the individual client hub. Header identity + biometrics + session
//  bank, a grid of active module tiles, and a settings gear to show/hide
//  modules per client.
//

import SwiftUI

/// Route value used to push a specific module screen for a client.
struct ModuleRoute: Hashable {
    let clientID: UUID
    let module: ProfileModule
}

struct ClientProfileView: View {
    let clientID: UUID
    var onBack: () -> Void

    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile

    @State private var showingSettings = false
    @State private var showingNote = false
    @State private var showingBiometrics = false
    @State private var toast: ToastData?

    /// Live client lookup so the header reflects edits / session-bank changes.
    private var client: Client? {
        clientStore.clients.first { $0.id == clientID }
    }

    var body: some View {
        Group {
            if let client {
                content(for: client)
            } else {
                VStack { Spacer(); Text("Client unavailable").foregroundStyle(Theme.Color.inkMuted); Spacer() }
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
        .sheet(isPresented: $showingNote) {
            if let client {
                ClientNoteSheet(clientID: client.id, name: client.name) { message in
                    toast = message
                }
            }
        }
        .sheet(isPresented: $showingBiometrics) {
            if let client {
                EditBiometricsSheet(clientID: client.id) { message in
                    toast = message
                }
            }
        }
    }

    private func content(for client: Client) -> some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: client.name,
                subtitle: client.effectiveStatus.label,
                trailing: AnyView(settingsButton),
                onBack: onBack
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    identityHeader(client)
                    biometrics(client)
                    sessionBank(client)
                    if showingSettings { moduleSettings(client) }
                    moduleGrid(client)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
    }

    private var settingsButton: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { showingSettings.toggle() }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(showingSettings ? Theme.Color.accentInk : Theme.Color.ink)
                .frame(width: 42, height: 42)
                .background(showingSettings ? Theme.Color.accent : Theme.Color.surface, in: Circle())
                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: showingSettings ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Identity

    private func identityHeader(_ client: Client) -> some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Theme.Color.ink)
                .frame(width: 92, height: 92)
                .overlay(
                    Text(client.initials)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                )
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(client.effectiveStatus.tint)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 3))
                }
                .cardShadow(0.8)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(client.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Button {
                        showingNote = true
                    } label: {
                        Image(systemName: client.note.isEmpty ? "note.text" : "note.text.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(client.note.isEmpty ? Theme.Color.inkMuted : Theme.Color.accentInk)
                            .frame(width: 32, height: 32)
                            .background(client.note.isEmpty ? Theme.Color.surface : Theme.Color.accent, in: Circle())
                            .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: client.note.isEmpty ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Client notes")
                }
                if !client.skillLevel.isEmpty {
                    Text(client.skillLevel.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.Color.accent, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Biometrics

    private func biometrics(_ client: Client) -> some View {
        let start = client.weightKg.map { "\($0) kg" } ?? "—"
        let goalValue = profile.weightTargets(for: client).goal
        let goal = goalValue.map { "\(Int($0)) kg" } ?? "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DETAILS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.inkFaint)
                Spacer()
                Button {
                    showingBiometrics = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                        Text("Edit")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                StatCell(label: "Age", value: client.age.map { "\($0)" } ?? "—")
                StatCell(label: "Height", value: client.heightCm.map { Client.formatHeightImperial(cm: $0) } ?? "—")
                StatCell(label: "Start", value: start)
                StatCell(label: "Goal", value: goal)
            }
        }
    }

    // MARK: Session bank

    private func sessionBank(_ client: Client) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION BANK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.accent.opacity(0.8))
                Text("Synced with schedule")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(client.sessionsRemaining)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: client.sessionsRemaining)
                Text("left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.background.opacity(0.7))
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardShadow()
    }

    // MARK: Module settings

    private func moduleSettings(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VISIBLE MODULES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.Color.inkFaint)
            ForEach(ProfileModule.allCases) { module in
                Toggle(isOn: Binding(
                    get: { profile.isVisible(module, for: client.id) },
                    set: { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            profile.toggle(module, for: client.id)
                        }
                        let on = profile.isVisible(module, for: client.id)
                        toast = ToastData(message: "\(module.title) \(on ? "shown" : "hidden")", icon: on ? "eye.fill" : "eye.slash.fill")
                    }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: module.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .frame(width: 22)
                        Text(module.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                    }
                }
                .tint(Theme.Color.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Module grid

    private func moduleGrid(_ client: Client) -> some View {
        let modules = profile.orderedVisibleModules(for: client.id)
        return VStack(alignment: .leading, spacing: 10) {
            if modules.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text("No modules enabled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Text("Tap the settings gear to turn modules on.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(modules) { module in
                        NavigationLink(value: ModuleRoute(clientID: client.id, module: module)) {
                            ModuleTile(module: module)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ModuleTile: View {
    let module: ProfileModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 42, height: 42)
                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                Text(module.subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }
}

// MARK: - Client note sheet

/// A free-form note editor for a single client, persisted to the ClientStore.
private struct ClientNoteSheet: View {
    let clientID: UUID
    let name: String
    var onSaved: (ToastData) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ClientStore.self) private var clientStore

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var client: Client? { clientStore.clients.first { $0.id == clientID } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Private note — only you can see this.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)

                TextField("Add a note about \(name.firstWord)…", text: $draft, axis: .vertical)
                    .font(.system(size: 15.5, weight: .medium))
                    .lineLimit(6...12)
                    .focused($focused)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.background)
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.bold)
                }
            }
        }
        .onAppear {
            draft = client?.note ?? ""
            focused = true
        }
    }

    private func save() {
        clientStore.setNote(draft.trimmingCharacters(in: .whitespacesAndNewlines), forID: clientID)
        onSaved(ToastData(message: "Note saved", icon: "note.text"))
        dismiss()
    }
}

// MARK: - Edit biometrics sheet

/// Editable Age, Height, Start Weight, and Goal Weight for a client.
private struct EditBiometricsSheet: View {
    let clientID: UUID
    var onSaved: (ToastData) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile

    @State private var age: String = ""
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var startWeight: String = ""
    @State private var goalWeight: String = ""

    private var client: Client? { clientStore.clients.first { $0.id == clientID } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    field(label: "Age", unit: "yrs", text: $age)
                    heightField
                    field(label: "Start Weight", unit: "kg", text: $startWeight)
                    field(label: "Goal Weight", unit: "kg", text: $goalWeight)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.bold)
                }
            }
        }
        .onAppear { populate() }
    }

    private var heightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEIGHT")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.inkFaint)
            HStack(spacing: Theme.Spacing.sm) {
                unitBox(text: $heightFeet, unit: "ft")
                unitBox(text: $heightInches, unit: "in")
            }
        }
    }

    private func unitBox(text: Binding<String>, unit: String) -> some View {
        HStack {
            TextField("—", text: text)
                .font(.system(size: 17, weight: .semibold))
                .keyboardType(.numberPad)
            Text(unit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func field(label: String, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Theme.Color.inkFaint)
            HStack {
                TextField("—", text: text)
                    .font(.system(size: 17, weight: .semibold))
                    .keyboardType(.numberPad)
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 13)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private func populate() {
        guard let client else { return }
        age = client.age.map { "\($0)" } ?? ""
        if let cm = client.heightCm {
            let totalInches = Int((Double(cm) / 2.54).rounded())
            heightFeet = "\(totalInches / 12)"
            heightInches = "\(totalInches % 12)"
        }
        startWeight = client.weightKg.map { "\($0)" } ?? ""
        let goal = profile.weightTargets(for: client).goal
        goalWeight = goal.map { "\(Int($0))" } ?? ""
    }

    private func save() {
        guard let client else { return }
        let newWeight = Int(startWeight.trimmingCharacters(in: .whitespaces))
        let feet = Int(heightFeet.trimmingCharacters(in: .whitespaces))
        let inches = Int(heightInches.trimmingCharacters(in: .whitespaces))
        let newHeight: Int? = (feet != nil || inches != nil)
            ? Client.cm(fromFeet: feet ?? 0, inches: inches ?? 0)
            : nil
        clientStore.updateBiometrics(
            age: Int(age.trimmingCharacters(in: .whitespaces)),
            heightCm: newHeight,
            weightKg: newWeight,
            for: clientID
        )
        let goal = Double(goalWeight.trimmingCharacters(in: .whitespaces))
        let existingStart = profile.weightTargets(for: client).start
        profile.setWeightTargets(start: existingStart, goal: goal, for: client)
        onSaved(ToastData(message: "Details updated", icon: "checkmark.circle.fill"))
        dismiss()
    }
}
