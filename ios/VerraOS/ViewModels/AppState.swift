//
//  AppState.swift
//  VerraOS
//

import SwiftUI

/// Global UI state for the app shell: which tab is active and whether the
/// profile drawer is presented.
@Observable
final class AppState {
    var selectedTab: NavTab = .schedule
    var isDrawerOpen: Bool = false
    var hasUnreadNotification: Bool = true

    /// Set when another tab requests opening a specific client's chat thread.
    /// The Messages tab observes this, opens the thread, then clears it.
    var pendingChatClientID: UUID?

    /// True while a full-screen chat thread is on screen, so the shell can hide
    /// the bottom navigation bar.
    var isChatThreadOpen: Bool = false

    /// Trainer profile shown in the drawer header.
    let trainerName = "Jordan Vale"
    let trainerTitle = "Head Strength Coach"
    let appVersion = "v1.0.2"

    func openDrawer() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isDrawerOpen = true
        }
    }

    func closeDrawer() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            isDrawerOpen = false
        }
    }

    func select(_ tab: NavTab) {
        guard tab != selectedTab else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
        }
    }

    /// Switches to the Messages tab and asks it to open the given client's thread.
    func openChat(with clientID: UUID) {
        pendingChatClientID = clientID
        select(.messages)
    }
}
