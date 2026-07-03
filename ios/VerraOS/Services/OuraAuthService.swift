import AuthenticationServices
import Foundation
import UIKit

struct OuraAuthorizeResponse: Decodable {
    let authorizationURL: String
    let state: String
    let redirectURI: String
}

enum OuraAuthError: LocalizedError {
    case cancelled
    case missingCode
    case notConfigured
    case presentationFailed
    case sessionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Oura sign-in was cancelled."
        case .missingCode:
            return "Oura did not return an authorization code. Confirm the redirect URI in the Oura developer portal is exactly: app.rork.hiyjy25oz4yjrbssyotkw://oura/callback"
        case .notConfigured:
            return "Oura is not configured on the server. Add OURA_CLIENT_ID and OURA_CLIENT_SECRET to backend/.env and restart the backend."
        case .presentationFailed:
            return "Could not open the Oura sign-in browser. Close any open sheets and try again."
        case .sessionAlreadyActive:
            return "Another sign-in is already in progress. Wait a moment and try again."
        }
    }
}

/// Runs the Oura OAuth flow in ASWebAuthenticationSession and completes it on the backend.
enum OuraAuthService {
    @MainActor
    static func connect(accessToken: String) async throws {
        let authorize = try await VerraAPI.fetchOuraAuthorize(accessToken: accessToken)
        guard let authURL = URL(string: authorize.authorizationURL) else {
            throw APIError.invalidURL
        }

        let callbackScheme = OAuthCallback.scheme(from: authorize.redirectURI)
        let callbackURL = try await OAuthWebAuthCoordinator.shared.start(url: authURL, callbackScheme: callbackScheme)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OuraAuthError.missingCode
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw APIError.server("Oura authorization failed: \(error)")
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw OuraAuthError.missingCode
        }

        _ = try await VerraAPI.completeOuraOAuth(code: code, state: state, accessToken: accessToken)
    }
}

/// Shared window lookup for OAuth / Sign in with Apple presentation anchors.
enum AuthPresentationAnchor {
    @MainActor
    static func keyWindow() -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes
            .sorted(by: { $0.activationState.rawValue > $1.activationState.rawValue })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }
        if let window = scenes.flatMap(\.windows).first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }
}
