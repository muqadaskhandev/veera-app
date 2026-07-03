import Fluent
import Foundation
import Vapor

enum ExerciseCategory {
    static let all: [String] = ["strength", "conditioning", "accessory", "mobility", "cardio"]
}

enum ExerciseService {
    static func categories() -> [String] {
        ExerciseCategory.all
    }

    static func list(
        query: String?,
        category: String?,
        limit: Int = 30,
        on database: any Database,
        baseURL: String?
    ) async throws -> [ExerciseDTO] {
        var builder = Exercise.query(on: database).sort(\.$name, .ascending)
        if let category, !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            builder = builder.filter(\.$category == category.lowercased())
        }

        let all = try await builder.all()
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let filtered: [Exercise]
        if trimmed.isEmpty {
            filtered = Array(all.prefix(max(1, min(limit, 100))))
        } else {
            filtered = all
                .filter { $0.name.lowercased().contains(trimmed) }
                .prefix(max(1, min(limit, 100)))
                .map { $0 }
        }
        return try filtered.map { try ExerciseDTO(from: $0, baseURL: baseURL) }
    }

    static func show(id: UUID, on database: any Database, baseURL: String?) async throws -> ExerciseDTO {
        guard let exercise = try await Exercise.find(id, on: database) else {
            throw Abort(.notFound, reason: "Exercise not found")
        }
        return try ExerciseDTO(from: exercise, baseURL: baseURL)
    }

    static func create(payload: CreateExerciseRequest, on database: any Database, baseURL: String?) async throws -> ExerciseDTO {
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Abort(.badRequest, reason: "Exercise name is required") }

        let category = payload.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ExerciseCategory.all.contains(category) else {
            throw Abort(.badRequest, reason: "Invalid category")
        }

        if try await Exercise.query(on: database).filter(\.$name == name).first() != nil {
            throw Abort(.conflict, reason: "An exercise with this name already exists")
        }

        let exercise = Exercise(
            name: name,
            category: category,
            description: payload.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await exercise.save(on: database)
        return try ExerciseDTO(from: exercise, baseURL: baseURL)
    }

    static func update(
        id: UUID,
        payload: UpdateExerciseRequest,
        on database: any Database,
        baseURL: String?
    ) async throws -> ExerciseDTO {
        guard let exercise = try await Exercise.find(id, on: database) else {
            throw Abort(.notFound, reason: "Exercise not found")
        }

        if let name = payload.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw Abort(.badRequest, reason: "Exercise name cannot be empty") }
            exercise.name = trimmed
        }
        if let category = payload.category {
            let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ExerciseCategory.all.contains(normalized) else {
                throw Abort(.badRequest, reason: "Invalid category")
            }
            exercise.category = normalized
        }
        if let description = payload.description {
            exercise.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try await exercise.save(on: database)
        return try ExerciseDTO(from: exercise, baseURL: baseURL)
    }

    static func uploadImage(
        id: UUID,
        file: File,
        on database: any Database,
        app: Application,
        baseURL: String?
    ) async throws -> ExerciseDTO {
        guard let exercise = try await Exercise.find(id, on: database) else {
            throw Abort(.notFound, reason: "Exercise not found")
        }

        let data = Data(file.data.readableBytesView)
        guard !data.isEmpty else { throw Abort(.badRequest, reason: "Image is empty") }

        let ext = (file.extension ?? "jpg").lowercased()
        let filename = "\(UUID().uuidString).\(ext)"
        let stored = try await StorageService.save(
            data: data,
            filename: filename,
            folder: "exercises",
            contentType: file.contentType?.serialize() ?? "image/jpeg",
            on: app
        )

        if let previous = exercise.imagePath {
            try? await StorageService.delete(storedPath: previous, on: app)
        }

        exercise.imagePath = stored
        try await exercise.save(on: database)
        return try ExerciseDTO(from: exercise, baseURL: baseURL)
    }

    static func uploadVideo(
        id: UUID,
        file: File,
        on database: any Database,
        app: Application,
        baseURL: String?
    ) async throws -> ExerciseDTO {
        guard let exercise = try await Exercise.find(id, on: database) else {
            throw Abort(.notFound, reason: "Exercise not found")
        }

        let data = Data(file.data.readableBytesView)
        guard !data.isEmpty else { throw Abort(.badRequest, reason: "Video is empty") }

        let ext = (file.extension ?? "mp4").lowercased()
        let filename = "\(UUID().uuidString).\(ext)"
        let stored = try await StorageService.save(
            data: data,
            filename: filename,
            folder: "exercises",
            contentType: file.contentType?.serialize() ?? "video/mp4",
            on: app
        )

        if let previous = exercise.videoPath {
            try? await StorageService.delete(storedPath: previous, on: app)
        }

        exercise.videoPath = stored
        try await exercise.save(on: database)
        return try ExerciseDTO(from: exercise, baseURL: baseURL)
    }
}

struct CreateExerciseRequest: Content {
    var name: String
    var category: String
    var description: String?
}

struct UpdateExerciseRequest: Content {
    var name: String?
    var category: String?
    var description: String?
}
