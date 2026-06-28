//
//  ClientRootView.swift
//  VerraOS
//
//  The client experience shell: four tabs (Dashboard, Schedule, Wearables,
//  Messages) on the shared VerraOS theme, running on isolated local demo data
//  for a single client, plus a slide-in account drawer. Everything is read-only
//  except logging weight, editing personal goals, messaging, managing their own
//  wearables, and skipping / cancelling their own sessions.
//

import SwiftUI

/// The primary destinations for the client experience.
enum ClientTab: Int, CaseIterable, Identifiable {
    case dashboard
    case schedule
    case wearables
    case messages

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .schedule: return "Schedule"
        case .wearables: return "Wearables"
        case .messages: return "Messages"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .schedule: return "calendar"
        case .wearables: return "applewatch"
        case .messages: return "bubble.left.and.bubble.right"
        }
    }

    var symbolFilled: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .schedule: return "calendar"
        case .wearables: return "applewatch"
        case .messages: return "bubble.left.and.bubble.right.fill"
        }
    }

    /// Tabs shown in the bottom navigation bar. Wearables is intentionally
    /// excluded — it stays reachable from the sidebar menu.
    static var barTabs: [ClientTab] { [.dashboard, .schedule, .messages] }
}

struct ClientRootView: View {
    /// Called when the client logs out, returning to the welcome screen.
    var onLogOut: () -> Void = {}

    @State private var app = AppState()
    @State private var schedule: ScheduleStore
    @State private var clients: ClientStore
    @State private var profile: ProfileStore
    @State private var messages: MessageStore
    @State private var trainer = TrainerStore()
    @State private var wearables = WearableConnectionStore()

    @State private var tab: ClientTab = .dashboard
    @State private var isDrawerOpen = false
    @State private var showingTrainerProfile = false
    @State private var showingEditDetails = false
    @State private var showingHelp = false
    @State private var showingSettings = false
    @State private var showLogOutConfirm = false

    private let client: Client
    private let conversationID: UUID
    private let coachName = "Your Trainer"
    private let coachTitle = ""
    private let drawerWidth: CGFloat = 308
    private let appVersion = "v1.0.2"
    private let legalURL = URL(string: "https://verraos.app/legal")!
    @Environment(\.openURL) private var openURL

