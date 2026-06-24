//
//  ClientTrainerProfileView.swift
//  VerraOS
//
//  Read-only view of the client's coach: avatar, name, title, bio, and
//  specialties. Presented as a sheet from the dashboard's "Your Trainer" card
//  and the account drawer.
//

import SwiftUI

struct ClientTrainerProfileView: View {
    let profile: TrainerProfile

    @Environment(\.dismiss) private var dismiss

    private var orderedSpecialties: [Specialty] {
        Specialty.allCases.filter { profile.specialties.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.lg) {
                    hero
                    if !profile.bio.isEmpty { bioCard }
                    if !orderedSpecialties.isEmpty { specialtyCard }
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
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            avatar
            VStack(spacing: 5) {
                Text(profile.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                Text(profile.title)
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

    private var bioCard: some View {
        SectionCard(title: "About", icon: "person.text.rectangle") {
            Text(profile.bio)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var specialtyCard: some View {
        SectionCard(title: "Specialties", icon: "checkmark.seal.fill") {
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
