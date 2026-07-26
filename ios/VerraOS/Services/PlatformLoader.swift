import Foundation

enum SessionLoader {
    static func session(from dto: SessionDTO) -> Session {
        let timeZoneIdentifier = dto.timeZoneIdentifier ?? TimeZone.current.identifier
        let tag = SessionTag(rawValue: dto.accent) ?? accent(from: dto.focus)

        return Session.make(
            id: dto.id,
            clientID: dto.clientID,
            clientName: dto.clientName,
            initials: dto.initials,
            dayOfMonth: 1,
            startMinutes: 0,
            scheduledAt: dto.scheduledAt,
            timeZoneIdentifier: timeZoneIdentifier,
            durationMinutes: dto.durationMinutes,
            accent: tag,
            location: dto.location,
            notes: dto.notes,
            isCompleted: dto.isCompleted,
            isSkipped: dto.isSkipped
        )
    }

    static func createBody(from session: Session, clientID: UUID?) -> VerraAPI.CreateSessionBody {
        VerraAPI.CreateSessionBody(
            id: session.id,
            clientID: clientID ?? session.clientID,
            clientName: session.clientName,
            focus: session.focus,
            location: session.location,
            accent: session.accent.rawValue,
            initials: session.initials,
            scheduledAt: session.scheduledAt,
            timeZoneIdentifier: session.timeZoneIdentifier,
            durationMinutes: session.durationMinutes,
            notes: session.notes
        )
    }

    static func updateBody(from session: Session, clientID: UUID?, isCancelled: Bool = false) -> VerraAPI.UpdateSessionBody {
        VerraAPI.UpdateSessionBody(
            clientID: clientID,
            clientName: session.clientName,
            focus: session.focus,
            location: session.location,
            accent: session.accent.rawValue,
            initials: session.initials,
            scheduledAt: session.scheduledAt,
            timeZoneIdentifier: session.timeZoneIdentifier,
            durationMinutes: session.durationMinutes,
            notes: session.notes,
            isCompleted: session.isCompleted,
            isSkipped: session.isSkipped,
            isCancelled: isCancelled
        )
    }

    private static func accent(from focus: String) -> SessionTag {
        SessionTag.allCases.first(where: { $0.label.caseInsensitiveCompare(focus) == .orderedSame }) ?? .training
    }
}

private extension SessionTag {
    var rawValue: String {
        switch self {
        case .training: return "training"
        case .strength: return "strength"
        case .mobility: return "mobility"
        case .consult: return "consult"
        case .recovery: return "recovery"
        case .personal: return "personal"
        }
    }

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "training": self = .training
        case "strength": self = .strength
        case "mobility": self = .mobility
        case "consult": self = .consult
        case "recovery": self = .recovery
        case "personal": self = .personal
        default: return nil
        }
    }
}

enum PlatformLoader {
    @MainActor
    static func applyFinancialEvents(_ events: [VerraAPI.FinancialEventDTO], clients: [Client], to profile: ProfileStore) {
        var grouped: [UUID: [LedgerEntry]] = [:]
        for event in events {
            guard let clientID = event.clientID else { continue }
            let kind: LedgerKind
            switch event.kind {
            case "income": kind = .packageAdded
            case "usage": kind = .sessionUsed
            default: kind = .adjustment
            }
            let entry = LedgerEntry(
                id: event.id,
                date: event.occurredAt,
                title: event.title,
                delta: event.sessionDelta,
                amount: event.amount,
                kind: kind
            )
            grouped[clientID, default: []].append(entry)
        }
        for client in clients {
            profile.replaceLedger(grouped[client.id] ?? [], for: client.id)
        }
    }

