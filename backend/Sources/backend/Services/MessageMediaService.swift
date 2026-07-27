import Fluent
import Vapor

enum MessageMediaService {
    private static let maxBytes = 25 * 1024 * 1024
    private static let folder = "chat"
    private static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif",
        "mp4", "mov",
        "m4a", "mp3", "wav",
        "pdf", "doc", "docx", "txt", "csv", "rtf", "pages", "numbers", "zip"
    ]

    /// Legacy directory used before StorageService integration.
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
        let contentType = mimeType(for: ext)
        // Prefer S3 (durable) with local disk fallback — same path as avatars / photos.
        _ = try await StorageService.save(
            data: data,
            filename: filename,
            folder: folder,
            contentType: contentType,
            on: app
        )

        // Always expose an authenticated API path. Directory buckets (S3 Express)
        // are private — the serve endpoint proxies from S3 when needed.
        return "/api/conversations/attachments/\(filename)"
    }

    /// Resolves a filename to a local file path (new StorageService dir or legacy chat dir).
    static func resolvePath(filename: String, on app: Application) -> String? {
        guard !filename.contains("/"), !filename.contains("..") else { return nil }
        if let path = StorageService.localFilePath(storedPath: filename, folder: folder, on: app) {
            return path
        }
        let legacy = directory(on: app) + filename
        return FileManager.default.fileExists(atPath: legacy) ? legacy : nil
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
