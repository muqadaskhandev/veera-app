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

        let callbackScheme = callbackScheme(from: authorize.redirectURI)
        let callbackURL = try await OuraWebAuthCoordinator.shared.start(url: authURL, callbackScheme: callbackScheme)

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

    /// ASWebAuthenticationSession expects the URL *scheme* only, not the full redirect URI.
    private static func callbackScheme(from redirectURI: String) -> String {
        if let scheme = URL(string: redirectURI)?.scheme, !scheme.isEmpty {
            return scheme
        }
        return "app.rork.hiyjy25oz4yjrbssyotkw"
    }
}

/// Presents Oura OAuth and resumes the awaiting task exactly once.
@MainActor
private final class OuraWebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OuraWebAuthCoordinator()

    private var session: ASWebAuthenticationSession?
    private var pendingContinuation: CheckedContinuation<URL, Error>?

    func start(url: URL, callbackScheme: String) async throws -> URL {
        guard pendingContinuation == nil, session == nil else {
            throw OuraAuthError.sessionAlreadyActive
        }
        guard !callbackScheme.isEmpty else {
            throw OuraAuthError.missingCode
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.handleCompletion(callbackURL: callbackURL, error: error)
                }
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            self.session = session

            Task { @MainActor in
                await Task.yield()
                await self.presentSessionIfNeeded()
            }
        }
    }

    private func presentSessionIfNeeded() async {
        guard let session else { return }
        if !session.start() {
            finish(with: .failure(OuraAuthError.presentationFailed))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        AuthPresentationAnchor.keyWindow()
    }

    private func handleCompletion(callbackURL: URL?, error: Error?) {
        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            finish(with: .failure(OuraAuthError.cancelled))
            return
        }
        if let error {
            finish(with: .failure(error))
            return
        }
        guard let callbackURL else {
            finish(with: .failure(OuraAuthError.missingCode))
            return
        }
        finish(with: .success(callbackURL))
    }

    private func finish(with result: Result<URL, Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        session = nil

        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
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
