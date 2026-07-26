import SwiftUI

enum NumericText {
    /// Keeps digits only, or digits plus a single decimal separator.
    static func sanitize(_ raw: String, allowDecimal: Bool) -> String {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        if !allowDecimal {
            return normalized.filter(\.isNumber)
        }
        var result = ""
        var seenDot = false
        for ch in normalized {
            if ch.isNumber {
                result.append(ch)
            } else if ch == ".", !seenDot {
                result.append(".")
                seenDot = true
            }
        }
        return result
    }
}

extension View {
    /// Strips non-numeric characters from a string field as the user types.
    func numbersOnly(_ text: Binding<String>, allowDecimal: Bool = false) -> some View {
        modifier(NumbersOnlyModifier(text: text, allowDecimal: allowDecimal))
    }
}

private struct NumbersOnlyModifier: ViewModifier {
    @Binding var text: String
    let allowDecimal: Bool

    func body(content: Content) -> some View {
        content.onChange(of: text) { _, newValue in
            let filtered = NumericText.sanitize(newValue, allowDecimal: allowDecimal)
            guard filtered != newValue else { return }
            // Bounce when needed so TextField drops rejected keystrokes from its buffer.
            if filtered == text {
                text = filtered + "\u{200B}"
                DispatchQueue.main.async { text = filtered }
            } else {
                text = filtered
            }
        }
    }
}
