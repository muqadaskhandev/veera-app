//
//  ContentView.swift
//  VerraOS
//

import SwiftUI

/// Root app shell: fixed header, swappable screen content, sticky bottom nav,
/// and an overlay profile drawer that slides in from the left.
struct ContentView: View {
    /// Called when the trainer logs out, returning to the welcome screen.
    var onLogOut: () -> Void = {}

    @State private var app = AppState()
    @State private var schedule = ScheduleStore()
    @State private var clients = ClientStore()
    @State private var profile = ProfileStore()
    @State private var messages = MessageStore()
    @State private var notifications = NotificationStore()
    @State private var trainer = TrainerStore()
    @State private var showingSettings = false
    @State private var showingNotifications = false
    @State private var showingEditProfile = false
    @State private var showingHelp = false
    @State private var showLogOutConfirm = false

    /// Public legal page opened from the drawer's Legal row.
    private let legalURL = URL(string: "https://verraos.app/legal")!
    @Environment(\.openURL) private var openURL

    private let drawerWidth: CGFloat = 308

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.Color.background.ignoresSafeArea()

            shell
                .scaleEffect(app.isDrawerOpen ? 0.92 : 1, anchor: .trailing)
                .offset(x: app.isDrawerOpen ? drawerWidth * 0.86 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: app.isDrawerOpen)
                .disabled(app.isDrawerOpen)

            if app.isDrawerOpen {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { app.closeDrawer() }
                    .transition(.opacity)
            }

            drawer
        }
        .background(Theme.Color.ink.ignoresSafeArea())
        .environment(app)
        .environment(schedule)
        .environment(clients)
        .environment(profile)
        .environment(messages)
        .environment(notifications)
        .environment(trainer)
        .sheet(isPresented: $showingSettings) {
            SettingsHubView(
                onLogOut: onLogOut,
                onDeleteAccount: onLogOut
            )
            .environment(schedule)
            .environment(trainer)
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationCenterView()
                .environment(notifications)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: trainer.profile)
                .environment(trainer)
        }
        .sheet(isPresented: $showingHelp) {
            HelpSupportView()
        }
        .confirmationDialog("Log out of VerraOS?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { onLogOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Shell

    private var shell: some View {
        VStack(spacing: 0) {
            TopHeader(
                title: app.selectedTab.title,
                hasUnread: notifications.hasUnread,
                showsControls: app.selectedTab == .schedule,
                onMenu: { app.openDrawer() },
                onBell: {
                    showingNotifications = true
                    notifications.markAllRead()
                }
            )

            ZStack {
                switch app.selectedTab {
                case .schedule: ScheduleView()
                case .clients: ClientsView()
                case .messages: MessagesView()
                case .financials: FinancialsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            if !app.isChatThreadOpen {
                BottomTabBar(selected: app.selectedTab) { tab in
                    app.select(tab)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.isChatThreadOpen)
        .background(Theme.Color.background)
        .clipShape(.rect(cornerRadius: app.isDrawerOpen ? 28 : 0))
    }

    // MARK: Drawer

    private var drawer: some View {
        ProfileDrawer(
            profile: trainer.profile,
            version: app.appVersion,
            onClose: { app.closeDrawer() },
            onEditProfile: { presentAfterDrawer { showingEditProfile = true } },
            onAppSettings: { presentAfterDrawer { showingSettings = true } },
            onLegal: {
                app.closeDrawer()
                openURL(legalURL)
            },
            onHelp: { presentAfterDrawer { showingHelp = true } },
            onLogOut: { presentAfterDrawer { showLogOutConfirm = true } }
        )
        .frame(width: drawerWidth)
        .offset(x: app.isDrawerOpen ? 0 : -drawerWidth)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: app.isDrawerOpen)
    }

    /// Closes the drawer, then presents a sheet once the slide-out finishes.
    private func presentAfterDrawer(_ present: @escaping () -> Void) {
        app.closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            present()
        }
    }
}

#Preview {
    ContentView()
}
