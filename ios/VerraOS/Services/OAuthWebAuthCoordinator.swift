import AuthenticationServices
import Foundation
import UIKit

enum OAuthWebAuthError: LocalizedError {
    case cancelled
    case missingCallback
    case presentationFailed
    case sessionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .missingCallback:
            return "Authorization did not return a callback URL."
        case .presentationFailed:
            return "Could not open the sign-in browser. Close any open sheets and try again."
        case .sessionAlreadyActive:
            return "Another sign-in is already in progress. Wait a moment and try again."
        }
    }
}

/// Presents OAuth in ASWebAuthenticationSession and resumes the awaiting task exactly once.
@MainActor
final class OAuthWebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthWebAuthCoordinator()

    private var session: ASWebAuthenticationSession?
    private var pendingContinuation: CheckedContinuation<URL, Error>?

    func start(url: URL, callbackScheme: String) async throws -> URL {
        guard pendingContinuation == nil, session == nil else {
            throw OAuthWebAuthError.sessionAlreadyActive
        }
        guard !callbackScheme.isEmpty else {
            throw OAuthWebAuthError.missingCallback
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
            finish(with: .failure(OAuthWebAuthError.presentationFailed))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        AuthPresentationAnchor.keyWindow()
    }

    private func handleCompletion(callbackURL: URL?, error: Error?) {
        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            finish(with: .failure(OAuthWebAuthError.cancelled))
            return
        }
        if let error {
            finish(with: .failure(error))
            return
        }
        guard let callbackURL else {
            finish(with: .failure(OAuthWebAuthError.missingCallback))
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

enum OAuthCallback {
    static func scheme(from redirectURI: String) -> String {
        if let scheme = URL(string: redirectURI)?.scheme, !scheme.isEmpty {
            return scheme
        }
        return "app.rork.hiyjy25oz4yjrbssyotkw"
    }
}
