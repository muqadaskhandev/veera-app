import Fluent

struct CreateProfile: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Profile.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("display_name", .string, .required)
            .field("title", .string, .required)
            .field("bio", .string, .required)
            .field("specialties_json", .string, .required)
            .field("avatar_path", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Profile.schema).delete()
    }
}

struct MigrateExistingProfiles: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let users = try await User.query(on: database).all()
        for user in users {
            guard let userID = user.id else { continue }
            let exists = try await Profile.query(on: database)
                .filter(\.$user.$id == userID)
                .first() != nil
            guard !exists else { continue }

            var displayName = user.displayName
            var title = ""
            var bio = ""
            var specialtiesJSON = "[]"

            if let trainer = try await Trainer.query(on: database)
                .filter(\.$user.$id == userID)
                .first() {
                displayName = trainer.name
                title = trainer.title
                bio = trainer.bio
                specialtiesJSON = trainer.specialtiesJSON ?? "[]"
            } else if let client = try await Client.query(on: database)
                .filter(\.$user.$id == userID)
                .first() {
                displayName = client.name
            }

            let profile = Profile(
                userID: userID,
                displayName: displayName,
                title: title,
                bio: bio,
                specialtiesJSON: specialtiesJSON,
                avatarPath: user.avatarPath
            )
            try await profile.save(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        try await Profile.query(on: database).delete()
    }
}
