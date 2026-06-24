//
//  ReadOnlyEnvironment.swift
//  VerraOS
//

import SwiftUI

/// Environment flag that puts shared profile module screens into read-only mode.
/// The trainer experience leaves this `false`; the client experience sets it to
/// `true` so edit / add / delete affordances are hidden while the same screens
/// are reused as a view-only window into the trainer's data.
private struct ReadOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isReadOnly: Bool {
        get { self[ReadOnlyKey.self] }
        set { self[ReadOnlyKey.self] = newValue }
    }
}

extension String {
    /// Up to two uppercased initials derived from the words in the string.
    var initialsValue: String {
        let parts = split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }
        return String(letters).uppercased()
    }
}
