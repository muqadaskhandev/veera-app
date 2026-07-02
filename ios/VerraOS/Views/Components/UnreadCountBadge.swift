import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        Text(displayText)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Color.accentInk)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: compact ? 16 : 18, minHeight: compact ? 16 : 18)
            .background(Theme.Color.accent, in: Capsule())
    }

    private var displayText: String {
        if count > 99 { return "99+" }
        return "\(count)"
    }
}
