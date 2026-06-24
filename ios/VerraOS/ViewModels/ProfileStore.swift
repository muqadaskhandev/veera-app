//
//  ProfileStore.swift
//  VerraOS
//

import SwiftUI

/// Owns per-client profile state that persists for the session: which modules
/// are visible, logged weight entries, and the financial session ledger. Demo
/// data is seeded lazily the first time a client's profile is opened.
@Observable
final class ProfileStore {
    private var visibleModules: [UUID: Set<ProfileModule>] = [:]
    private var weightStore: [UUID: [WeightEntry]] = [:]
    private var weightTargetStore: [UUID: WeightTargets] = [:]
    private var ledgerStore: [UUID: [LedgerEntry]] = [:]
    private var workoutStore: [String: [WorkoutDay]] = [:]
    private var macroStore: [UUID: MacroTargets] = [:]
    private var notesStore: [UUID: [NutritionNote]] = [:]
    private var supplementStore: [UUID: [Supplement]] = [:]
    private var photoStore: [UUID: [ProgressPhoto]] = [:]
    /// How many workout weeks exist per client (always at least 1).
    private var workoutWeekCounts: [UUID: Int] = [:]

    // MARK: Module visibility

    func modules(for id: UUID) -> Set<ProfileModule> {
        if let existing = visibleModules[id] { return existing }
        let defaults = Set(ProfileModule.allCases.filter { $0.defaultOn })
        visibleModules[id] = defaults
        return defaults
    }

    func isVisible(_ module: ProfileModule, for id: UUID) -> Bool {
        modules(for: id).contains(module)
    }

    /// Ordered list of visible modules for the dashboard grid.
    func orderedVisibleModules(for id: UUID) -> [ProfileModule] {
        let set = modules(for: id)
        return ProfileModule.allCases.filter { set.contains($0) }
    }

    func toggle(_ module: ProfileModule, for id: UUID) {
        var set = modules(for: id)
        if set.contains(module) { set.remove(module) } else { set.insert(module) }
        visibleModules[id] = set
    }

    /// Replaces the full visible-module set for a client. Used to seed a richer
    /// default for the client demo experience.
    func setVisibleModules(_ modules: Set<ProfileModule>, for id: UUID) {
        visibleModules[id] = modules
    }

    // MARK: Weight

    /// Pure read: logged entries only — empty until the client logs a weight.
    func weights(for client: Client) -> [WeightEntry] {
        weightStore[client.id] ?? []
    }

    /// Logs today's weight, replacing any existing entry already logged today.
    func logWeight(_ kg: Double, for client: Client) {
        var entries = weights(for: client)
        let rounded = (kg * 10).rounded() / 10
        if let idx = entries.firstIndex(where: { $0.daysAgo == 0 }) {
            entries[idx].kg = rounded
        } else {
            entries.append(WeightEntry(daysAgo: 0, kg: rounded))
        }
        weightStore[client.id] = entries
    }

    func weightTargets(for client: Client) -> WeightTargets {
        weightTargetStore[client.id] ?? WeightTargets(start: nil, goal: nil)
    }

    func setWeightTargets(start: Double?, goal: Double?, for client: Client) {
        weightTargetStore[client.id] = WeightTargets(start: start, goal: goal)
    }

    // MARK: Workout (multi-week)

    private func workoutKey(_ id: UUID, _ week: Int) -> String { "\(id.uuidString)#\(week)" }

    /// Number of weeks that currently exist for a client (minimum 1).
    func workoutWeekCount(for id: UUID) -> Int {
        max(1, workoutWeekCounts[id] ?? 1)
    }

    /// Ensures a week index exists, extending the plan when needed. Returns the
    /// (clamped) index that is now guaranteed to be available.
    @discardableResult
    func ensureWorkoutWeek(_ id: UUID, week: Int) -> Int {
        let target = max(0, week)
        if target + 1 > workoutWeekCount(for: id) {
            workoutWeekCounts[id] = target + 1
        }
        return target
    }

    /// Pure read of a given week's plan. Every week starts completely blank
    /// until the trainer adds something themselves.
    func workoutWeek(for id: UUID, week: Int) -> [WorkoutDay] {
        workoutStore[workoutKey(id, week)] ?? ProfileDemo.emptyWeek()
    }

