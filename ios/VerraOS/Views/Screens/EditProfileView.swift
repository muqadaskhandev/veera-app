//
//  EditProfileView.swift
//  VerraOS
//

import SwiftUI
import PhotosUI

/// Edit the trainer's client-facing profile: photo, name, title, bio, and
/// specialty tags. Changes are committed to the TrainerStore on Save.
struct EditProfileView: View {
    @Environment(TrainerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TrainerProfile
    @State private var pickerItem: PhotosPickerItem?
    @State private var toast: ToastData?
    @State private var isSaving = false
    @State private var pendingAvatarData: Data?

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
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 48)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(isSaving)
                }
            }
            .toast($toast)
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadImage(newValue) }
            }
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }

    // MARK: Actions

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            store.profile = draft
            try await store.saveToServer(avatarUpload: pendingAvatarData)
            pendingAvatarData = nil
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
        // Downscale to keep persisted payload small.
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
    /// Returns a copy scaled so its longest side is at most `maxDimension`.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
