//
//  ProfileData.swift
//  VerraOS
//

import SwiftUI

/// A module that can be shown or hidden on an individual client's profile hub.
enum ProfileModule: String, CaseIterable, Identifiable, Hashable {
    case wearables
    case workout
    case nutrition
    case weight
    case photos
    case financials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wearables: return "Wearables"
        case .workout: return "Workout Plan"
        case .nutrition: return "Nutrition"
        case .weight: return "Weight"
        case .photos: return "Progress Photos"
        case .financials: return "Financials"
        }
    }

    var icon: String {
        switch self {
        case .wearables: return "heart.text.square.fill"
        case .workout: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .weight: return "scalemass.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .financials: return "dollarsign.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .wearables: return "Sleep · Heart · Activity"
        case .workout: return "Weekly training plan"
        case .nutrition: return "Macros · Supplements"
        case .weight: return "Trend & goals"
        case .photos: return "Visual progress"
        case .financials: return "Session ledger"
        }
    }

    /// Whether this module is visible by default on a new profile.
    var defaultOn: Bool {
        switch self {
        case .wearables, .financials: return true
        default: return false
        }
    }
}

// MARK: - Data points

struct WeightEntry: Identifiable, Hashable {
    let id: UUID
    /// Days before today (0 = today).
    var daysAgo: Int
    var kg: Double

    init(id: UUID = UUID(), daysAgo: Int, kg: Double) {
        self.id = id
        self.daysAgo = daysAgo
        self.kg = kg
    }
}

enum LedgerKind {
    case packageAdded
    case sessionUsed
    case adjustment

    var tint: Color {
        switch self {
        case .packageAdded: return Color(hex: 0x57C77B)
        case .sessionUsed: return Theme.Color.inkMuted
        case .adjustment: return Color(hex: 0xE8893C)
        }
    }

    var icon: String {
        switch self {
        case .packageAdded: return "plus.circle.fill"
        case .sessionUsed: return "minus.circle.fill"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}

struct LedgerEntry: Identifiable, Hashable {
    static func == (lhs: LedgerEntry, rhs: LedgerEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    var date: Date
    var title: String
    var delta: Int
    var amount: Double?
    var kind: LedgerKind

    init(id: UUID = UUID(), date: Date, title: String, delta: Int, amount: Double? = nil, kind: LedgerKind) {
        self.id = id
        self.date = date
        self.title = title
        self.delta = delta
        self.amount = amount
        self.kind = kind
    }
}

struct Supplement: Identifiable, Hashable {
    let id: UUID
    var name: String
    var dosage: String

    init(id: UUID = UUID(), name: String, dosage: String) {
        self.id = id
        self.name = name
        self.dosage = dosage
    }
}

/// The role a row plays inside a day's plan.
enum WorkoutItemKind: String, Hashable {
    case exercise
    case header
    case rest
}

struct WorkoutExercise: Identifiable, Hashable {
    let id: UUID
    var name: String
    var sets: Int?
    var reps: Int?
    /// Whether this row is an exercise, a section header, or a rest day.
    var kind: WorkoutItemKind

    init(id: UUID = UUID(), name: String, sets: Int? = nil, reps: Int? = nil, kind: WorkoutItemKind = .exercise) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.kind = kind
    }

    var isHeader: Bool { kind == .header }
    var isRestItem: Bool { kind == .rest }

    /// Human-readable sets × reps summary, empty when unset or not an exercise.
    var detail: String {
        guard kind == .exercise else { return "" }
        switch (sets, reps) {
        case let (s?, r?): return "\(s) × \(r)"
        case let (s?, nil): return "\(s) sets"
        case let (nil, r?): return "\(r) reps"
        default: return ""
        }
    }
}

struct WorkoutDay: Identifiable, Hashable {
    let id: UUID
    let label: String
    var focus: String?
    var exercises: [WorkoutExercise]

    /// A day is a rest day only when it has no actual exercises.
    var isRest: Bool { !exercises.contains { $0.kind == .exercise } }

    init(id: UUID = UUID(), label: String, focus: String?, exercises: [WorkoutExercise]) {
        self.id = id
        self.label = label
        self.focus = focus
        self.exercises = exercises
    }
}

/// Editable daily macro targets. Calories are derived from the macro split.
struct MacroTargets: Hashable {
    var protein: Int
    var carbs: Int
    var fats: Int
    var calories: Int { protein * 4 + carbs * 4 + fats * 9 }
}

/// A single editable nutrition / protocol note.
struct NutritionNote: Identifiable, Hashable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// Editable start / goal weight overrides for a client.
struct WeightTargets: Hashable {
    var start: Double?
    var goal: Double?
}

/// A logged progress photo. No real image in the cloud simulator, so a tint
/// stands in for the captured photo while keeping the chronological log real.
struct ProgressPhoto: Identifiable, Hashable {
    let id: UUID
    var date: Date
    var tintHex: UInt

    init(id: UUID = UUID(), date: Date, tintHex: UInt) {
        self.id = id
        self.date = date
        self.tintHex = tintHex
    }

    var label: String { date.formatted(.dateTime.month(.abbreviated).year()) }

    /// Precise day-level date, e.g. "22 Jun 2026".
    var exactLabel: String { date.formatted(.dateTime.day().month(.abbreviated).year()) }
}

/// Static helpers shared across profile screens. No sample/demo data — the app
/// starts empty and is populated by real trainer/client input.
enum ProfileDemo {
    /// A completely blank week — every day starts empty until the trainer adds to it.
    static func emptyWeek() -> [WorkoutDay] {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map {
            WorkoutDay(label: $0, focus: nil, exercises: [])
        }
    }

    /// Reference list used by the workout builder's exercise search.
    static let exerciseLibrary: [String] = [
        "Back Squat", "Front Squat", "Bench Press", "Incline Bench Press", "Deadlift",
        "Romanian Deadlift", "Overhead Press", "Pull-Ups", "Chin-Ups", "Barbell Row",
        "Lat Pulldown", "Walking Lunge", "Bulgarian Split Squat", "Leg Press", "Hip Thrust",
        "Face Pull", "Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Plank",
        "Hanging Leg Raise", "Kettlebell Swing", "Assault Bike", "Box Jump",
    ]
}