    /// Applies an in-place transform to a week's days and persists the result.
    func mutateWeek(_ id: UUID, week: Int, _ transform: (inout [WorkoutDay]) -> Void) {
        var days = workoutWeek(for: id, week: week)
        transform(&days)
        workoutStore[workoutKey(id, week)] = days
    }

    /// Copies the exercises of one day onto another day within the same week.
    func copyDay(fromIndex: Int, toIndex: Int, id: UUID, week: Int) {
        var days = workoutWeek(for: id, week: week)
        guard days.indices.contains(fromIndex), days.indices.contains(toIndex) else { return }
        let source = days[fromIndex]
        days[toIndex].focus = source.focus
        days[toIndex].exercises = source.exercises.map {
            WorkoutExercise(name: $0.name, sets: $0.sets, reps: $0.reps, kind: $0.kind)
        }
        workoutStore[workoutKey(id, week)] = days
    }

    /// Copies an entire week's plan onto another week index, creating the
    /// destination week if it does not exist yet.
    func copyWeek(from: Int, to: Int, id: UUID) {
        ensureWorkoutWeek(id, week: to)
        let source = workoutWeek(for: id, week: from)
        let copied = source.map { day in
            WorkoutDay(
                label: day.label,
                focus: day.focus,
                exercises: day.exercises.map {
                    WorkoutExercise(name: $0.name, sets: $0.sets, reps: $0.reps, kind: $0.kind)
                }
            )
        }
        workoutStore[workoutKey(id, to)] = copied
    }

    // MARK: Nutrition

    func macros(for id: UUID) -> MacroTargets {
        macroStore[id] ?? MacroTargets(protein: 0, carbs: 0, fats: 0)
    }

    func setMacros(_ macros: MacroTargets, for id: UUID) {
        macroStore[id] = macros
    }

    func notes(for id: UUID) -> [NutritionNote] {
        notesStore[id] ?? []
    }

    func addNote(_ text: String, for id: UUID) {
        var notes = notes(for: id)
        notes.insert(NutritionNote(text: text), at: 0)
        notesStore[id] = notes
    }

    func updateNote(_ note: NutritionNote, for id: UUID) {
        var notes = notes(for: id)
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        notesStore[id] = notes
    }

    func deleteNote(_ noteID: UUID, for id: UUID) {
        notesStore[id] = notes(for: id).filter { $0.id != noteID }
    }

    // MARK: Supplements

    func supplements(for id: UUID) -> [Supplement] {
        supplementStore[id] ?? []
    }

    func addSupplement(name: String, dosage: String, for id: UUID) {
        var supps = supplements(for: id)
        supps.append(Supplement(name: name, dosage: dosage))
        supplementStore[id] = supps
    }

    func updateSupplement(_ supplement: Supplement, for id: UUID) {
        var supps = supplements(for: id)
        guard let idx = supps.firstIndex(where: { $0.id == supplement.id }) else { return }
        supps[idx] = supplement
        supplementStore[id] = supps
    }

    func deleteSupplement(_ supplementID: UUID, for id: UUID) {
        supplementStore[id] = supplements(for: id).filter { $0.id != supplementID }
    }

    // MARK: Progress photos

    /// Logged photos, newest first.
    func photos(for id: UUID) -> [ProgressPhoto] {
        photoStore[id] ?? []
    }

    func addPhoto(for id: UUID) {
        let tints: [UInt] = [0x8C887E, 0x9AA17E, 0x7E94A1, 0xA17E8C, 0xA1957E, 0x7EA193]
        var photos = photos(for: id)
        let tint = tints[photos.count % tints.count]
        photos.insert(ProgressPhoto(date: Date(), tintHex: tint), at: 0)
        photoStore[id] = photos.sorted { $0.date > $1.date }
    }

    func deletePhoto(_ photoID: UUID, for id: UUID) {
        photoStore[id] = photos(for: id).filter { $0.id != photoID }
    }

    // MARK: Ledger

    func ledger(for client: Client) -> [LedgerEntry] {
        ledgerStore[client.id] ?? []
    }

    /// Read-only ledger accessor for the global Financials tab. Returns stored
    /// entries when present, otherwise the deterministic seed WITHOUT mutating
    /// state, so it is safe to call during view body evaluation.
    func ledgerSnapshot(for client: Client) -> [LedgerEntry] {
        ledgerStore[client.id] ?? []
    }

    func addLedgerEntry(_ entry: LedgerEntry, for id: UUID) {
        var entries = ledgerStore[id] ?? []
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
        ledgerStore[id] = entries
    }
}
