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
    /// Uses the API host so the smart `/join` page can open the app or App Store.
    init(clientName: String, code: String) {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        let url = URL(string: "join?code=\(encoded)", relativeTo: APIConfig.baseURL)?.absoluteURL
            ?? URL(string: "https://veera-app.onrender.com/join?code=\(encoded)")!
        self.init(clientName: clientName, url: url)
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
