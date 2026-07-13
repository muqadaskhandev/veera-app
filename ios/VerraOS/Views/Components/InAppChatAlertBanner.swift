import SwiftUI

/// Lightweight banner shown at the top for chat / account alerts.
struct InAppChatAlertBanner: View {
    let title: String
    let bodyText: String
    var symbol: String = "bubble.left.fill"
    var tint: Color = Color(hex: 0x3D7FE8)
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    Text(bodyText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.Color.hairline, lineWidth: 1))
            .cardShadow(1.2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.md)
        .preferredColorScheme(.light)
    }
}

struct IncomingChatAlert: Equatable {
    let title: String
    let body: String
    var conversationID: UUID? = nil
    var opensSchedule: Bool = false
    var symbol: String = "bubble.left.fill"
    var tintHex: UInt = 0x3D7FE8
}
