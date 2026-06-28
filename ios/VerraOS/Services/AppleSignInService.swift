import AuthenticationServices
import UIKit

struct AppleSignInResult {
    let identityToken: String
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
            delegate.retainSelf = delegate
            controller.performRequests()
        }
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<AppleSignInResult, Error>) -> Void
    var retainSelf: AppleSignInDelegate?

    init(completion: @escaping (Result<AppleSignInResult, Error>) -> Void) {
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { retainSelf = nil }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            completion(.failure(APIError.server("Apple Sign-In did not return a valid token")))
            return
        }

        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let displayName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

        completion(.success(AppleSignInResult(identityToken: identityToken, displayName: displayName)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { retainSelf = nil }
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            completion(.failure(APIError.server("Apple Sign-In was cancelled")))
        } else {
            completion(.failure(error))
        }
    }
}
