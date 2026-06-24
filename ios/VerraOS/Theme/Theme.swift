//
//  Theme.swift
//  VerraOS
//
//  Central design system: colors, typography, spacing, radii, shadows.
//

import SwiftUI

/// VerraOS design tokens. Editorial "paper" aesthetic with a single
/// electric-lime accent reserved for active / emphasis states.
enum Theme {
    // MARK: Colors
    enum Color {
        /// Warm bone paper background.
        static let background = SwiftUI.Color(hex: 0xF4F1EA)
        /// Pure surface for cards / sheets.
        static let surface = SwiftUI.Color.white
        /// Slightly recessed surface for nested fills.
        static let surfaceMuted = SwiftUI.Color(hex: 0xEDE9E0)
        /// Warm near-black ink for primary text.
        static let ink = SwiftUI.Color(hex: 0x1A1A17)
        /// Secondary muted text.
        static let inkMuted = SwiftUI.Color(hex: 0x8C887E)
        /// Faint text / icons.
        static let inkFaint = SwiftUI.Color(hex: 0xB6B2A8)
        /// Electric lime accent.
        static let accent = SwiftUI.Color(hex: 0xC2F23C)
        /// Deep accent ink used on lime fills.
        static let accentInk = SwiftUI.Color(hex: 0x222417)
        /// Hairline separators.
        static let hairline = SwiftUI.Color(hex: 0x1A1A17).opacity(0.08)
        /// Notification badge.
        static let danger = SwiftUI.Color(hex: 0xE8483D)
    }

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 32
    }

    // MARK: Radius
    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 26
        static let pill: CGFloat = 999
    }
}

extension Color {
    /// Initialize a Color from a 0xRRGGBB hex literal.
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension View {
    /// Soft elevated card shadow used across the app.
    func cardShadow(_ strength: Double = 1) -> some View {
        self.shadow(color: Color(hex: 0x1A1A17).opacity(0.05 * strength), radius: 18, x: 0, y: 10)
            .shadow(color: Color(hex: 0x1A1A17).opacity(0.03 * strength), radius: 2, x: 0, y: 1)
    }
}
