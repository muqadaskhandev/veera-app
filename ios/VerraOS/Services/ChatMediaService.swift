import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ChatMediaService {
    struct PreparedUpload {
        let data: Data
        let filename: String
        let mimeType: String
        let kind: MessageKind
    }

    static func preparePhoto(from data: Data, maxDimension: CGFloat = 1600) -> PreparedUpload? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = image.resizedForChat(maxDimension: maxDimension)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return PreparedUpload(
            data: jpeg,
            filename: "photo-\(UUID().uuidString).jpg",
            mimeType: "image/jpeg",
            kind: .photo
        )
    }

    static func prepareVideo(from url: URL) -> PreparedUpload? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let ext = url.pathExtension.lowercased()
        let normalizedExt = ext.isEmpty ? "mov" : ext
        let mimeType: String
        switch normalizedExt {
        case "mp4": mimeType = "video/mp4"
        case "mov": mimeType = "video/quicktime"
        default: mimeType = "video/mp4"
        }
        return PreparedUpload(
            data: data,
            filename: "video-\(UUID().uuidString).\(normalizedExt)",
            mimeType: mimeType,
            kind: .video
        )
    }

    static func prepareVoice(from url: URL, duration: Int) -> PreparedUpload? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return PreparedUpload(
            data: data,
            filename: "voice-\(UUID().uuidString).m4a",
            mimeType: "audio/mp4",
            kind: .voice(seconds: max(1, duration))
        )
    }
}

private extension UIImage {
    func resizedForChat(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

struct ChatMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ChatMovie(url: destination)
        }
    }
}