    /// Maps API financial events into ledger rows for the Financials tab.
    static func finEvents(from dtos: [VerraAPI.FinancialEventDTO]) -> [FinEvent] {
        dtos.compactMap { dto in
            let clientName = dto.clientName ?? "Client"
            switch dto.kind {
            case "income":
                let detail = dto.sessionDelta > 0 ? "bought \(dto.sessionDelta)-Pack" : dto.detail
                return FinEvent(
                    id: dto.id,
                    date: dto.occurredAt,
                    clientName: clientName,
                    detail: detail,
                    amount: dto.amount,
                    kind: .income
                )
            case "usage":
                return FinEvent(
                    id: dto.id,
                    date: dto.occurredAt,
                    clientName: clientName,
                    detail: "Session Used",
                    amount: nil,
                    kind: .usage
                )
            default:
                return nil
            }
        }
    }

    @MainActor
    static func applyWorkoutWeek(_ response: VerraAPI.WorkoutWeekResponse, clientID: UUID, week: Int, to profile: ProfileStore) {
        profile.replaceWorkoutWeek(workoutDays(from: response.days), week: week, for: clientID, weekCount: response.weekCount)
    }

    static func workoutDays(from dtos: [VerraAPI.WorkoutDayDTO]) -> [WorkoutDay] {
        dtos.map { day in
            WorkoutDay(
                id: day.id ?? UUID(),
                label: day.label,
                focus: day.focus,
                exercises: day.exercises.map { exercise in
                    WorkoutExercise(
                        id: exercise.id ?? UUID(),
                        exerciseID: exercise.exerciseID,
                        name: exercise.name,
                        sets: exercise.sets,
                        reps: exercise.reps,
                        category: exercise.category,
                        kind: WorkoutItemKind(rawValue: exercise.kind) ?? .exercise,
                        weightKg: exercise.weightKg
                    )
                },
                notes: day.notes
            )
        }
    }

    static func saveWorkoutBody(from days: [WorkoutDay], weekCount: Int?) -> VerraAPI.SaveWorkoutWeekBody {
        VerraAPI.SaveWorkoutWeekBody(
            days: days.map { day in
                VerraAPI.WorkoutDayDTO(
                    id: day.id,
                    label: day.label,
                    focus: day.focus,
                    exercises: day.exercises.map { exercise in
                        VerraAPI.WorkoutExerciseDTO(
                            id: exercise.id,
                            exerciseID: exercise.exerciseID,
                            name: exercise.name,
                            category: exercise.category,
                            sets: exercise.sets,
                            reps: exercise.reps,
                            kind: exercise.kind.rawValue,
                            weightKg: exercise.weightKg
                        )
                    },
                    notes: day.notes
                )
            },
            weekCount: weekCount
        )
    }

    @MainActor
    static func applyWeightLogs(
        _ logs: [VerraAPI.WeightLogDTO],
        for clientID: UUID,
        preservingLocalIDs: Set<UUID> = [],
        to profile: ProfileStore
    ) {
        let server = logs.map { log in
            WeightEntry(id: log.id, recordedAt: log.recordedAt, kg: log.kg)
        }
        let serverIDs = Set(server.map(\.id))
        let pendingLocals = profile.weightEntries(for: clientID).filter {
            preservingLocalIDs.contains($0.id) && !serverIDs.contains($0.id)
        }
        let entries = (server + pendingLocals).sorted { $0.recordedAt < $1.recordedAt }
        profile.replaceWeightLogs(entries, for: clientID)
    }

    @MainActor
    static func applyNutrition(_ dto: VerraAPI.NutritionProfileDTO, clientID: UUID, to profile: ProfileStore) {
        profile.replaceNutrition(
            macros: MacroTargets(protein: dto.proteinG, carbs: dto.carbsG, fats: dto.fatsG),
            notes: dto.notes.map { NutritionNote(id: $0.id, text: $0.text) },
            supplements: dto.supplements.map { Supplement(id: $0.id, name: $0.name, dosage: $0.dosage) },
            for: clientID
        )
    }

    @MainActor
    static func applyPhotos(_ photos: [VerraAPI.ProgressPhotoDTO], clientID: UUID, to profile: ProfileStore) {
        let mapped = photos.map { photo in
            ProgressPhoto(id: photo.id, date: photo.capturedAt, imageURL: photo.imageURL)
        }
        profile.replacePhotos(mapped, for: clientID)
    }
}
