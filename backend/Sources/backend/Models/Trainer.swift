import Fluent
import Vapor

final class Trainer: Model, @unchecked Sendable {
    static let schema = "trainers"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "title")
    var title: String

    @Field(key: "bio")
    var bio: String

    @OptionalField(key: "specialties_json")
    var specialtiesJSON: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalParent(key: "user_id")
    var user: User?

    @Children(for: \.$trainer)
    var clients: [Client]

    init() {}

    init(id: UUID? = nil, name: String, title: String, bio: String) {
        self.id = id
        self.name = name
        self.title = title
        self.bio = bio
    }
}

extension Trainer: Content {}

struct TrainerDTO: Content {
    let id: UUID
    let name: String
    let title: String
    let bio: String
    let specialties: [String]
    let avatarURL: String?

    init(from trainer: Trainer, avatarURL: String? = nil) throws {
        guard let id = trainer.id else {
            throw Abort(.internalServerError, reason: "Trainer missing id")
        }
        self.id = id
        self.name = trainer.name
        self.title = trainer.title
        self.bio = trainer.bio
        self.specialties = TrainerSpecialties.decode(trainer.specialtiesJSON)
        self.avatarURL = avatarURL
    }

    init(
        id: UUID,
        name: String,
        title: String,
        bio: String,
        specialties: [String],
        avatarURL: String?
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.bio = bio
        self.specialties = specialties
        self.avatarURL = avatarURL
    }
}

enum TrainerSpecialties {
    static func decode(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    static func encode(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
