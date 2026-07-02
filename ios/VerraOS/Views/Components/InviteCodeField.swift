import SwiftUI

/// Shared invite-code input used in onboarding and client settings.
struct InviteCodeField: View {
    enum Style {
        case onboarding
        case settings
    }

    @Binding var code: String
    var style: Style = .settings

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Color.accent)
            TextField("", text: $code, prompt: Text("INVITE CODE").foregroundColor(promptColor))
                .focused($focused)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .tracking(2)
                .onChange(of: code) { _, newValue in
                    code = newValue.uppercased()
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(focused ? Theme.Color.accent : borderColor, lineWidth: 1)
        )
    }

    private var textColor: Color {
        style == .onboarding ? .white : Theme.Color.ink
    }

    private var promptColor: Color {
        style == .onboarding ? .white.opacity(0.4) : Theme.Color.inkFaint
    }

    private var backgroundColor: Color {
        style == .onboarding ? Color.white.opacity(0.08) : Theme.Color.surfaceMuted
    }

    private var borderColor: Color {
        style == .onboarding ? .white.opacity(0.18) : Theme.Color.hairline
    }
}
