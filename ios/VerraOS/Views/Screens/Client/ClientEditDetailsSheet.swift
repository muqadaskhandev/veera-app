//
//  ClientEditDetailsSheet.swift
//  VerraOS
//
//  A lightweight account-details sheet for the client. Editable display name now;
//  email / password setup arrives later with onboarding.
//

import SwiftUI

struct ClientEditDetailsSheet: View {
    let name: String
    let email: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var toast: ToastData?

    init(name: String, email: String) {
        self.name = name
        self.email = email
        _draftName = State(initialValue: name)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    field(label: "Display Name", text: $draftName, placeholder: "Your name")
                    accountCard
                    onboardingNote
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
                    Button("Save") { dismiss() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.Color.accent, in: Capsule())
                }
            }
            .toast($toast)
        }
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
                    Text(email.isEmpty ? "Not set" : email)
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

    private var onboardingNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.accentInk)
            Text("Email & password setup arrives with onboarding soon.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
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
