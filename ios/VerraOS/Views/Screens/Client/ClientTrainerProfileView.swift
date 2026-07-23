//
//  ClientTrainerProfileView.swift
//  VerraOS
//
//  Read-only client view of their coach. Shows public profile fields only —
//  photo, name, title, bio, specialties, plus experience / location / focus.
//  Private onboarding answers (gender, age, client count, referral) are hidden.
//

import SwiftUI

struct ClientTrainerProfileView: View {
    @Bindable var account: ClientAccountStore

    @Environment(\.dismiss) private var dismiss

    private var profile: TrainerProfile { account.coachProfile }

    private var orderedSpecialties: [Specialty] {
        Specialty.allCases.filter { profile.specialties.contains($0) }
    }

    private var hasCoachingDetails: Bool {
        !(profile.experience?.isEmpty ?? true)
            || !(profile.trainingLocation?.isEmpty ?? true)
            || !profile.coachingFocus.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.lg) {
                    hero
                    aboutCard
                    if hasCoachingDetails {
                        coachingCard
                    }
                    specialtyCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 44)
            }
            .background(Theme.Color.background)
            .navigationTitle("Your Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
            .task {
                await account.refreshFromServer()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            avatar
            VStack(spacing: 5) {
                Text(profile.name.isEmpty ? "Your Trainer" : profile.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                Text(profile.title.isEmpty ? "Strength Coach" : profile.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.Color.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var avatar: some View {
        Group {
            if let data = profile.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(profile.initials)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 2.5).padding(-5))
        .cardShadow(0.8)
    }

    private var aboutCard: some View {
        SectionCard(title: "About", icon: "person.text.rectangle") {
            Text(profile.bio.isEmpty ? "Your coach hasn't added a bio yet." : profile.bio)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(profile.bio.isEmpty ? Theme.Color.inkMuted : Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var coachingCard: some View {
        SectionCard(title: "Coaching", icon: "figure.strengthtraining.traditional") {
            VStack(alignment: .leading, spacing: 14) {
                if let experience = profile.experience, !experience.isEmpty {
                    coachingRow(label: "Experience", value: experience)
                }
                if let location = profile.trainingLocation, !location.isEmpty {
                    coachingRow(label: "Trains at", value: location)
                }
                if !profile.coachingFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOCUS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Theme.Color.inkFaint)
                        FlowChips(items: profile.coachingFocus.map { IdentifiedFocus($0) }) { item in
                            Text(item.value)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Theme.Color.surfaceMuted, in: Capsule())
                                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func coachingRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.inkFaint)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
        }
    }

    private var specialtyCard: some View {
        SectionCard(title: "Specialties", icon: "checkmark.seal.fill") {
            if orderedSpecialties.isEmpty {
                Text("General strength and coaching")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowChips(items: orderedSpecialties) { specialty in
                    Text(specialty.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.Color.surfaceMuted, in: Capsule())
                        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                }
            }
        }
    }
}

private struct IdentifiedFocus: Identifiable {
    let id: String
    let value: String
    init(_ value: String) {
        self.id = value
        self.value = value
    }
}
