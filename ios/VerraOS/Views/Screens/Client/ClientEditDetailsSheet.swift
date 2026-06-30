//
//  ClientEditDetailsSheet.swift
//  VerraOS
//

import PhotosUI
import SwiftUI

struct ClientEditDetailsSheet: View {
    @Bindable var account: ClientAccountStore

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var draftAvatarData: Data?
    @State private var pendingAvatarData: Data?
    @State private var toast: ToastData?

    init(account: ClientAccountStore) {
        self.account = account
        _draftName = State(initialValue: account.name)
        _draftAvatarData = State(initialValue: account.avatarData)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    photoSection
                    field(label: "Display Name", text: $draftName, placeholder: "Your name")
                    accountCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 44)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(account.isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.Color.accent, in: Capsule())
                    .disabled(account.isSaving)
                }
            }
            .toast($toast)
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadImage(newValue) }
            }
        }
    }

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
            if let data = draftAvatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(account.initials)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 108, height: 108)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2.5).padding(-5))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Account")
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text(account.email.isEmpty ? "Not set" : account.email)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    @MainActor
    private func save() async {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast = ToastData(message: "Name is required", icon: "exclamationmark.triangle.fill")
            return
        }
        do {
            try await account.save(displayName: trimmed, avatarUpload: pendingAvatarData)
            pendingAvatarData = nil
            draftAvatarData = account.avatarData
            toast = ToastData(message: "Profile saved", icon: "checkmark.circle.fill")
            dismiss()
        } catch {
            toast = ToastData(message: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    private func loadImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let resized = image.resized(maxDimension: 512)
        if let jpeg = resized.jpegData(compressionQuality: 0.82) {
            await MainActor.run {
                draftAvatarData = jpeg
                pendingAvatarData = jpeg
                toast = ToastData(message: "Photo updated", icon: "photo.fill")
            }
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
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
