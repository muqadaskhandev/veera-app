//
//  ClientsView.swift
//  VerraOS
//

import SwiftUI

/// Level 1 Clients directory: a searchable, sortable roster with color-coded
/// status badges, quick actions, archive access, and a first-run empty state.
struct ClientsView: View {
    @Environment(ClientStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(MessageStore.self) private var messages

    @State private var search: String = ""
    @State private var sort: ClientSort = .status
    @State private var showArchived: Bool = false
    @State private var showingFilters: Bool = false

    @State private var showingAdd = false
    @State private var deleteCandidate: Client?
    @State private var invitePayload: InvitePayload?
    @State private var toast: ToastData?
    @State private var path = NavigationPath()

    private var rows: [Client] {
        store.roster(search: search, sort: sort, showArchived: showArchived)
    }

    private var hasAnyClients: Bool { !store.clients.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if !hasAnyClients {
                    EmptyRosterView { showingAdd = true }
                } else {
                    content
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hasAnyClients { addButton }
            }
            .navigationBarHidden(true)
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
        .toast($toast)
        .sheet(isPresented: $showingAdd) {
            AddClientView { message in
                toast = ToastData(message: message, icon: "paperplane.fill")
            }
        }
        .sheet(item: $invitePayload, onDismiss: {
            toast = ToastData(message: "Invite link ready to share", icon: "link")
        }) { payload in
            ShareSheet(items: [payload.message])
        }
        .confirmationDialog(
            "Delete \(deleteCandidate?.name ?? "client")?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let c = deleteCandidate {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.delete(c) }
                    toast = ToastData(message: "\(c.name.firstWord) deleted", icon: "trash.fill")
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This permanently removes all of their data. This can't be undone.")
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                countHeader
                searchField
                if showingFilters { filterPanel }
                if rows.isEmpty {
                    noMatchState
                } else {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(rows) { client in
                            ClientRow(
                                client: client,
                                onProfile: { path.append(client) },
                                onChat: {
                                    Task {
                                        _ = await messages.threadID(for: client)
                                        app.openChat(with: client.id)
                                    }
                                },
                                onArchive: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        if showArchived { store.restore(client) } else { store.archive(client) }
                                    }
                                    toast = ToastData(
                                        message: showArchived ? "\(client.name.firstWord) restored" : "\(client.name.firstWord) archived",
                                        icon: showArchived ? "arrow.uturn.up" : "archivebox.fill"
                                    )
                                },
                                onDelete: { deleteCandidate = client },
                                onInvite: { invitePayload = InvitePayload(client: client) },
                                isArchivedContext: showArchived
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 100)
        }
    }

    // MARK: Count header

    private var countHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showArchived ? "Archived" : "Roster")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(showArchived ? store.archivedCount : store.activeClients.count)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text(showArchived ? "archived" : "active clients")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { showingFilters.toggle() }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(showingFilters ? Theme.Color.accentInk : Theme.Color.ink)
                    .frame(width: 42, height: 42)
                    .background(showingFilters ? Theme.Color.accent : Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: showingFilters ? 0 : 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            TextField("Search clients", text: $search)
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

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SORT BY")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.Color.inkFaint)
            HStack(spacing: 6) {
                ForEach(ClientSort.allCases) { item in
                    let isActive = item == sort
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { sort = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(isActive ? Theme.Color.accentInk : Theme.Color.inkMuted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(isActive ? Theme.Color.accent : Theme.Color.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Theme.Color.hairline).frame(height: 1)

            Toggle(isOn: $showArchived) {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                    Text("Show Archived")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                    if store.archivedCount > 0 {
                        Text("\(store.archivedCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Color.inkMuted)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.Color.surfaceMuted, in: Capsule())
                    }
                }
            }
            .tint(Theme.Color.accent)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: showArchived ? "archivebox" : "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Color.inkFaint)
            Text(showArchived ? "No archived clients" : "No clients match \"\(search)\"")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Floating add button

    private var addButton: some View {
        Button { showingAdd = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 58, height: 58)
                .background(Theme.Color.accent, in: Circle())
                .overlay(Circle().stroke(Theme.Color.accentInk.opacity(0.12), lineWidth: 1))
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .accessibilityLabel("Add client")
    }
}

// MARK: - Client row

private struct ClientRow: View {
    let client: Client
    var onProfile: () -> Void
    var onChat: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void
    var onInvite: () -> Void
    var isArchivedContext: Bool

    private var status: ClientStatus { client.effectiveStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(client.sessionsRemaining) sessions left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(1)
                }

                Menu {
                    Button { onInvite() } label: { Label("Share Invite Link", systemImage: "square.and.arrow.up") }
                    if isArchivedContext {
                        Button { onArchive() } label: { Label("Restore", systemImage: "arrow.uturn.up") }
                    } else {
                        Button { onArchive() } label: { Label("Archive", systemImage: "archivebox") }
                    }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(width: 32, height: 32)
                        .background(Theme.Color.surfaceMuted, in: Circle())
                }
            }

            HStack(spacing: 10) {
                StatusBadge(status: status)
                Spacer(minLength: 6)
                Button(action: onChat) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 32, height: 32)
                        .background(Theme.Color.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chat")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onProfile)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        .cardShadow(0.7)
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.Color.ink)
            .frame(width: 46, height: 46)
            .overlay(
                Text(client.initials)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(status.tint)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Theme.Color.surface, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
    }
}

private struct StatusBadge: View {
    let status: ClientStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(status.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(status.soft, in: Capsule())
    }
}

// MARK: - Empty state

private struct EmptyRosterView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(Theme.Color.surface)
                    .frame(width: 110, height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.Color.hairline, lineWidth: 1))
                    .cardShadow()
                Image(systemName: "list.clipboard")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.Color.ink)
            }

            VStack(spacing: 8) {
                Text("No clients yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("Invite a client via email or SMS to start tracking their progress.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text("Add Your First Client")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .padding(.horizontal, 24)
                .padding(.vertical, 15)
                .background(Theme.Color.accent, in: Capsule())
                .shadow(color: Theme.Color.accent.opacity(0.5), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
