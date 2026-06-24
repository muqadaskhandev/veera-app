//
//  SecurityView.swift
//  VerraOS
//

import SwiftUI

/// Change password, toggle biometric login, and log out. Pushed from Settings.
struct SecurityView: View {
    @Environment(TrainerStore.self) private var store

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var toast: ToastData?
    @State private var showLogOutConfirm = false

    private var canChangePassword: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        @Bindable var store = store
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                passwordSection
                biometricSection(enabled: $store.profile.biometricLoginEnabled)
                logOutSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 44)
        }
        .background(Theme.Color.background)
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.Color.accent)
        .toast($toast)
        .confirmationDialog("Log out of VerraOS?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                toast = ToastData(message: "Signed out (simulated)", icon: "rectangle.portrait.and.arrow.right")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Password

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Change Password")
            VStack(spacing: 0) {
                secureRow(label: "Current", text: $currentPassword)
                hairline
                secureRow(label: "New", text: $newPassword)
                hairline
                secureRow(label: "Confirm", text: $confirmPassword)
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))

            if !newPassword.isEmpty && newPassword.count < 6 {
                helper("New password must be at least 6 characters.", tint: Theme.Color.danger)
            } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                helper("Passwords don't match.", tint: Theme.Color.danger)
            }

            Button {
                currentPassword = ""; newPassword = ""; confirmPassword = ""
                toast = ToastData(message: "Password updated", icon: "lock.fill")
            } label: {
                Text("Update Password")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canChangePassword ? Theme.Color.accentInk : Theme.Color.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canChangePassword ? Theme.Color.accent : Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!canChangePassword)
        }
    }

    private func secureRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .frame(width: 80, alignment: .leading)
            SecureField("••••••••", text: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .textContentType(.password)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 15)
    }

    // MARK: Biometrics

    private func biometricSection(enabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Biometric Login")
            Toggle(isOn: enabled) {
                HStack(spacing: 12) {
                    Image(systemName: "faceid")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID / Touch ID")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                        Text("Unlock with your face or fingerprint.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                }
            }
            .tint(Theme.Color.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 13)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    // MARK: Log out

    private var logOutSection: some View {
        Button {
            showLogOutConfirm = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                Text("Log Out")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(Theme.Color.danger)
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func helper(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
    }

    private var hairline: some View {
        Rectangle().fill(Theme.Color.hairline).frame(height: 1).padding(.horizontal, Theme.Spacing.md)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }
}
