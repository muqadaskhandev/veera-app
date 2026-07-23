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
    @State private var healthData = HealthDataStore()
    @State private var showingSettings = false
    @State private var showingBilling = false
    @State private var showingNotifications = false
    @State private var showingEditProfile = false
    @State private var showingHelp = false
    @State private var showLogOutConfirm = false
    @State private var incomingChatAlert: IncomingChatAlert?
    /// One-time upsell after a trainer creates their account (not on every relaunch).
    @State private var showingPostSignupPaywall = false
    @Environment(SubscriptionStore.self) private var subscription
    @Environment(\.scenePhase) private var scenePhase

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
        .overlay(alignment: .top) {
            if let incomingChatAlert {
                InAppChatAlertBanner(
                    title: incomingChatAlert.title,
                    bodyText: incomingChatAlert.body,
                    symbol: incomingChatAlert.symbol,
                    tint: Color(hex: incomingChatAlert.tintHex),
                    onTap: {
                        let id = incomingChatAlert.conversationID
                        let opensSchedule = incomingChatAlert.opensSchedule
                        self.incomingChatAlert = nil
                        if let id {
                            app.openChat(conversationID: id)
                        } else if opensSchedule {
                            NotificationCenter.default.post(name: .openScheduleTab, object: nil)
                        } else {
                            showingNotifications = true
                        }
                    },
                    onDismiss: { self.incomingChatAlert = nil }
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: incomingChatAlert?.title)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showingPostSignupPaywall) {
            BillingView(isPaywall: true, onDismiss: {
                AuthStore.pendingPostSignupPaywall = false
                showingPostSignupPaywall = false
            })
            .environment(subscription)
        }
        .onChange(of: subscription.hasActiveSubscription) { _, isActive in
            if isActive {
                AuthStore.pendingPostSignupPaywall = false
                showingPostSignupPaywall = false
            }
        }
        .background(Theme.Color.ink.ignoresSafeArea())
        .environment(app)
        .environment(schedule)
        .environment(clients)
        .environment(profile)
        .environment(messages)
        .environment(notifications)
        .environment(trainer)
        .environment(healthData)
        .sheet(isPresented: $showingSettings) {
            SettingsHubView(
                onLogOut: onLogOut,
                onDeleteAccount: onLogOut
            )
            .environment(schedule)
            .environment(trainer)
            .environment(subscription)
        }
        .sheet(isPresented: $showingBilling) {
            NavigationStack {
                BillingView(isPaywall: false)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBilling = false }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Color.ink)
                        }
                    }
            }
            .environment(subscription)
        }
        .onChange(of: app.isDrawerOpen) { _, isOpen in
            if isOpen {
                Task { await subscription.refreshFromServer() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await subscription.refreshFromServer() }
            }
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
        .task {
            await subscription.bootstrap()
            await presentPostSignupPaywallIfNeeded()
            schedule.onCalendarPrefsPersisted = { json in
                Task { await trainer.saveCalendarPrefsJSON(json) }
            }
            profile.onVisibleModulesPersisted = { id, modules in
                clients.updateVisibleModules(modules, for: id)
                clients.syncRoster(to: schedule)
            }
            await trainer.refreshFromServer()
            schedule.loadCalendarPrefsFromServer(trainer.calendarPrefsJSON)
            await clients.refreshFromServer()
            clients.syncRoster(to: schedule)
            profile.applyVisibleModulesFromClients(clients.clients)
            await schedule.refreshFromServer()
            await schedule.syncGoogleConnectionStatus()
            await notifications.refreshFromServer()
            schedule.startCalendarMonitoring()
            if schedule.isSynced {
                await schedule.refreshCalendarData()
            }
            if let token = AuthStore.accessToken {
                await messages.start(accessToken: token)
                await ChatPushService.registerIfNeeded()
                if let summary = try? await VerraAPI.fetchFinancialSummary(filter: "all", accessToken: token) {
                    PlatformLoader.applyFinancialEvents(summary.events, clients: clients.clients, to: profile)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChatConversation)) { notification in
            guard let conversationID = notification.object as? UUID else { return }
            app.openChat(conversationID: conversationID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshNotifications)) { _ in
            Task { await notifications.refreshFromServer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingChatAlert)) { notification in
            guard let info = notification.userInfo,
                  let title = info["title"] as? String,
                  let body = info["body"] as? String else { return }
            let conversationID = (info["conversationID"] as? String).flatMap(UUID.init(uuidString:))
            let symbol = info["symbol"] as? String ?? "bubble.left.fill"
            let tintHex = (info["tintHex"] as? NSNumber)?.uintValue ?? 0x3D7FE8
            let opensSchedule = info["opensSchedule"] as? Bool ?? false
            notifications.prependMessageAlert(title: title, detail: body)
            let alert = IncomingChatAlert(
                title: title,
                body: body,
                conversationID: conversationID,
                opensSchedule: opensSchedule,
                symbol: symbol,
                tintHex: tintHex
            )
            incomingChatAlert = alert
            Task {
                try? await Task.sleep(for: .seconds(4))
                if incomingChatAlert == alert {
                    incomingChatAlert = nil
                }
            }
        }
        .onDisappear {
            messages.stop()
            schedule.stopCalendarMonitoring()
        }
    }

    // MARK: Shell

    private var shell: some View {
        VStack(spacing: 0) {
            TopHeader(
                title: app.selectedTab.title,
                hasUnread: notifications.hasUnread,
                showsControls: true,
                onMenu: { app.openDrawer() },
                onBell: {
                    showingNotifications = true
                }
            )

            Group {
                switch app.selectedTab {
                case .schedule: ScheduleView()
                case .clients: ClientsView()
                case .messages: MessagesView()
                case .financials: FinancialsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !app.isChatThreadOpen {
                    BottomTabBar(selected: app.selectedTab, messagesUnreadCount: messages.unreadCount) { tab in
                        app.select(tab)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
            onSubscription: { presentAfterDrawer { showingBilling = true } },
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

    /// After first trainer signup only: verify subscription, then show upsell once.
    @MainActor
    private func presentPostSignupPaywallIfNeeded() async {
        guard AuthStore.pendingPostSignupPaywall else { return }
        await subscription.refreshFromServer()
        if subscription.hasActiveSubscription || subscription.isAdmin {
            AuthStore.pendingPostSignupPaywall = false
            return
        }
        showingPostSignupPaywall = true
    }
}

#Preview {
    ContentView()
        .environment(SubscriptionStore())
}
