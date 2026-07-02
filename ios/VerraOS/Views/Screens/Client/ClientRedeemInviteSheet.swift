import SwiftUI

/// Lets a signed-in client connect to their coach with an invite code after onboarding.
struct ClientRedeemInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let account: ClientAccountStore
    var onLinked: () -> Void = {}

    @State private var inviteCode = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var validatedTrainerName: String?
    @State private var invitedEmail: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect to your coach")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.ink)
                        Text("Enter the invite code from your trainer. We'll link your account and show their profile on your dashboard.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    InviteCodeField(code: $inviteCode, style: .settings)

                    if let validatedTrainerName {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: 0x57C77B))
                            Text("Valid code for \(validatedTrainerName)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                        }
                    }

                    if let invitedEmail {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Color.accentInk)
                                .padding(.top, 2)
                            Text("This invite was sent to \(invitedEmail). Your account must use that email address.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Color.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                        )
                    }

                    Button(action: { Task { await redeem() } }) {
                        Text(isSaving ? "Connecting…" : "Connect Trainer")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(canSubmit ? Theme.Color.accentInk : Theme.Color.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background((canSubmit ? Theme.Color.accent : Theme.Color.accent.opacity(0.35)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isSaving)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.background)
            .navigationTitle("Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
            .alert("Could not connect", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: inviteCode) { _, _ in
                validatedTrainerName = nil
                invitedEmail = nil
            }
        }
    }

    private var canSubmit: Bool {
        !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func redeem() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if validatedTrainerName == nil {
                let validation = try await VerraAPI.validateInvite(code: code)
                guard validation.valid else {
                    errorMessage = validation.message ?? "Invalid or expired invite code"
                    return
                }
                validatedTrainerName = validation.trainerName
                invitedEmail = validation.invitedEmail

                if let invitedEmail = validation.invitedEmail {
                    let accountEmail = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !accountEmail.isEmpty, accountEmail == invitedEmail.lowercased() else {
                        errorMessage = "This isn't the email for this code. Please use \(invitedEmail) — that's the address your trainer invited."
                        return
                    }
                }
            }

            _ = try await account.redeemInvite(code: code)
            onLinked()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
