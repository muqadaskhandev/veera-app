import Fluent
import Foundation
import Vapor

enum AvatarService {
    private static let maxBytes = 5 * 1024 * 1024
    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    static func directory(on app: Application) -> String {
        app.directory.workingDirectory + "uploads/avatars/"
    }

    static func ensureDirectory(on app: Application) throws {
        let path = directory(on: app)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func publicURL(for avatarPath: String?, cacheVersion: String? = nil) -> String? {
        guard let avatarPath, !avatarPath.isEmpty else { return nil }
        guard let cacheVersion, !cacheVersion.isEmpty else {
            return "/api/profile/avatars/\(avatarPath)"
        }
        return "/api/profile/avatars/\(avatarPath)?v=\(cacheVersion)"
    }

    static func save(
        file: File,
        for profile: Profile,
        on app: Application
    ) async throws -> String {
        try ensureDirectory(on: app)

        let data = Data(file.data.readableBytesView)
        guard !data.isEmpty else {
            throw Abort(.badRequest, reason: "Avatar file is empty")
        }
        guard data.count <= maxBytes else {
            throw Abort(.badRequest, reason: "Avatar must be 5 MB or smaller")
        }

        let ext = normalizedExtension(for: file)
        guard allowedExtensions.contains(ext) else {
            throw Abort(.badRequest, reason: "Avatar must be JPEG, PNG, or WebP")
        }

        let userID = profile.$user.id
        let filename = "\(userID.uuidString).\(ext == "jpeg" ? "jpg" : ext)"
        let path = directory(on: app) + filename

        if let oldPath = profile.avatarPath {
            let oldFile = directory(on: app) + oldPath
            try? FileManager.default.removeItem(atPath: oldFile)
        }

        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        profile.avatarPath = filename
        return filename
    }

    static func filePath(for filename: String, on app: Application) throws -> String {
        guard !filename.contains("/"), !filename.contains("..") else {
            throw Abort(.badRequest, reason: "Invalid avatar filename")
        }
        let path = directory(on: app) + filename
        guard FileManager.default.fileExists(atPath: path) else {
            throw Abort(.notFound)
        }
        return path
    }

    private static func normalizedExtension(for file: File) -> String {
        if let ext = file.extension?.lowercased(), !ext.isEmpty {
            return ext
        }
        let name = file.filename.lowercased()
        if let dot = name.lastIndex(of: ".") {
            return String(name[name.index(after: dot)...])
        }
        return "jpg"
    }
}
