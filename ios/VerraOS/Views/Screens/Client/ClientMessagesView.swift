//
//  ClientMessagesView.swift
//  VerraOS
//
//  The client's single chat thread with their coach. There's only one trainer,
//  so this opens straight into the conversation — no inbox list. Full-screen,
//  with a back chevron that returns to the rest of the tabs.
//

import SwiftUI

struct ClientMessagesView: View {
    let conversationID: UUID
    let coachName: String
    let coachSubtitle: String
    /// Returns the client to the other tabs (the bottom nav is hidden here).
    var onExit: () -> Void = {}

    @State private var path = NavigationPath()

    var body: some View {
        ChatThreadView(
            conversationID: conversationID,
            path: $path,
            coachMode: true,
            coachName: coachName,
            coachSubtitle: coachSubtitle,
            showsBack: true,
            onBack: onExit
        )
    }
}
