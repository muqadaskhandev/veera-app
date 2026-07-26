//
//  Theme.swift
//  VerraOS
//
//  Central design system: colors, typography, spacing, radii, shadows.
//

import SwiftUI
import UIKit

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

    /// Layout helpers for the fixed bottom tab bar.
    enum Layout {
        /// Extra scroll content inset so the last rows clear the sticky tab bar
        /// even when nested `NavigationStack` destinations don't fully inherit
        /// the parent's bottom `safeAreaInset`.
        static let scrollBottomPadding: CGFloat = 96
    }
}

enum Keyboard {
    /// Resigns the current first responder (any focused text field).
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
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

    /// Keeps the last scroll row above the sticky tab bar and home indicator.
    func tabScrollContent() -> some View {
        contentMargins(.bottom, Theme.Layout.scrollBottomPadding, for: .scrollContent)
    }

    /// Lets the keyboard follow a drag / swipe on a `ScrollView`, dismissing
    /// interactively as the user scrolls away from the focused field.
    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
    }

    /// Dismisses the keyboard when the user taps empty space (outside fields).
    /// Uses a simultaneous gesture so buttons and text fields still receive taps.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded { _ in
                Keyboard.dismiss()
            }
        )
    }

    /// Adds a Done button above the software keyboard so number/decimal pads
    /// (which lack a return key) can be dismissed explicitly.
    func keyboardDismissToolbar(_ title: String = "Done") -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(title) { Keyboard.dismiss() }
                    .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    /// Combined keyboard UX for form/scroll screens: swipe-to-dismiss,
    /// tap-outside, and a Done button on the keyboard accessory bar.
    func formKeyboardBehavior() -> some View {
        self
            .dismissKeyboardOnScroll()
            .dismissKeyboardOnTap()
            .keyboardDismissToolbar()
    }
}