    init(onLogOut: @escaping () -> Void = {}) {
        self.onLogOut = onLogOut

        // Build a clean client identity from the onboarding name (if provided).
        let savedName = UserDefaults.standard.string(forKey: "verra.client.displayName") ?? ""
        let displayName = savedName.isEmpty ? "Your Profile" : savedName
        var fresh = Client(
            name: displayName,
            initials: Self.initials(from: displayName),
            sessionsRemaining: 0,
            status: .active
        )
        if let savedGoal = UserDefaults.standard.string(forKey: "verra.client.goal"),
           !savedGoal.isEmpty {
            fresh.primaryGoal = savedGoal
        }
        self.client = fresh

        // Seed the roster with this single client so their own profile resolves.
        _clients = State(initialValue: ClientStore(clients: [fresh]))

        // Start with an empty schedule — the client's sessions are populated for real.
        let sched = ScheduleStore(sessions: [], clients: [fresh])
        _schedule = State(initialValue: sched)

        // A single empty conversation thread with their coach.
        let store = MessageStore(conversations: [MessageStore.clientThread(for: fresh)])
        _messages = State(initialValue: store)
        self.conversationID = store.conversations.first?.id ?? UUID()

        // The client's plan areas are visible but start empty until the trainer fills them.
        let p = ProfileStore()
        p.setVisibleModules([.workout, .wearables, .weight, .nutrition, .photos, .financials], for: fresh.id)
        _profile = State(initialValue: p)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.Color.background.ignoresSafeArea()

            shell
                .scaleEffect(isDrawerOpen ? 0.92 : 1, anchor: .trailing)
                .offset(x: isDrawerOpen ? drawerWidth * 0.86 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isDrawerOpen)
                .disabled(isDrawerOpen)

            if isDrawerOpen {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .transition(.opacity)
            }

            drawer
        }
        .background(Theme.Color.ink.ignoresSafeArea())
        .environment(\.isReadOnly, true)
        .environment(app)
        .environment(schedule)
        .environment(clients)
        .environment(profile)
        .environment(messages)
        .environment(trainer)
        .environment(wearables)
        .sheet(isPresented: $showingTrainerProfile) {
            ClientTrainerProfileView(profile: trainer.profile)
        }
        .sheet(isPresented: $showingEditDetails) {
            ClientEditDetailsSheet(name: client.name, email: client.email)
        }
        .sheet(isPresented: $showingHelp) {
            HelpSupportView()
        }
        .sheet(isPresented: $showingSettings) {
            ClientSettingsView(
                unit: trainer.units,
                onSelectUnit: { trainer.units = $0 },
                onLogOut: onLogOut,
                onDeleteAccount: onLogOut
            )
        }
        .confirmationDialog("Log out of VerraOS?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { onLogOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Shell

    private var shell: some View {
        VStack(spacing: 0) {
            if tab != .messages {
                ClientTopBar(
                    title: tab.title,
                    onMenu: openDrawer
                )
            }

            ZStack {
                switch tab {
                case .dashboard:
                    ClientDashboardView(clientID: client.id, onViewTrainer: { showingTrainerProfile = true })
                case .schedule:
                    ClientScheduleView(clientName: client.name)
                case .wearables:
                    ClientWearablesView(clientID: client.id)
                case .messages:
                    ClientMessagesView(
                        conversationID: conversationID,
                        coachName: coachName,
                        coachSubtitle: coachTitle,
                        onExit: { withAnimation(.easeInOut(duration: 0.2)) { tab = .dashboard } }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            if tab != .messages {
                ClientTabBar(selected: tab) { newTab in
                    guard newTab != tab else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { tab = newTab }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Color.background)
        .clipShape(.rect(cornerRadius: isDrawerOpen ? 28 : 0))
    }

    // MARK: Drawer

    private var drawer: some View {
        ClientDrawer(
            name: client.name,
            initials: client.initials,
            email: client.email,
            version: appVersion,
            onClose: closeDrawer,
            onEditDetails: { presentAfterDrawer { showingEditDetails = true } },
            onManageWearables: {
                closeDrawer()
                withAnimation(.easeInOut(duration: 0.2)) { tab = .wearables }
            },
            onViewTrainer: { presentAfterDrawer { showingTrainerProfile = true } },
            onAppSettings: { presentAfterDrawer { showingSettings = true } },
            onHelp: { presentAfterDrawer { showingHelp = true } },
            onLegal: {
                closeDrawer()
                openURL(legalURL)
            },
            onLogOut: { presentAfterDrawer { showLogOutConfirm = true } }
        )
        .frame(width: drawerWidth)
        .offset(x: isDrawerOpen ? 0 : -drawerWidth)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isDrawerOpen)
    }

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "?" : result
    }

    private func openDrawer() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isDrawerOpen = true }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { isDrawerOpen = false }
    }

    /// Closes the drawer, then presents a sheet once the slide-out finishes.
    private func presentAfterDrawer(_ present: @escaping () -> Void) {
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { present() }
    }
}

// MARK: - Client top bar

private struct ClientTopBar: View {
    let title: String
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: onMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menu")

            Spacer(minLength: 0)

            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: title)

            Spacer(minLength: 0)

            // Balances the leading menu button so the title stays centered.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Theme.Color.background)
    }
}

// MARK: - Client tab bar

private struct ClientTabBar: View {
    let selected: ClientTab
    let onSelect: (ClientTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClientTab.barTabs) { tab in
                ClientTabItem(tab: tab, isActive: tab == selected) { onSelect(tab) }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            Theme.Color.surface
                .clipShape(.rect(topLeadingRadius: 26, topTrailingRadius: 26))
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.hairline).frame(height: 1)
        }
        .shadow(color: Color(hex: 0x1A1A17).opacity(0.06), radius: 16, x: 0, y: -6)
    }
}

private struct ClientTabItem: View {
    let tab: ClientTab
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Theme.Color.accent)
                            .frame(width: 52, height: 32)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: isActive ? tab.symbolFilled : tab.symbol)
                        .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkFaint)
                }
                .frame(height: 32)

                Text(tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.Color.ink : Theme.Color.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}
