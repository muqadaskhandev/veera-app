//
//  ClientRootView.swift
//  VerraOS
//
//  The client experience shell: dashboard, schedule, wearables, and messages
//  on the shared VerraOS theme, backed by the authenticated client profile.
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

    /// Tabs shown in the bottom navigation bar. Wearables stays in the drawer.
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
    @State private var notifications = NotificationStore()
    @State private var trainer = TrainerStore()
    @State private var account = ClientAccountStore()
    @State private var wearables = WearableConnectionStore()
    @State private var healthData = HealthDataStore()

    @State private var tab: ClientTab = .dashboard
    @State private var isDrawerOpen = false
    @State private var showingTrainerProfile = false
    @State private var showingEditDetails = false
    @State private var showingHelp = false
    @State private var showingSettings = false
    @State private var showingRedeemInvite = false
    @State private var pendingInviteCode: String?
    @State private var showingNotifications = false
    @State private var showLogOutConfirm = false
    @State private var incomingChatAlert: IncomingChatAlert?

    private var client: Client {
        account.client ?? Self.placeholderClient
    }

    private var coachName: String {
        let name = account.coachProfile.name
        return name.isEmpty ? "Your Trainer" : name
    }

    private var coachTitle: String {
        account.coachProfile.title
    }

    private static let placeholderClient = Client(
        name: "Loading…",
        initials: "…",
        sessionsRemaining: 0,
        status: .active
    )

    @State private var conversationID: UUID = UUID()
    private let drawerWidth: CGFloat = 308
    private let appVersion = "v1.0.2"
    private let legalURL = URL(string: "https://verraos.app/legal")!
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(onLogOut: @escaping () -> Void = {}) {
        self.onLogOut = onLogOut

        let placeholder = Self.placeholderClient
        _clients = State(initialValue: ClientStore(clients: [placeholder]))
        let sched = ScheduleStore(sessions: [], clients: [placeholder])
        _schedule = State(initialValue: sched)

        // Don't seed a fake local thread — that blocked ensureClientThread from
        // creating/adopting the real coach conversation on the server.
        _messages = State(initialValue: MessageStore())

        let p = ProfileStore()
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
        .overlay(alignment: .top) {
            if let incomingChatAlert, tab != .messages || incomingChatAlert.conversationID == nil {
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
                            conversationID = id
                            withAnimation(.easeInOut(duration: 0.2)) { tab = .messages }
                        } else if opensSchedule {
                            withAnimation(.easeInOut(duration: 0.2)) { tab = .schedule }
                            Task { await schedule.refreshFromServer() }
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
        .background(Theme.Color.ink.ignoresSafeArea())
        .environment(\.isReadOnly, true)
        .environment(app)
        .environment(schedule)
        .environment(clients)
        .environment(profile)
        .environment(messages)
        .environment(notifications)
        .environment(trainer)
        .environment(wearables)
        .environment(healthData)
        .environment(account)
        .sheet(isPresented: $showingTrainerProfile) {
            ClientTrainerProfileView(account: account)
        }
        .sheet(isPresented: $showingEditDetails) {
            ClientEditDetailsSheet(account: account)
        }
        .onChange(of: showingEditDetails) { _, isShowing in
            if !isShowing {
                Task { await refreshAll() }
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpSupportView()
        }
        .sheet(isPresented: $showingSettings) {
            ClientSettingsView(
                unit: account.units,
                onSelectUnit: { newUnit in
                    Task { await account.setWeightUnit(newUnit) }
                    // Shared module screens still read trainer.units for display —
                    // apply locally only so we never PATCH the trainer's preference.
                    trainer.applyDisplayUnit(newUnit)
                },
                onLogOut: onLogOut,
                onDeleteAccount: onLogOut,
                onTrainerLinked: { Task { await refreshAll() } }
            )
            .environment(account)
        }
        .sheet(isPresented: $showingRedeemInvite) {
            ClientRedeemInviteSheet(account: account, prefillCode: pendingInviteCode) {
                Task { await refreshAll() }
            }
        }
        .onChange(of: showingRedeemInvite) { _, isShowing in
            if !isShowing { pendingInviteCode = nil }
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationCenterView()
                .environment(notifications)
        }
        .confirmationDialog("Log out of VerraOS?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { onLogOut() }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await refreshAll()
            checkPendingInviteLink()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshChatState() }
        }
        .onDisappear {
            messages.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkInviteCodeReceived)) { notification in
            guard let code = notification.object as? String else { return }
            pendingInviteCode = code
            showingRedeemInvite = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthKitDataUpdated)) { _ in
            Task {
                guard wearables.isConnected(.appleHealth) else { return }
                await wearables.syncNow(healthData: healthData)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChatConversation)) { notification in
            guard let id = notification.object as? UUID else { return }
            conversationID = messages.canonicalConversationID(id)
            withAnimation(.easeInOut(duration: 0.2)) { tab = .messages }
            Task { await refreshChatState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openScheduleTab)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { tab = .schedule }
            Task { await schedule.refreshFromServer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshNotifications)) { _ in
            Task { await notifications.refreshFromServer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingChatAlert)) { notification in
            guard let info = notification.userInfo,
                  let title = info["title"] as? String,
                  let pushBody = info["body"] as? String else { return }
            let conversationID = (info["conversationID"] as? String).flatMap(UUID.init(uuidString:))
            // Only hide the banner when already viewing that exact thread.
            if let conversationID, tab == .messages, conversationID == self.conversationID { return }
            let body: String = {
                guard conversationID != nil else { return pushBody }
                switch title {
                case "Voice message": return "You have a new voice message from \(coachName)"
                case "Image": return "You have a new image from \(coachName)"
                case "Video": return "You have a new video from \(coachName)"
                default: return "You have a new message from \(coachName)"
                }
            }()
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
    }

    /// Applies an invite code captured from a universal/deep link before this
    /// view existed (e.g. tapped before sign-in or onboarding finished).
    @MainActor
    private func checkPendingInviteLink() {
        guard account.coachProfile.name.isEmpty, let code = DeepLinkRouter.shared.consumePendingCode() else { return }
        pendingInviteCode = code
        showingRedeemInvite = true
    }

    @MainActor
    private func syncFromAccount() {
        guard let loaded = account.client else { return }
        clients.clients = [loaded]
        schedule.clients = [loaded]
        // Load coach card data without PATCHing preferences through TrainerStore.
        trainer.replaceProfileWithoutSaving(account.coachProfile)
        trainer.applyDisplayUnit(account.units)
        profile.applyWeightTargets(from: loaded)
        profile.applyVisibleModules(loaded.visibleModules, for: loaded.id)
    }

    @MainActor
    private func refreshAll() async {
        await account.refreshFromServer()
        syncFromAccount()
        await schedule.refreshFromServer()
        await wearables.refreshFromServer()
        if let client = account.client {
            await profile.refreshAllVisibleModules(for: client)
        }
        if let clientID = account.client?.id {
            await healthData.refreshForClient(clientID: clientID, trainerView: false)
        }
        await HealthBackgroundSync.syncOnLaunchIfNeeded(wearables: wearables, healthData: healthData)
        if let token = AuthStore.accessToken {
            await messages.start(accessToken: token)
            await notifications.refreshFromServer()
            await ChatPushService.registerIfNeeded()
            if let id = await messages.ensureClientThread() {
                conversationID = id
            }
        }
    }

    /// Soft refresh for unread badges + notification center (launch / foreground / push tap).
    @MainActor
    private func refreshChatState() async {
        guard AuthStore.accessToken != nil else { return }
        await messages.refreshFromServer()
        await notifications.refreshFromServer()
        if let id = await messages.ensureClientThread() {
            conversationID = id
        }
    }

    // MARK: Shell

    private var shell: some View {
        VStack(spacing: 0) {
            if tab != .messages {
                ClientTopBar(
                    title: tab.title,
                    hasUnread: notifications.hasUnread,
                    onMenu: openDrawer,
                    onBell: { showingNotifications = true }
                )
            }

            Group {
                switch tab {
                case .dashboard:
                    ClientDashboardView(
                        clientID: client.id,
                        onViewTrainer: { showingTrainerProfile = true },
                        onConnectTrainer: { showingRedeemInvite = true },
                        onEditProfile: { showingEditDetails = true }
                    )
                case .schedule:
                    ClientScheduleView(clientID: client.id, clientName: client.name)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if tab != .messages {
                    ClientTabBar(
                        selected: tab,
                        messagesUnreadCount: messages.unreadCount
                    ) { newTab in
                        guard newTab != tab else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { tab = newTab }
                        if newTab == .messages {
                            Task {
                                if let id = await messages.ensureClientThread() {
                                    conversationID = id
                                }
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Theme.Color.background)
        .clipShape(.rect(cornerRadius: isDrawerOpen ? 28 : 0))
    }

    // MARK: Drawer

    private var drawer: some View {
        ClientDrawer(
            name: account.name.isEmpty ? client.name : account.name,
            initials: account.initials,
            email: account.email.isEmpty ? client.email : account.email,
            avatarData: account.avatarData,
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
    var hasUnread: Bool = false
    let onMenu: () -> Void
    var onBell: (() -> Void)?

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

            if let onBell {
                Button(action: onBell) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Color.ink)
                            .frame(width: 44, height: 44)
                            .background(Theme.Color.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                        if hasUnread {
                            Circle()
                                .fill(Theme.Color.danger)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Theme.Color.background, lineWidth: 2))
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Theme.Color.background)
    }
}

// MARK: - Client tab bar

private struct ClientTabBar: View {
    let selected: ClientTab
    var messagesUnreadCount: Int = 0
    let onSelect: (ClientTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClientTab.barTabs) { tab in
                ClientTabItem(
                    tab: tab,
                    isActive: tab == selected,
                    badgeCount: tab == .messages ? messagesUnreadCount : 0
                ) { onSelect(tab) }
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
    var badgeCount: Int = 0
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

                    if badgeCount > 0 {
                        UnreadCountBadge(count: badgeCount, compact: true)
                            .offset(x: 14, y: -10)
                            .transaction { $0.animation = nil }
                    }
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
