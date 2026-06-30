import SwiftUI

/// Custom-styled Apple sign-in control. Uses `ASAuthorizationController` directly
/// instead of `SignInWithAppleButton` for reliable presentation in overlays.
struct AppleSignInButton: View {
    let label: String
    let isDisabled: Bool
    let onResult: (Result<AppleSignInResult, Error>) -> Void

    init(
        label: String = "Continue with Apple",
        isDisabled: Bool = false,
        onResult: @escaping (Result<AppleSignInResult, Error>) -> Void
    ) {
        self.label = label
        self.isDisabled = isDisabled
        self.onResult = onResult
    }

    var body: some View {
        Button {
            Task { await performSignIn() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk)
                Text(label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @MainActor
    private func performSignIn() async {
        guard !isDisabled else { return }
        do {
            let result = try await AppleSignInService.signIn()
            onResult(.success(result))
        } catch {
            onResult(.failure(error))
        }
    }
}
