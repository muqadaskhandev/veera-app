import SwiftUI

struct MessageDeliveryIndicator: View {
    let status: MessageDeliveryStatus
    var onAccentBackground: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            checkmarks
            if status == .read {
                Text("Seen")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(foregroundColor)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var checkmarks: some View {
        if status == .sent {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
        } else {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .offset(x: -4, y: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .offset(x: 4, y: -1)
            }
            .frame(width: 18, height: 10)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .sent:
            return onAccentBackground ? Theme.Color.accentInk.opacity(0.55) : Theme.Color.inkFaint
        case .delivered:
            return onAccentBackground ? Theme.Color.accentInk.opacity(0.75) : Theme.Color.inkMuted
        case .read:
            return onAccentBackground ? Theme.Color.accentInk : Theme.Color.ink
        }
    }

    private var accessibilityText: String {
        switch status {
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .read: return "Seen"
        }
    }
}
