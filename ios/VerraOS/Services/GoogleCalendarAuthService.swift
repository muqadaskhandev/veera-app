import Foundation

struct GoogleCalendarAuthorizeResponse: Decodable {
    let authorizationURL: String
    let state: String
    let redirectURI: String
}

struct GoogleCalendarStatusResponse: Decodable {
    let connected: Bool
    let configured: Bool
}

enum GoogleCalendarAuthError: LocalizedError {
    case cancelled
    case missingCode
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Google Calendar sign-in was cancelled."
        case .missingCode:
            return "Google did not return an authorization code. Register http://127.0.0.1:8080/api/calendar/google/oauth/callback as a Web OAuth redirect URI in Google Cloud Console."
        case .notConfigured:
            return "Google Calendar is not configured on the server. Add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to backend/.env and restart the backend."
        }
    }
}

enum GoogleCalendarAuthService {
    @MainActor
    static func connect(accessToken: String) async throws {
        let authorize = try await VerraAPI.fetchGoogleCalendarAuthorize(accessToken: accessToken)
        guard let authURL = URL(string: authorize.authorizationURL) else {
            throw APIError.invalidURL
        }

        let callbackScheme = OAuthCallback.scheme(from: authorize.redirectURI)
        let callbackURL = try await OAuthWebAuthCoordinator.shared.start(url: authURL, callbackScheme: callbackScheme)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarAuthError.missingCode
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw APIError.server("Google authorization failed: \(error)")
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw GoogleCalendarAuthError.missingCode
        }

        _ = try await VerraAPI.completeGoogleCalendarOAuth(code: code, state: state, accessToken: accessToken)
    }
}
