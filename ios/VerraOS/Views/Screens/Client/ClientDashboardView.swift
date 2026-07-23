//
//  ClientDashboardView.swift
//  VerraOS
//
//  The client's home: a read-only mirror of the trainer's Client Hub for one
//  client, plus the single personal action of logging their own weight. Module
//  tiles push into the shared module screens in read-only mode.
//

import SwiftUI

struct ClientDashboardView: View {
    let clientID: UUID
    /// Opens the read-only trainer profile from the "Your Trainer" card.
    var onViewTrainer: () -> Void = {}
    var onConnectTrainer: () -> Void = {}
    var onEditProfile: () -> Void = {}

    @Environment(ClientStore.self) private var clientStore
    @Environment(ProfileStore.self) private var profile
    @Environment(TrainerStore.self) private var trainer
    @Environment(WearableConnectionStore.self) private var wearables
    @Environment(ClientAccountStore.self) private var account

    private var unit: WeightUnit { trainer.units }

    @State private var path = NavigationPath()
    @State private var isRefreshing = false

    private var client: Client? {
        clientStore.clients.first { $0.id == clientID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let client {
                    content(for: client)
                } else {
                    VStack { Spacer(); Text("Profile unavailable").foregroundStyle(Theme.Color.inkMuted); Spacer() }
                }
            }
            .background(Theme.Color.background)
            .navigationDestination(for: ModuleRoute.self) { route in
                ProfileModuleRouter(route: route, wearablesConnected: wearables.hasAnyConnection) { if !path.isEmpty { path.removeLast() } }
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private func content(for client: Client) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.Spacing.md) {
                identityHeader(client)
                biometrics(client)
                sessionBank(client)
                if account.hasLinkedTrainer {
                    trainerCard
                } else {
                    connectTrainerBanner
                }
                if !client.note.isEmpty { coachNote(client) }
                moduleGrid(client)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        .tabScrollContent()
        .opacity(isRefreshing && !account.isLoaded ? 0.6 : 1)
        .overlay {
            if isRefreshing && !account.isLoaded {
                ProgressView()
            }
        }
        .task { await refreshDashboard() }
        .refreshable { await refreshDashboard() }
    }

    @MainActor
    private func refreshDashboard() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await account.refreshFromServer()
        if let loaded = account.client {
            clientStore.clients = [loaded]
            trainer.profile.weightUnit = WeightUnit(rawValue: account.weightUnit) ?? .kg
            profile.applyWeightTargets(from: loaded)
            profile.applyVisibleModules(loaded.visibleModules, for: loaded.id)
            await profile.refreshAllVisibleModules(for: loaded)
        }
    }

    // MARK: Identity

    private func identityHeader(_ client: Client) -> some View {
        let displayName = account.name.isEmpty ? client.name : account.name
        let initials = account.initials.isEmpty ? client.initials : account.initials

        return VStack(spacing: 12) {
            Group {
                if let data = account.avatarData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Theme.Color.ink)
                        .overlay(
                            Text(initials)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.accent)
                        )
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(client.effectiveStatus.tint)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 3))
            }
            .cardShadow(0.8)

            Text(displayName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Biometrics (read-only)

    private func biometrics(_ client: Client) -> some View {
        let start = client.weightKg.map { String(format: "%.0f %@", unit.fromKg(Double($0)), unit.short) } ?? "—"
        let goalKg = client.goalWeightKg.map(Double.init)
            ?? profile.weightTargets(for: client).goal
        let goal = goalKg.map { String(format: "%.0f %@", unit.fromKg($0), unit.short) } ?? "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DETAILS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.inkFaint)
                Spacer()
                Button(action: onEditProfile) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                        Text("Edit profile")
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

    // MARK: Session bank (read-only)

    private func sessionBank(_ client: Client) -> some View {
        HStack(alignment: .center) {
            Text("SESSION BANK")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.Color.accent.opacity(0.8))
            Spacer()
            Text("\(client.sessionsRemaining)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.accent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: client.sessionsRemaining)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Color.ink, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardShadow()
    }

    // MARK: Your trainer

    private var connectTrainerBanner: some View {
        Button(action: onConnectTrainer) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.accent.opacity(0.18))
                        .frame(width: 50, height: 50)
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Color.accentInk)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONNECT YOUR COACH")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text("Got an invite code?")
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Link your trainer to see their profile and sessions.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1))
            .cardShadow(0.5)
        }
        .buttonStyle(.plain)
    }

    private var trainerCard: some View {
        let coach = account.coachProfile
        return Button(action: onViewTrainer) {
            HStack(spacing: 14) {
                coachAvatar(coach)
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR TRAINER")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text(coach.name.isEmpty ? "Your Trainer" : coach.name)
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(coach.title.isEmpty ? "Strength Coach" : coach.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.inkFaint)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
            .cardShadow(0.5)
        }
        .buttonStyle(.plain)
    }

    private func coachAvatar(_ coach: TrainerProfile) -> some View {
        Group {
            if let data = coach.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(coach.initials)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.accent, lineWidth: 1.5).padding(-2))
    }

    // MARK: Coach note

    private func coachNote(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
                Text("FROM YOUR COACH")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Text(client.note)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.5)
    }

    // MARK: Module grid

    private func moduleGrid(_ client: Client) -> some View {
        let modules = profile.orderedVisibleModules(for: client.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR PLAN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Color.inkFaint)
                Spacer()
            }
            if modules.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                    Text("Nothing shared yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(modules) { module in
                        NavigationLink(value: ModuleRoute(clientID: client.id, module: module)) {
                            ClientModuleTile(module: module)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ClientModuleTile: View {
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
