//
//  EditProfileView.swift
//  VerraOS
//

import SwiftUI
import PhotosUI

/// Edit the trainer's client-facing profile plus private onboarding answers.
struct EditProfileView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TrainerProfile
    @State private var pickerItem: PhotosPickerItem?
    @State private var toast: ToastData?
    @State private var isSaving = false
    @State private var isLoadingOnboarding = true
    @State private var pendingAvatarData: Data?
    @State private var onboardingAnswers: [String: String] = [:]
    @State private var selectedFocus: Set<String> = []
    @State private var referralOtherText = ""

    init(profile: TrainerProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    photoSection
                    fieldSection
                    bioSection
                    specialtySection
                    onboardingSection
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 48)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.Color.accent, in: Capsule())
                    .disabled(isSaving || isLoadingOnboarding)
                }
            }
            .toast($toast)
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadImage(newValue) }
            }
            .task { await loadOnboarding() }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(width: 34, height: 34)
                        .background(Theme.Color.accent, in: Circle())
                        .overlay(Circle().stroke(Theme.Color.background, lineWidth: 3))
                }
            }
            .buttonStyle(.plain)

            Text("Tap to change photo")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var avatar: some View {
        Group {
            if let data = draft.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(draft.initials)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 108, height: 108)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2.5).padding(-5))
    }

    // MARK: Name + title

    private var fieldSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            LabeledField(label: "Display Name", text: $draft.name, placeholder: "Coach Sarah")
            LabeledField(label: "Job Title", text: $draft.title, placeholder: "Head Strength Coach")
        }
    }

    // MARK: Bio

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Bio")
            ZStack(alignment: .topLeading) {
                if draft.bio.isEmpty {
                    Text("Write a short introduction your clients will see…")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $draft.bio)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 128)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    // MARK: Specialties

    private var specialtySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Specialties")
            Text("Visible to clients")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
            FlowChips(items: Specialty.allCases) { specialty in
                let selected = draft.specialties.contains(specialty)
                SpecialtyChip(label: specialty.rawValue, selected: selected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if selected { draft.specialties.remove(specialty) }
                        else { draft.specialties.insert(specialty) }
                    }
                }
            }
        }
    }

    // MARK: Onboarding answers

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Coaching details")
                Text("Same answers from onboarding. Experience, location, and focus are visible to clients.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }

            if isLoadingOnboarding {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(TrainerOnboardingFields.editableKeys, id: \.self) { key in
                    onboardingField(for: key)
                }
            }
        }
    }

    @ViewBuilder
    private func onboardingField(for key: String) -> some View {
        let options = TrainerOnboardingFields.options(for: key)
        let clientVisible = TrainerOnboardingFields.clientVisibleKeys.contains(key)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel(TrainerOnboardingFields.title(for: key))
                if clientVisible {
                    Text("CLIENTS SEE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Color.accent.opacity(0.35), in: Capsule())
                } else {
                    Text("PRIVATE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Color.inkMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Color.surfaceMuted, in: Capsule())
                }
            }

            if TrainerOnboardingFields.allowsMultiple(key) {
                FlowChips(items: options.map { IdentifiedString($0) }) { item in
                    let selected = selectedFocus.contains(item.value)
                    SpecialtyChip(label: item.value, selected: selected) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if selected { selectedFocus.remove(item.value) }
                            else { selectedFocus.insert(item.value) }
                        }
                    }
                }
            } else {
                FlowChips(items: options.map { IdentifiedString($0) }) { item in
                    let selected = isOptionSelected(key: key, option: item.value)
                    SpecialtyChip(label: item.value, selected: selected) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectSingle(key: key, option: item.value)
                        }
                    }
                }
            }

            if TrainerOnboardingFields.allowsOtherText(key),
               onboardingAnswers[key] == "Other" || (!referralOtherText.isEmpty && !options.contains(onboardingAnswers[key] ?? "")) {
                TextField("Tell us more…", text: $referralOtherText)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            }
        }
    }

    private func isOptionSelected(key: String, option: String) -> Bool {
        let value = onboardingAnswers[key] ?? ""
        if option == "Other" {
            return value == "Other" || (!value.isEmpty && !TrainerOnboardingFields.options(for: key).contains(value))
        }
        return value == option
    }

    private func selectSingle(key: String, option: String) {
        onboardingAnswers[key] = option
        if key == TrainerOnboardingFields.referral, option != "Other" {
            referralOtherText = ""
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: Actions

    private func loadOnboarding() async {
        guard let token = AuthStore.accessToken else {
            isLoadingOnboarding = false
            return
        }
        do {
            let response = try await VerraAPI.fetchTrainerOnboarding(accessToken: token)
            await MainActor.run {
                onboardingAnswers = response.answers
                selectedFocus = Set(TrainerOnboardingFields.focusList(from: response.answers))
                let referral = response.answers[TrainerOnboardingFields.referral] ?? ""
                if !referral.isEmpty, !TrainerOnboardingFields.referralOptions.contains(referral) {
                    referralOtherText = referral
                    onboardingAnswers[TrainerOnboardingFields.referral] = "Other"
                }
                isLoadingOnboarding = false
            }
        } catch {
            await MainActor.run {
                isLoadingOnboarding = false
                toast = ToastData(message: "Couldn’t load coaching details", icon: "exclamationmark.triangle.fill")
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            store.profile = draft
            try await store.saveToServer(avatarUpload: pendingAvatarData)
            pendingAvatarData = nil

            if let token = AuthStore.accessToken {
                var answers = onboardingAnswers
                answers[TrainerOnboardingFields.focus] = TrainerOnboardingFields.encodeFocus(selectedFocus)
                if answers[TrainerOnboardingFields.referral] == "Other" {
                    let custom = referralOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !custom.isEmpty {
                        answers[TrainerOnboardingFields.referral] = custom
                    }
                }
                _ = try await VerraAPI.saveTrainerOnboarding(answers: answers, accessToken: token)
            }

            await MainActor.run {
                toast = ToastData(message: "Profile saved", icon: "checkmark.circle.fill")
                dismiss()
            }
        } catch {
            await MainActor.run {
                toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let resized = image.resized(maxDimension: 512)
        if let jpeg = resized.jpegData(compressionQuality: 0.82) {
            await MainActor.run {
                draft.avatarData = jpeg
                pendingAvatarData = jpeg
                toast = ToastData(message: "Photo updated", icon: "photo.fill")
            }
        }
    }
}

private struct IdentifiedString: Identifiable {
    let id: String
    let value: String
    init(_ value: String) {
        self.id = value
        self.value = value
    }
}

/// A boxed text field with a small caps label above it.
private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.inkFaint)
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }
}

/// A toggleable specialty pill.
private struct SpecialtyChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(selected ? Theme.Color.accentInk : Theme.Color.ink)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(selected ? Theme.Color.accent : Theme.Color.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
