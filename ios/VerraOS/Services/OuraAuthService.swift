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

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Oura sign-in was cancelled."
        case .missingCode: return "Oura did not return an authorization code."
        case .notConfigured: return "Oura is not configured on the server."
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

        let callbackScheme = URL(string: authorize.redirectURI)?.scheme ?? "app.rork.hiyjy25oz4yjrbssyotkw"
        let callbackURL = try await presentAuthSession(url: authURL, callbackScheme: callbackScheme)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw OuraAuthError.missingCode
        }

        _ = try await VerraAPI.completeOuraOAuth(code: code, state: state, accessToken: accessToken)
    }

    @MainActor
    private static func presentAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: OuraAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OuraAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = OuraAuthPresentationContext.shared
            OuraAuthPresentationContext.shared.retainedSession = session
            guard session.start() else {
                continuation.resume(throwing: OuraAuthError.notConfigured)
            }
        }
    }
}

@MainActor
private final class OuraAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OuraAuthPresentationContext()
    var retainedSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
