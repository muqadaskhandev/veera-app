import Foundation
import JWT
import Vapor

struct APNsAlertPayload: Content {
    struct APS: Content {
        struct Alert: Content {
            var title: String
            var body: String
        }

        var alert: Alert
        var sound: String
        var badge: Int?
    }

    var aps: APS
    var conversationID: String
}

private struct APNsAuthClaims: JWTPayload {
    var iss: IssuerClaim
    var iat: IssuedAtClaim

    func verify(using signer: JWTSigner) throws {}
}

enum APNsService {
    static func isConfigured(on app: Application) -> Bool {
        config(on: app) != nil
    }

    static func sendAlert(
        to deviceToken: String,
        title: String,
        body: String,
        conversationID: UUID,
        badge: Int? = 1,
        on app: Application
    ) async {
        guard let config = config(on: app) else {
            app.logger.debug("APNs skipped — not configured")
            return
        }

        let token = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else { return }

        do {
            let jwt = try makeAuthToken(config: config)
            let payload = APNsAlertPayload(
                aps: .init(
                    alert: .init(title: title, body: body),
                    sound: "default",
                    badge: badge
                ),
                conversationID: conversationID.uuidString
            )

            let host = config.useSandbox
                ? "https://api.sandbox.push.apple.com"
                : "https://api.push.apple.com"
            let url = URI(string: "\(host)/3/device/\(token)")

            let response = try await app.client.post(url) { request in
                request.headers.add(name: .authorization, value: "bearer \(jwt)")
                request.headers.add(name: "apns-topic", value: config.bundleID)
                request.headers.add(name: "apns-push-type", value: "alert")
                request.headers.add(name: "apns-priority", value: "10")
                try request.content.encode(payload, as: .json)
            }

            if response.status == .ok {
                app.logger.info("APNs delivered to \(token.prefix(8))…")
            } else {
                let reason = response.body.map { String(buffer: $0) } ?? "unknown"
                app.logger.warning("APNs failed (\(response.status.code)): \(reason)")
            }
        } catch {
            app.logger.warning("APNs error: \(error.localizedDescription)")
        }
    }

    private struct Config {
        let keyID: String
        let teamID: String
        let bundleID: String
        let privateKeyPEM: String
        let useSandbox: Bool
    }

    private static func config(on app: Application) -> Config? {
        guard let keyID = Environment.get("APNS_KEY_ID"), !keyID.isEmpty,
              let teamID = Environment.get("APNS_TEAM_ID"), !teamID.isEmpty,
              let bundleID = Environment.get("APNS_BUNDLE_ID"), !bundleID.isEmpty else {
            return nil
        }

        let privateKeyPEM: String?
        if let inline = Environment.get("APNS_PRIVATE_KEY"), !inline.isEmpty {
            privateKeyPEM = inline.replacingOccurrences(of: "\\n", with: "\n")
        } else if let path = Environment.get("APNS_PRIVATE_KEY_PATH"), !path.isEmpty {
            privateKeyPEM = try? String(contentsOfFile: path, encoding: .utf8)
        } else {
            privateKeyPEM = nil
        }

        guard let privateKeyPEM, !privateKeyPEM.isEmpty else { return nil }

        let useSandbox = Environment.get("APNS_USE_SANDBOX")?.lowercased() != "false"
        return Config(keyID: keyID, teamID: teamID, bundleID: bundleID, privateKeyPEM: privateKeyPEM, useSandbox: useSandbox)
    }

    private static func makeAuthToken(config: Config) throws -> String {
        let key = try ECDSAKey.private(pem: config.privateKeyPEM)
        let signer = JWTSigner.es256(key: key)
        let claims = APNsAuthClaims(iss: .init(value: config.teamID), iat: .init(value: Date()))
        return try signer.sign(claims, kid: JWKIdentifier(string: config.keyID))
    }
}
