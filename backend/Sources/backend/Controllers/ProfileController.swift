import Fluent
import Vapor

struct ProfileController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let profile = routes.grouped("api", "profile")
        profile.get("avatars", ":filename", use: avatar)

        let protected = profile.grouped(JWTAuthMiddleware())
        protected.get("me", use: me)
        protected.patch("me", use: update)
        protected.on(.POST, "avatar", body: .collect(maxSize: "6mb"), use: uploadAvatar)
    }

    @Sendable
    func me(req: Request) async throws -> ProfileResponse {
        let user = try req.auth.require(User.self)
        return try await ProfileService.load(for: user, on: req.db)
    }

    @Sendable
    func update(req: Request) async throws -> ProfileResponse {
        let user = try req.auth.require(User.self)
        let payload = try req.content.decode(UpdateProfileRequest.self)
        return try await ProfileService.update(for: user, payload: payload, on: req.db)
    }

    @Sendable
    func uploadAvatar(req: Request) async throws -> ProfileResponse {
        let user = try req.auth.require(User.self)
        struct AvatarUpload: Content {
            var avatar: File
        }
        let upload = try req.content.decode(AvatarUpload.self)
        let profile = try await ProfileService.getOrCreate(for: user, on: req.db)
        _ = try await AvatarService.save(file: upload.avatar, for: profile, on: req.application)
        try await profile.save(on: req.db)

        user.avatarPath = profile.avatarPath
        try await user.save(on: req.db)

        return try await ProfileService.load(for: user, on: req.db)
    }

    @Sendable
    func avatar(req: Request) async throws -> Response {
        guard let filename = req.parameters.get("filename") else {
            throw Abort(.badRequest)
        }
        let path = try AvatarService.filePath(for: filename, on: req.application)
        return try await req.fileio.asyncStreamFile(at: path)
    }
}
