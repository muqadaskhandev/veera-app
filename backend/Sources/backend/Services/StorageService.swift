import Crypto
import Foundation
import NIOCore
import Vapor

enum StorageService {
    static func isS3Configured() -> Bool {
        guard let bucket = Environment.get("S3_BUCKET")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bucket.isEmpty else { return false }
        guard let accessKey = Environment.get("AWS_ACCESS_KEY_ID")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessKey.isEmpty else { return false }
        guard let secretKey = Environment.get("AWS_SECRET_ACCESS_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secretKey.isEmpty else { return false }
        return true
    }

    /// S3 Express One Zone directory buckets end with `--x-s3` (e.g. `verra-app--use1-az4--x-s3`).
    static func isDirectoryBucket(_ bucket: String) -> Bool {
        bucket.hasSuffix("--x-s3")
    }

    static func publicURL(for key: String, baseURL: String?) -> String? {
        guard !key.isEmpty else { return nil }
        if key.hasPrefix("http") { return key }
        // Local API paths must stay relative so the iOS client resolves them
        // against APIConfig.baseURL (localhost in Simulator, production elsewhere).
        if key.hasPrefix("/api/") { return key }
        // Directory buckets are private — always serve through the API proxy.
        if isS3Configured(),
           let bucket = Environment.get("S3_BUCKET"),
           isDirectoryBucket(bucket) {
            return "/api/storage/\(key)"
        }
        if isS3Configured(), let url = objectURL(for: key) {
            return url.absoluteString
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
        // Prefer S3 when fully configured; fall back to local disk if the
        // upload fails so progress photos still work in local/dev.
        if isS3Configured() {
            do {
                let key = "\(folder)/\(filename)"
                try await uploadToS3(data: data, key: key, contentType: contentType, on: app)
                return key
            } catch {
                app.logger.warning("S3 upload failed — falling back to local storage: \(error)")
            }
        }
        return try saveLocally(data: data, filename: filename, folder: folder, on: app)
    }

    /// Downloads an object from S3 (used to proxy private / Express buckets to clients).
    static func fetch(key: String, on app: Application) async throws -> Data {
        guard let url = objectURL(for: key) else {
            throw Abort(.internalServerError, reason: "S3 is not configured")
        }

        let auth = try await signedRequest(
            method: "GET",
            url: url,
            headers: [:],
            body: Data(),
            on: app
        )

        let response = try await app.client.get(URI(string: url.absoluteString)) { request in
            applySignedHeaders(auth, to: &request)
        }

        guard (200..<300).contains(response.status.code),
              let buffer = response.body else {
            throw Abort(.notFound, reason: "S3 object not found")
        }
        return Data(buffer.readableBytesView)
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

    // MARK: - Internals

    private static func saveLocally(data: Data, filename: String, folder: String, on app: Application) throws -> String {
        let dir = localDirectory(folder: folder, on: app)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + filename
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return "/api/storage/\(folder)/\(filename)"
    }

    /// Availability zone id embedded in directory bucket names: `name--use1-az4--x-s3`.
    private static func directoryBucketAvailabilityZone(_ bucket: String) -> String? {
        guard bucket.hasSuffix("--x-s3") else { return nil }
        let trimmed = String(bucket.dropLast("--x-s3".count))
        guard let range = trimmed.range(of: "--", options: .backwards) else { return nil }
        let az = String(trimmed[range.upperBound...])
        return az.isEmpty ? nil : az
    }

    private static func sigV4Service(for bucket: String) -> String {
        isDirectoryBucket(bucket) ? "s3express" : "s3"
    }

    private static func configuredBucket() -> String? {
        Environment.get("S3_BUCKET")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func objectURL(for key: String) -> URL? {
        guard let bucket = configuredBucket(), !bucket.isEmpty else { return nil }
        let region = Environment.get("AWS_REGION") ?? "us-east-1"
        let host: String
        if isDirectoryBucket(bucket), let az = directoryBucketAvailabilityZone(bucket) {
            host = "\(bucket).s3express-\(az).\(region).amazonaws.com"
        } else {
            host = "\(bucket).s3.\(region).amazonaws.com"
        }
        let encodedKey = key
            .split(separator: "/")
            .map { component in
                component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
        return URL(string: "https://\(host)/\(encodedKey)")
    }

    private static func iamCredentials() throws -> AWSSigV4Signer.Credentials {
        guard let accessKey = Environment.get("AWS_ACCESS_KEY_ID"),
              let secretKey = Environment.get("AWS_SECRET_ACCESS_KEY") else {
            throw Abort(.internalServerError, reason: "S3 is not configured")
        }
        return .init(
            accessKeyID: accessKey,
            secretAccessKey: secretKey,
            sessionToken: Environment.get("AWS_SESSION_TOKEN").flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private struct SignedRequest {
        let authorization: String
        let amzDate: String
        let payloadHash: String
        /// Required for S3 Express zonal APIs (`x-amz-s3session-token`).
        let s3SessionToken: String?
        /// STS / CreateSession token for SigV4 (`x-amz-security-token`).
        let securityToken: String?
    }

    private static func signedRequest(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data,
        on app: Application
    ) async throws -> SignedRequest {
        guard let bucket = configuredBucket() else {
            throw Abort(.internalServerError, reason: "S3 is not configured")
        }
        let region = Environment.get("AWS_REGION") ?? "us-east-1"
        let service = sigV4Service(for: bucket)

        let credentials: AWSSigV4Signer.Credentials
        let s3SessionToken: String?
        if isDirectoryBucket(bucket) {
            let session = try await ExpressSessionCache.shared.credentials(on: app)
            credentials = .init(
                accessKeyID: session.accessKeyID,
                secretAccessKey: session.secretAccessKey,
                sessionToken: session.sessionToken
            )
            s3SessionToken = session.sessionToken
        } else {
            credentials = try iamCredentials()
            s3SessionToken = nil
        }

        var signHeaders = headers
        if let s3SessionToken {
            signHeaders["x-amz-s3session-token"] = s3SessionToken
        }

        let signed = AWSSigV4Signer.authorizationHeader(
            method: method,
            url: url,
            headers: signHeaders,
            body: body,
            service: service,
            region: region,
            credentials: credentials
        )

        return SignedRequest(
            authorization: signed.authorization,
            amzDate: signed.amzDate,
            payloadHash: signed.payloadHash,
            s3SessionToken: s3SessionToken,
            securityToken: credentials.sessionToken
        )
    }

    private static func applySignedHeaders(_ auth: SignedRequest, to request: inout ClientRequest) {
        request.headers.replaceOrAdd(name: .authorization, value: auth.authorization)
        request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-date"), value: auth.amzDate)
        request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-content-sha256"), value: auth.payloadHash)
        if let token = auth.securityToken {
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-security-token"), value: token)
        }
        if let token = auth.s3SessionToken {
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-s3session-token"), value: token)
        }
    }

    private static func uploadToS3(data: Data, key: String, contentType: String, on app: Application) async throws {
        guard let url = objectURL(for: key) else {
            throw Abort(.internalServerError, reason: "S3 is not configured")
        }

        let auth = try await signedRequest(
            method: "PUT",
            url: url,
            headers: ["content-type": contentType],
            body: data,
            on: app
        )

        let response = try await app.client.put(URI(string: url.absoluteString)) { request in
            applySignedHeaders(auth, to: &request)
            request.headers.replaceOrAdd(name: .contentType, value: contentType)
            request.body = ByteBuffer(bytes: [UInt8](data))
        }

        guard (200..<300).contains(response.status.code) else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("S3 upload failed (\(response.status.code)): \(body.prefix(300))")
            throw Abort(.badGateway, reason: "S3 upload failed (\(response.status.code))")
        }
    }

    private static func deleteFromS3(key: String, on app: Application) async throws {
        guard let url = objectURL(for: key) else { return }

        let auth = try await signedRequest(
            method: "DELETE",
            url: url,
            headers: [:],
            body: Data(),
            on: app
        )

        let response = try await app.client.delete(URI(string: url.absoluteString)) { request in
            applySignedHeaders(auth, to: &request)
        }

        guard (200..<300).contains(response.status.code) || response.status.code == 404 else {
            throw Abort(.badGateway, reason: "S3 delete failed (\(response.status.code))")
        }
    }

    /// CreateSession for S3 Express directory buckets (temporary 5-minute credentials).
    fileprivate static func createExpressSession(on app: Application) async throws -> ExpressSession {
        guard let bucket = configuredBucket(),
              let az = directoryBucketAvailabilityZone(bucket),
              isDirectoryBucket(bucket) else {
            throw Abort(.internalServerError, reason: "Directory bucket is not configured")
        }

        let region = Environment.get("AWS_REGION") ?? "us-east-1"
        // Empty value must be `session=` for SigV4 canonical query.
        guard let url = URL(string: "https://\(bucket).s3express-\(az).\(region).amazonaws.com/?session=") else {
            throw Abort(.internalServerError, reason: "Invalid S3 Express endpoint")
        }

        let credentials = try iamCredentials()
        let headers = ["x-amz-create-session-mode": "ReadWrite"]
        let signed = AWSSigV4Signer.authorizationHeader(
            method: "GET",
            url: url,
            headers: headers,
            body: Data(),
            service: "s3express",
            region: region,
            credentials: credentials
        )

        let response = try await app.client.get(URI(string: url.absoluteString)) { request in
            request.headers.replaceOrAdd(name: .authorization, value: signed.authorization)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-date"), value: signed.amzDate)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-content-sha256"), value: signed.payloadHash)
            request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-create-session-mode"), value: "ReadWrite")
            if let token = credentials.sessionToken {
                request.headers.replaceOrAdd(name: HTTPHeaders.Name("x-amz-security-token"), value: token)
            }
        }

        guard (200..<300).contains(response.status.code),
              let buffer = response.body else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            app.logger.error("S3 Express CreateSession failed (\(response.status.code)): \(body.prefix(300))")
            throw Abort(.badGateway, reason: "S3 Express CreateSession failed (\(response.status.code))")
        }

        let xml = String(buffer: buffer)
        guard let accessKeyID = xmlTag("AccessKeyId", in: xml),
              let secretAccessKey = xmlTag("SecretAccessKey", in: xml),
              let sessionToken = xmlTag("SessionToken", in: xml) else {
            throw Abort(.badGateway, reason: "S3 Express CreateSession returned invalid credentials")
        }

        let expiration: Date
        if let raw = xmlTag("Expiration", in: xml),
           let parsed = ISO8601DateFormatter().date(from: raw) {
            expiration = parsed
        } else {
            expiration = Date().addingTimeInterval(5 * 60)
        }

        return ExpressSession(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiration: expiration
        )
    }

    private static func xmlTag(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"),
              let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}

// MARK: - S3 Express session cache

private struct ExpressSession {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String
    let expiration: Date
}

private actor ExpressSessionCache {
    static let shared = ExpressSessionCache()

    private var session: ExpressSession?

    func credentials(on app: Application) async throws -> ExpressSession {
        if let session, session.expiration.timeIntervalSinceNow > 60 {
            return session
        }
        let created = try await StorageService.createExpressSession(on: app)
        session = created
        return created
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
