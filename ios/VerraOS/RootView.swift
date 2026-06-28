//
//  RootView.swift
//  VerraOS
//

import SwiftUI

/// Which experience the app is currently showing.
private enum AppRole {
    case none
    case trainer
    case client
}

/// Top-level flow: shows the welcome/splash screen first, then a one-time
/// onboarding flow per role, then routes into the Trainer or Client experience.
struct RootView: View {
    @State private var role: AppRole = .none
    @State private var onboardingRole: OnboardingRole?

    @AppStorage("verra.onboarded.trainer") private var onboardedTrainer = false
    @AppStorage("verra.onboarded.client") private var onboardedClient = false

    var body: some View {
        ZStack {
            switch role {
            case .none:
                WelcomeView(
                    onSelectTrainer: { begin(.trainer) },
                    onSelectClient: { begin(.client) }
                )
                .transition(.opacity)
            case .trainer:
                ContentView(onLogOut: signOut)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .client:
                ClientRootView(onLogOut: signOut)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let onboardingRole {
                OnboardingView(role: onboardingRole) { name, goal in
                    completeOnboarding(for: onboardingRole, name: name, goal: goal)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: role)
        .animation(.easeInOut(duration: 0.35), value: onboardingRole == nil)
    }

    /// Entry point from the welcome screen: run onboarding first if it hasn't
    /// been completed for this role, otherwise go straight to the home screen.
    private func begin(_ target: AppRole) {
        switch target {
        case .trainer where !onboardedTrainer:
            onboardingRole = .trainer
        case .client where !onboardedClient:
            onboardingRole = .client
        default:
            setRole(target)
        }
    }

    private func completeOnboarding(for onboarding: OnboardingRole, name: String, goal: String) {
        switch onboarding {
        case .trainer:
            onboardedTrainer = true
            if !name.isEmpty {
                let store = TrainerStore()
                store.profile.name = name
            }
            withAnimation { onboardingRole = nil }
            setRole(.trainer)
        case .client:
            onboardedClient = true
            if !name.isEmpty {
                UserDefaults.standard.set(name, forKey: "verra.client.displayName")
            }
            if !goal.isEmpty {
                UserDefaults.standard.set(goal, forKey: "verra.client.goal")
            }
            withAnimation { onboardingRole = nil }
            setRole(.client)
        }
    }

    private func setRole(_ newRole: AppRole) {
        role = newRole
    }

    private func signOut() {
        AuthStore.signOut()
        onboardedTrainer = false
        onboardedClient = false
        onboardingRole = nil
        withAnimation { setRole(.none) }
    }
}

#Preview {
    RootView()
}
