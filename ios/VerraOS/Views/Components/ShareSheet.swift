//
//  ShareSheet.swift
//  VerraOS
//
//  A thin SwiftUI wrapper over UIActivityViewController so we can present the
//  native iOS share sheet programmatically (e.g. from inside a context menu).
//

import SwiftUI
import UIKit

/// Identifiable payload for sharing a client invite link via `.sheet(item:)`.
struct InvitePayload: Identifiable {
    let id = UUID()
    let clientName: String
    let url: URL

    /// Friendly, personalized invite message paired with the download link.
    var message: String {
        let first = clientName.split(separator: " ").first.map(String.init) ?? clientName
        return "Hi \(first)! I'm tracking your training on VerraOS. Download the app and join me here: \(url.absoluteString)"
    }
}

extension InvitePayload {
    /// Builds an invite link from a real, backend-issued join code.
    init(clientName: String, code: String) {
        self.init(
            clientName: clientName,
            url: URL(string: "https://verraos.app/join?code=\(code)")!
        )
    }
}

/// Presents the system share sheet with the given activity items.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
