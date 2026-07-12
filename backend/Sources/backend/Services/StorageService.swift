import Crypto
import Foundation
import NIOCore
import Vapor

enum StorageService {
    static func isS3Configured() -> Bool {
        guard let bucket = Environment.get("S3_BUCKET"), !bucket.isEmpty else { return false }
        return Environment.get("AWS_ACCESS_KEY_ID") != nil
    }

    static func publicURL(for key: String, baseURL: String?) -> String? {
        guard !key.isEmpty else { return nil }
        if key.hasPrefix("http") { return key }
        if key.hasPrefix("/api/") { return key }
        if isS3Configured(), let bucket = Environment.get("S3_BUCKET"), let region = Environment.get("AWS_REGION") {
            return "https://\(bucket).s3.\(region).amazonaws.com/\(key)"
        }
        if let baseURL, let url = URL(string: baseURL) {
            return url.appending(path: key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
        }
        return key
    }

    @discardableResult
    static func save(
        data: Data,
        filename: String,
        folder: String,
        contentType: String,
        on app: Application
    ) async throws -> String {
        if isS3Configured() {
            let key = "\(folder)/\(filename)"
            try await uploadToS3(data: data, key: key, contentType: contentType, on: app)
            return key
        }
        return try saveLocally(data: data, filename: filename, folder: folder, on: app)
    }

    static func localFilePath(storedPath: String, folder: String, on app: Application) -> String? {
        let filename = storedPath.split(separator: "/").last.map(String.init) ?? storedPath
        let path = localDirectory(folder: folder, on: app) + filename
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static func localDirectory(folder: String, on app: Application) -> String {
        app.directory.workingDirectory + "uploads/\(folder)/"
    }

    static func delete(storedPath: String, on app: Application) async throws {
        guard !storedPath.isEmpty else { return }
        if storedPath.hasPrefix("/api/storage/") {
            let suffix = storedPath.dropFirst("/api/storage/".count)
            let parts = suffix.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return }
            let folder = String(parts[0])
            let filename = String(parts[1])
            let path = localDirectory(folder: folder, on: app) + filename
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        if isS3Configured() {
            try await deleteFromS3(key: storedPath, on: app)
        }
    }

    private static func saveLocally(data: Data, filename: String, folder: String, on app: Application) throws -> String {
        let dir = localDirectory(folder: folder, on: app)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + filename
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return "/api/storage/\(folder)/\(filename)"
    }

    private static func uploadToS3(data: Data, key: String, contentType: String, on app: Application) async throws {
        guard let bucket = Environment.get("S3_BUCKET"),
              let accessKey = Environment.get("AWS_ACCESS_KEY_ID"),
              let secretKey = Environment.get("AWS_SECRET_ACCESS_KEY"),
              let url = URL(string: "https://\(bucket).s3.\(Environment.get("AWS_REGION") ?? "us-east-1").amazonaws.com/\(key)") else {
            throw Abort(.internalServerError, reason: "S3 is not configured")
        }

        let region = Environment.get("AWS_REGION") ?? "us-east-1"
        let signed = AWSSigV4Signer.authorizationHeader(
            method: "PUT",
            url: url,
            headers: ["content-type": contentType],
            body: data,
            service: "s3",
            region: region,
            credentials: .init(
                accessKeyID: accessKey,
                secretAccessKey: secretKey,
                sessionToken: Environment.get("AWS_SESSION_TOKEN").flatMap { $0.isEmpty ? nil : $0 }
            )
        )

        let response = try await app.client.put(URI(string: url.absoluteString)) { request in
            request.headers.replaceOrAdd(name: .authorization, value: signed.authorization)
            request.headers.replaceOrAdd(name: .contentType, value: contentType)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-date"), value: signed.amzDate)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-content-sha256"), value: signed.payloadHash)
            request.body = ByteBuffer(bytes: [UInt8](data))
        }

        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "S3 upload failed (\(response.status.code))")
        }
    }

    private static func deleteFromS3(key: String, on app: Application) async throws {
        guard let bucket = Environment.get("S3_BUCKET"),
              let accessKey = Environment.get("AWS_ACCESS_KEY_ID"),
              let secretKey = Environment.get("AWS_SECRET_ACCESS_KEY"),
              let url = URL(string: "https://\(bucket).s3.\(Environment.get("AWS_REGION") ?? "us-east-1").amazonaws.com/\(key)") else {
            return
        }

        let region = Environment.get("AWS_REGION") ?? "us-east-1"
        let signed = AWSSigV4Signer.authorizationHeader(
            method: "DELETE",
            url: url,
            headers: [:],
            body: Data(),
            service: "s3",
            region: region,
            credentials: .init(
                accessKeyID: accessKey,
                secretAccessKey: secretKey,
                sessionToken: Environment.get("AWS_SESSION_TOKEN").flatMap { $0.isEmpty ? nil : $0 }
            )
        )

        let response = try await app.client.delete(URI(string: url.absoluteString)) { request in
            request.headers.replaceOrAdd(name: .authorization, value: signed.authorization)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-date"), value: signed.amzDate)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-content-sha256"), value: signed.payloadHash)
        }

        guard (200..<300).contains(response.status.code) || response.status.code == 404 else {
            throw Abort(.badGateway, reason: "S3 delete failed (\(response.status.code))")
        }
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
