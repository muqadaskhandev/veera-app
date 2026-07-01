import AuthenticationServices
import Foundation
import UIKit

struct AppleSignInResult {
    let userID: String
    let identityToken: String
    let email: String?
    let displayName: String?
}

enum AppleSignInService {
    @MainActor
    static func signIn() async throws -> AppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate { result in
                continuation.resume(with: result)
            }
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // Keep controller + delegate alive until Apple calls back.
            delegate.retainSelf = delegate
            delegate.retainController = controller
            controller.performRequests()
        }
    }

    static func result(from authorization: ASAuthorization) throws -> AppleSignInResult {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.server("Apple Sign-In did not return a valid token")
        }

        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let displayName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

        AppleCredentialStore.appleUserID = credential.user

        return AppleSignInResult(
            userID: credential.user,
            identityToken: identityToken,
            email: credential.email,
            displayName: displayName
        )
    }

    static func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain {
            switch nsError.code {
            case ASAuthorizationError.canceled.rawValue:
                return APIError.server("Apple Sign-In was cancelled")
            case ASAuthorizationError.unknown.rawValue:
                return APIError.server(
                    "Sign in with Apple is not configured for this build. In Xcode, select your Development Team, confirm the Sign in with Apple capability is enabled, and enable it on your App ID in the Apple Developer portal."
                )
            case ASAuthorizationError.invalidResponse.rawValue:
                return APIError.server("Apple Sign-In returned an invalid response. Try again or use a physical device.")
            case ASAuthorizationError.notHandled.rawValue:
                return APIError.server("Apple Sign-In could not be presented. Try again.")
            case ASAuthorizationError.failed.rawValue:
                return APIError.server("Apple Sign-In failed. Sign into an Apple ID in Settings and try again.")
            default:
                break
            }
        }
        return error
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<AppleSignInResult, Error>) -> Void
    var retainSelf: AppleSignInDelegate?
    var retainController: ASAuthorizationController?

    init(completion: @escaping (Result<AppleSignInResult, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
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

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { release() }
        do {
            completion(.success(try AppleSignInService.result(from: authorization)))
        } catch {
            completion(.failure(error))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { release() }
        completion(.failure(AppleSignInService.mapError(error)))
    }

    private func release() {
        retainSelf = nil
        retainController = nil
    }
}
