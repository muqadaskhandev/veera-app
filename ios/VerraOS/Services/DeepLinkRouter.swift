//
//  DeepLinkRouter.swift
//  VerraOS
//
//  Parses universal links (https://verraos.app/...) and the `verraos://`
//  custom-scheme fallback, extracting invite codes so a client can be routed
//  straight into the "connect your coach" flow. Kept as a lightweight
//  singleton so a link tapped before login (or before onboarding finishes)
//  isn't lost — whichever screen owns the redeem sheet consumes it later.
//

import Foundation

@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    private init() {}

    /// An invite code extracted from a `/join?code=` or `/invite/<code>` link,
    /// waiting to be picked up by the client shell.
    private(set) var pendingInviteCode: String?

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        let path = components.path

        if path.hasPrefix("/join"), let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            setPendingCode(code)
            return
        }

        if path.hasPrefix("/invite/") {
            let code = path.replacingOccurrences(of: "/invite/", with: "")
            setPendingCode(code)
            return
        }

        // Custom-scheme fallback, e.g. verraos://join?code=ABC123
        if components.host == "join" || path.isEmpty, let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            setPendingCode(code)
        }
    }

    /// Returns the pending code (if any) and clears it so it's only applied once.
    func consumePendingCode() -> String? {
        let code = pendingInviteCode
        pendingInviteCode = nil
        return code
    }

    private func setPendingCode(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingInviteCode = trimmed
        NotificationCenter.default.post(name: .deepLinkInviteCodeReceived, object: trimmed)
    }
}

extension Notification.Name {
    static let deepLinkInviteCodeReceived = Notification.Name("deepLinkInviteCodeReceived")
}
