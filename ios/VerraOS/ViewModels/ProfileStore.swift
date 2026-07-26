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
    /// Called after visible-module toggles are saved to the API.
    var onVisibleModulesPersisted: ((UUID, [String]) -> Void)?

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
    private var workoutPersistTasks: [String: Task<Void, Never>] = [:]
    /// Weeks with local edits that haven't been confirmed by a successful save yet.
    /// Prevents an in-flight `refreshModule` from wiping notes / freestyle rows.
    private var dirtyWorkoutKeys: Set<String> = []
    private var nutritionPersistTasks: [UUID: Task<Void, Never>] = [:]
    private var weightPersistTasks: [UUID: Task<Void, Never>] = [:]
    private var moduleVisibilityPersistTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Module visibility

    private func defaultModules() -> Set<ProfileModule> {
        Set(ProfileModule.allCases.filter { $0.defaultOn })
    }

    private func resolvedModules(from raw: [String]?) -> Set<ProfileModule> {
        guard let raw, !raw.isEmpty else { return defaultModules() }
        let set = Set(raw.compactMap(ProfileModule.init(rawValue:)))
        return set.isEmpty ? defaultModules() : set
    }

    func applyVisibleModules(_ raw: [String]?, for id: UUID) {
        visibleModules[id] = resolvedModules(from: raw)
    }

    func applyVisibleModulesFromClients(_ clients: [Client]) {
        for client in clients {
            if visibleModules[client.id] == nil || client.visibleModules != nil {
                applyVisibleModules(client.visibleModules, for: client.id)
            }
        }
    }

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
        setVisible(module, !isVisible(module, for: id), for: id)
    }

    func setVisible(_ module: ProfileModule, _ visible: Bool, for id: UUID) {
        var set = modules(for: id)
        if visible {
            set.insert(module)
        } else {
            set.remove(module)
        }
        visibleModules[id] = set
        scheduleModuleVisibilityPersist(for: id)
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

    /// Logs a new weight entry. Always appends — even if a value was already
    /// logged today — so intra-day re-logs (e.g. morning vs. evening) each
    /// keep their own place in the history instead of overwriting one another.
    func logWeight(_ kg: Double, for client: Client) {
        var entries = weights(for: client)
        let rounded = (kg * 10).rounded() / 10
        entries.append(WeightEntry(daysAgo: 0, kg: rounded))
        weightStore[client.id] = entries
        scheduleWeightPersist(kg: rounded, for: client)
    }

    func weightTargets(for client: Client) -> WeightTargets {
        weightTargetStore[client.id] ?? WeightTargets(start: nil, goal: nil)
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
        let key = workoutKey(id, week)
        workoutStore[key] = days
        dirtyWorkoutKeys.insert(key)
        scheduleWorkoutPersist(clientID: id, week: week)
    }

    /// Copies the exercises of one day onto another day within the same week.
    func copyDay(fromIndex: Int, toIndex: Int, id: UUID, week: Int) {
        var days = workoutWeek(for: id, week: week)
        guard days.indices.contains(fromIndex), days.indices.contains(toIndex) else { return }
        let source = days[fromIndex]
        days[toIndex].focus = source.focus
        days[toIndex].notes = source.notes
        days[toIndex].exercises = source.exercises.map {
            WorkoutExercise(
                exerciseID: $0.exerciseID,
                name: $0.name,
                sets: $0.sets,
                reps: $0.reps,
                category: $0.category,
                kind: $0.kind,
                weightKg: $0.weightKg
            )
        }
        let key = workoutKey(id, week)
        workoutStore[key] = days
        dirtyWorkoutKeys.insert(key)
        scheduleWorkoutPersist(clientID: id, week: week)
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
                    WorkoutExercise(
                        exerciseID: $0.exerciseID,
                        name: $0.name,
                        sets: $0.sets,
                        reps: $0.reps,
                        category: $0.category,
                        kind: $0.kind,
                        weightKg: $0.weightKg
                    )
                },
                notes: day.notes
            )
        }
        let key = workoutKey(id, to)
        workoutStore[key] = copied
        dirtyWorkoutKeys.insert(key)
        scheduleWorkoutPersist(clientID: id, week: to)
    }

    // MARK: Nutrition

    func macros(for id: UUID) -> MacroTargets {
        macroStore[id] ?? MacroTargets(protein: 0, carbs: 0, fats: 0)
    }

    func setMacros(_ macros: MacroTargets, for id: UUID) {
        macroStore[id] = macros
        scheduleNutritionPersist(for: id)
    }

    func notes(for id: UUID) -> [NutritionNote] {
        notesStore[id] ?? []
    }

    func addNote(_ text: String, for id: UUID) {
        var notes = notes(for: id)
        notes.insert(NutritionNote(text: text), at: 0)
        notesStore[id] = notes
        scheduleNutritionPersist(for: id)
    }

    func updateNote(_ note: NutritionNote, for id: UUID) {
        var notes = notes(for: id)
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        notesStore[id] = notes
        scheduleNutritionPersist(for: id)
    }

    func deleteNote(_ noteID: UUID, for id: UUID) {
        notesStore[id] = notes(for: id).filter { $0.id != noteID }
        scheduleNutritionPersist(for: id)
    }

    // MARK: Supplements

    func supplements(for id: UUID) -> [Supplement] {
        supplementStore[id] ?? []
    }

    func addSupplement(name: String, dosage: String, for id: UUID) {
        var supps = supplements(for: id)
        supps.append(Supplement(name: name, dosage: dosage))
        supplementStore[id] = supps
        scheduleNutritionPersist(for: id)
    }

    func updateSupplement(_ supplement: Supplement, for id: UUID) {
        var supps = supplements(for: id)
        guard let idx = supps.firstIndex(where: { $0.id == supplement.id }) else { return }
        supps[idx] = supplement
        supplementStore[id] = supps
        scheduleNutritionPersist(for: id)
    }

    func deleteSupplement(_ supplementID: UUID, for id: UUID) {
        supplementStore[id] = supplements(for: id).filter { $0.id != supplementID }
        scheduleNutritionPersist(for: id)
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

    func removePhoto(_ photoID: UUID, for id: UUID) {
        photoStore[id] = photos(for: id).filter { $0.id != photoID }
    }

    func replaceWeightLogs(_ entries: [WeightEntry], for id: UUID) {
        weightStore[id] = entries
    }

    func replaceNutrition(
        macros: MacroTargets,
        notes: [NutritionNote],
        supplements: [Supplement],
        for id: UUID
    ) {
        macroStore[id] = macros
        notesStore[id] = notes
        supplementStore[id] = supplements
    }

    func replacePhotos(_ photos: [ProgressPhoto], for id: UUID) {
        photoStore[id] = photos.sorted { $0.date > $1.date }
    }

    func applyWeightTargets(from client: Client) {
        var targets = weightTargetStore[client.id] ?? WeightTargets(start: nil, goal: nil)
        targets.start = client.startWeightKg ?? client.weightKg.map(Double.init)
        targets.goal = client.goalWeightKg.map(Double.init)
        weightTargetStore[client.id] = targets
    }

    func setWeightTargets(start: Double?, goal: Double?, for client: Client) {
        weightTargetStore[client.id] = WeightTargets(start: start, goal: goal)
        scheduleWeightTargetPersist(start: start, goal: goal, for: client)
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

    func replaceLedger(_ entries: [LedgerEntry], for id: UUID) {
        ledgerStore[id] = entries.sorted { $0.date > $1.date }
    }

    func replaceWorkoutWeek(_ days: [WorkoutDay], week: Int, for id: UUID, weekCount: Int) {
        let key = workoutKey(id, week)
        // Never clobber a week the user just edited until the save succeeds.
        guard !dirtyWorkoutKeys.contains(key) else { return }
        workoutWeekCounts[id] = max(1, weekCount)
        workoutStore[key] = days
    }
}

// MARK: - Server sync

extension ProfileStore {
    @MainActor
    func refreshAllVisibleModules(for client: Client) async {
        let modules = orderedVisibleModules(for: client.id)
        for module in modules where module != .wearables {
            await refreshModule(module, for: client)
        }
        if modules.contains(.workout) {
            await refreshModule(.workout, for: client, week: 0)
        }
    }

    @MainActor
    func refreshModule(_ module: ProfileModule, for client: Client, week: Int = 0) async {
        guard let token = AuthStore.accessToken else { return }
        switch module {
        case .workout:
            let key = workoutKey(client.id, week)
            // Skip fetch-apply while local edits are still pending — otherwise
            // freestyle rows and session notes vanish before the debounce fires.
            if dirtyWorkoutKeys.contains(key) { return }
            if let response = try? await VerraAPI.fetchWorkoutWeek(
                clientID: client.id,
                week: week,
                accessToken: token
            ) {
                PlatformLoader.applyWorkoutWeek(response, clientID: client.id, week: week, to: self)
            }
        case .weight:
            applyWeightTargets(from: client)
            if let logs = try? await VerraAPI.fetchWeightLogs(clientID: client.id, accessToken: token) {
                PlatformLoader.applyWeightLogs(logs, for: client.id, to: self)
            }
        case .nutrition:
            if let dto = try? await VerraAPI.fetchNutrition(clientID: client.id, accessToken: token) {
                PlatformLoader.applyNutrition(dto, clientID: client.id, to: self)
            }
        case .photos:
            if let photos = try? await VerraAPI.fetchProgressPhotos(clientID: client.id, accessToken: token) {
                PlatformLoader.applyPhotos(photos, clientID: client.id, to: self)
            }
        case .financials:
            await refreshLedger(for: client.id)
        default:
            break
        }
    }

    @MainActor
    func uploadPhoto(data: Data, for clientID: UUID) async -> Bool {
        guard let token = AuthStore.accessToken else { return false }
        guard let dto = try? await VerraAPI.uploadProgressPhoto(
            clientID: clientID,
            imageData: data,
            accessToken: token
        ) else {
            return false
        }
        var photos = photos(for: clientID)
        photos.insert(ProgressPhoto(id: dto.id, date: dto.capturedAt, imageURL: dto.imageURL), at: 0)
        photoStore[clientID] = photos.sorted { $0.date > $1.date }
        return true
    }

    @MainActor
    func deletePhoto(_ photoID: UUID, for clientID: UUID) async -> Bool {
        guard let token = AuthStore.accessToken else { return false }
        do {
            try await VerraAPI.deleteProgressPhoto(clientID: clientID, photoID: photoID, accessToken: token)
            removePhoto(photoID, for: clientID)
            return true
        } catch {
            return false
        }
    }

    func scheduleWorkoutPersist(clientID: UUID, week: Int) {
        let key = workoutKey(clientID, week)
        workoutPersistTasks[key]?.cancel()
        workoutPersistTasks[key] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await persistWorkoutWeek(clientID: clientID, week: week)
        }
    }

    /// Cancels the debounce and writes the week to the server immediately
    /// (used by Save Log / Save Freestyle so data doesn't race with refresh).
    @MainActor
    func flushWorkoutPersist(clientID: UUID, week: Int) async {
        let key = workoutKey(clientID, week)
        workoutPersistTasks[key]?.cancel()
        workoutPersistTasks[key] = nil
        dirtyWorkoutKeys.insert(key)
        await persistWorkoutWeek(clientID: clientID, week: week)
    }

    @MainActor
    private func persistWorkoutWeek(clientID: UUID, week: Int) async {
        guard let token = AuthStore.accessToken else { return }
        let key = workoutKey(clientID, week)
        let days = workoutWeek(for: clientID, week: week)
        let body = PlatformLoader.saveWorkoutBody(
            from: days,
            weekCount: workoutWeekCount(for: clientID)
        )
        do {
            let response = try await VerraAPI.saveWorkoutWeek(
                clientID: clientID,
                week: week,
                body: body,
                accessToken: token
            )
            dirtyWorkoutKeys.remove(key)
            // Only apply the server echo if nothing newer was edited during the save.
            if !dirtyWorkoutKeys.contains(key) {
                PlatformLoader.applyWorkoutWeek(response, clientID: clientID, week: week, to: self)
            }
        } catch {
            // Keep dirty so the next refresh doesn't wipe the local edits; retry
            // will happen on the next mutation/flush.
        }
    }

    func scheduleNutritionPersist(for clientID: UUID) {
        nutritionPersistTasks[clientID]?.cancel()
        nutritionPersistTasks[clientID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await persistNutrition(for: clientID)
        }
    }

    func scheduleWeightPersist(kg: Double, for client: Client) {
        weightPersistTasks[client.id]?.cancel()
        weightPersistTasks[client.id] = Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            _ = try? await VerraAPI.logWeight(clientID: client.id, kg: kg, accessToken: token)
            if let logs = try? await VerraAPI.fetchWeightLogs(clientID: client.id, accessToken: token) {
                PlatformLoader.applyWeightLogs(logs, for: client.id, to: self)
            }
        }
    }

    func scheduleWeightTargetPersist(start: Double?, goal: Double?, for client: Client) {
        weightPersistTasks[client.id]?.cancel()
        weightPersistTasks[client.id] = Task { @MainActor in
            guard let token = AuthStore.accessToken else { return }
            let goalKg = goal.map { Int($0.rounded()) }
            _ = try? await VerraAPI.updateClient(
                id: client.id,
                goalWeightKg: goalKg,
                startWeightKg: start,
                accessToken: token
            )
        }
    }

    @MainActor
    func refreshLedger(for clientID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        if let events = try? await VerraAPI.fetchClientLedger(clientID: clientID, accessToken: token) {
            let entries = events.map { event -> LedgerEntry in
                let kind: LedgerKind
                switch event.kind {
                case "income": kind = .packageAdded
                case "usage": kind = .sessionUsed
                default: kind = .adjustment
                }
                return LedgerEntry(
                    id: event.id,
                    date: event.occurredAt,
                    title: event.title,
                    delta: event.sessionDelta,
                    amount: event.amount,
                    kind: kind
                )
            }
            replaceLedger(entries, for: clientID)
        }
    }

    func scheduleModuleVisibilityPersist(for id: UUID) {
        moduleVisibilityPersistTasks[id]?.cancel()
        moduleVisibilityPersistTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await persistModuleVisibility(for: id)
        }
    }

    @MainActor
    private func persistModuleVisibility(for id: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        let payload = modules(for: id).map(\.rawValue).sorted()
        if let dto = try? await VerraAPI.updateClient(
            id: id,
            visibleModules: payload,
            accessToken: token
        ) {
            onVisibleModulesPersisted?(id, dto.visibleModules ?? payload)
        }
    }

    @MainActor
    private func persistNutrition(for clientID: UUID) async {
        guard let token = AuthStore.accessToken else { return }
        let body = VerraAPI.UpdateNutritionBody(
            proteinG: macros(for: clientID).protein,
            carbsG: macros(for: clientID).carbs,
            fatsG: macros(for: clientID).fats,
            notes: notes(for: clientID).map {
                VerraAPI.NutritionNoteInput(id: $0.id, text: $0.text)
            },
            supplements: supplements(for: clientID).map {
                VerraAPI.SupplementInput(id: $0.id, name: $0.name, dosage: $0.dosage)
            }
        )
        if let dto = try? await VerraAPI.updateNutrition(
            clientID: clientID,
            body: body,
            accessToken: token
        ) {
            PlatformLoader.applyNutrition(dto, clientID: clientID, to: self)
        }
    }
}
