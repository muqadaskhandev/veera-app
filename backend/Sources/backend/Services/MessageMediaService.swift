import Fluent
import Vapor

enum MessageMediaService {
    private static let maxBytes = 25 * 1024 * 1024
    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "mp4", "mov", "m4a", "mp3", "wav"]

    static func directory(on app: Application) -> String {
        app.directory.workingDirectory + "uploads/chat/"
    }

    static func ensureDirectory(on app: Application) throws {
        try FileManager.default.createDirectory(
            atPath: directory(on: app),
            withIntermediateDirectories: true
        )
    }

    static func save(file: File, on app: Application) async throws -> String {
        try ensureDirectory(on: app)

        let data = Data(file.data.readableBytesView)
        guard !data.isEmpty else {
            throw Abort(.badRequest, reason: "Attachment is empty")
        }
        guard data.count <= maxBytes else {
            throw Abort(.badRequest, reason: "Attachment must be 25 MB or smaller")
        }

        let ext = (file.extension ?? "bin").lowercased()
        guard allowedExtensions.contains(ext) else {
            throw Abort(.badRequest, reason: "Unsupported attachment type")
        }

        let filename = "\(UUID().uuidString).\(ext)"
        let path = directory(on: app) + filename
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return "/api/conversations/attachments/\(filename)"
    }

    static func resolvePath(filename: String, on app: Application) -> String? {
        guard !filename.contains("/"), !filename.contains("..") else { return nil }
        let path = directory(on: app) + filename
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}
