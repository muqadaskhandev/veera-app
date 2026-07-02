//
//  MessagesView.swift
//  VerraOS
//
//  Level 1 — the inbox. A searchable list of client conversations with unread
//  dots, last-message previews, and a FAB to start a new thread. Pushes into the
//  chat thread and on into the client profile hub.
//

import SwiftUI

struct MessagesView: View {
    @Environment(MessageStore.self) private var store
    @Environment(ClientStore.self) private var clientStore
    @Environment(AppState.self) private var app

    @State private var search: String = ""
    @State private var path = NavigationPath()
    @State private var showingNew = false

    private var rows: [Conversation] {
        store.inbox(search: search)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Color.background.ignoresSafeArea()
                content
            }
            .overlay(alignment: .bottomTrailing) { newButton }
            .navigationBarHidden(true)
            .navigationDestination(for: Conversation.self) { convo in
                ChatThreadView(conversationID: convo.id, path: $path)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: Client.self) { client in
                ClientProfileView(clientID: client.id) { if !path.isEmpty { path.removeLast() } }
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .navigationDestination(for: ModuleRoute.self) { route in
                ProfileModuleRouter(route: route) { if !path.isEmpty { path.removeLast() } }
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .sheet(isPresented: $showingNew) {
            NewMessageSheet { client in
                showingNew = false
                Task {
                    let id = await store.threadID(for: client)
                    if let convo = store.conversation(id: id) {
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(convo)
                    }
                }
            }
        }
        .onAppear { openPendingChatIfNeeded() }
        .onChange(of: app.pendingChatClientID) { _, _ in openPendingChatIfNeeded() }
        .onChange(of: app.pendingChatConversationID) { _, _ in openPendingChatIfNeeded() }
    }

    /// Opens the thread requested from another tab or a push notification.
    private func openPendingChatIfNeeded() {
        if let conversationID = app.pendingChatConversationID {
            app.pendingChatConversationID = nil
            guard let convo = store.conversation(id: conversationID) else { return }
            store.markRead(convo.id)
            path = NavigationPath()
            path.append(convo)
            return
        }

        guard let clientID = app.pendingChatClientID,
              let client = clientStore.clients.first(where: { $0.id == clientID }) else { return }
        app.pendingChatClientID = nil
        Task {
            let id = await store.threadID(for: client)
            guard let convo = store.conversation(id: id) else { return }
            store.markRead(convo.id)
            path = NavigationPath()
            path.append(convo)
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                countHeader
                searchField
                if rows.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(rows) { convo in
                            Button {
                                store.markRead(convo.id)
                                path.append(convo)
                            } label: {
                                ConversationRow(conversation: convo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 100)
        }
    }

    private var countHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Inbox")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(store.conversations.count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("conversations")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                if store.unreadCount > 0 {
                    Text("\(store.unreadCount) new")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.Color.accent, in: Capsule())
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            TextField("Search by name", text: $search)
                .font(.system(size: 15, weight: .medium))
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
        .background(Theme.Color.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(search.isEmpty ? "No conversations yet" : "No matches for \"\(search)\"")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var newButton: some View {
        Button { showingNew = true } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 58, height: 58)
                .background(Theme.Color.accent, in: Circle())
                .overlay(Circle().stroke(Theme.Color.accentInk.opacity(0.12), lineWidth: 1))
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityLabel("New message")
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Color.ink)
                    .frame(width: 50, height: 50)
                Text(conversation.initials)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.clientName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(relativeTime(minutes: conversation.lastMinutesAgo))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                HStack(spacing: 6) {
                    Text(conversation.lastMessage?.kind.preview ?? conversation.lastMessagePreview ?? "No messages yet")
                        .font(.system(size: 13.5, weight: conversation.isUnread ? .semibold : .medium))
                        .foregroundStyle(conversation.isUnread ? Theme.Color.ink : Theme.Color.inkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if conversation.isUnread {
                        Circle()
                            .fill(Theme.Color.accent)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.6)
    }
}

// MARK: - New message sheet

private struct NewMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ClientStore.self) private var clientStore
    var onPick: (Client) -> Void

    @State private var search: String = ""

    private var results: [Client] {
        let active = clientStore.activeClients
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                    TextField("Search roster", text: $search)
                        .font(.system(size: 15, weight: .medium))
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
                .background(Theme.Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(results) { client in
                            Button { onPick(client) } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Theme.Color.ink)
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Text(client.initials)
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundStyle(Theme.Color.accent)
                                        )
                                    Text(client.name)
                                        .font(.system(size: 15.5, weight: .semibold))
                                        .foregroundStyle(Theme.Color.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Theme.Color.inkFaint)
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .background(Theme.Color.background)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.inkMuted)
                }
            }
        }
    }
}
