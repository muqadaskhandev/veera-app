import Foundation
import NIOCore
import Vapor

/// Sends transactional email through Amazon SES (API v2).
enum SESEmailService {
    struct Configuration {
        let region: String
        let fromEmail: String
        let fromName: String?
        let credentials: AWSSigV4Signer.Credentials

        static func load() -> Configuration? {
            guard
                let accessKey = Environment.get("AWS_ACCESS_KEY_ID"), !accessKey.isEmpty,
                let secretKey = Environment.get("AWS_SECRET_ACCESS_KEY"), !secretKey.isEmpty,
                let fromEmail = Environment.get("SES_FROM_EMAIL"), !fromEmail.isEmpty
            else {
                return nil
            }

            return Configuration(
                region: Environment.get("AWS_REGION") ?? "us-east-1",
                fromEmail: fromEmail,
                fromName: Environment.get("SES_FROM_NAME"),
                credentials: .init(
                    accessKeyID: accessKey,
                    secretAccessKey: secretKey,
                    sessionToken: Environment.get("AWS_SESSION_TOKEN")
                )
            )
        }
    }

    static func isConfigured() -> Bool {
        Configuration.load() != nil
    }

    static func send(
        to recipient: String,
        subject: String,
        textBody: String,
        htmlBody: String? = nil,
        on request: Request
    ) async throws {
        try await send(to: recipient, subject: subject, textBody: textBody, htmlBody: htmlBody, on: request.application)
    }

    static func send(
        to recipient: String,
        subject: String,
        textBody: String,
        htmlBody: String? = nil,
        on app: Application
    ) async throws {
        guard let config = Configuration.load() else {
            throw Abort(.internalServerError, reason: "Email service is not configured")
        }

        let fromAddress: String
        if let fromName = config.fromName, !fromName.isEmpty {
            fromAddress = "\(fromName) <\(config.fromEmail)>"
        } else {
            fromAddress = config.fromEmail
        }

        var bodyObject: [String: Any] = [
            "Text": ["Data": textBody, "Charset": "UTF-8"],
        ]
        if let htmlBody {
            bodyObject["Html"] = ["Data": htmlBody, "Charset": "UTF-8"]
        }

        let payload: [String: Any] = [
            "FromEmailAddress": fromAddress,
            "Destination": ["ToAddresses": [recipient]],
            "Content": [
                "Simple": [
                    "Subject": ["Data": subject, "Charset": "UTF-8"],
                    "Body": bodyObject,
                ],
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let endpoint = URL(string: "https://email.\(config.region).amazonaws.com/v2/email/outbound-emails")!
        let signed = AWSSigV4Signer.authorizationHeader(
            method: "POST",
            url: endpoint,
            headers: ["content-type": "application/json"],
            body: bodyData,
            service: "ses",
            region: config.region,
            credentials: config.credentials
        )

        let response = try await app.client.post(URI(string: endpoint.absoluteString)) { clientRequest in
            clientRequest.headers.replaceOrAdd(name: .contentType, value: "application/json")
            clientRequest.headers.replaceOrAdd(name: .init("host"), value: endpoint.host!)
            clientRequest.headers.replaceOrAdd(name: .init("x-amz-date"), value: signed.amzDate)
            clientRequest.headers.replaceOrAdd(name: .init("authorization"), value: signed.authorization)
            if let sessionToken = config.credentials.sessionToken {
                clientRequest.headers.replaceOrAdd(name: .init("x-amz-security-token"), value: sessionToken)
            }
            var buffer = ByteBuffer()
            buffer.writeBytes(bodyData)
            clientRequest.body = .init(buffer: buffer)
        }

        guard (200 ... 299).contains(response.status.code) else {
            let responseBody = response.body.flatMap { String(buffer: $0) } ?? ""
            app.logger.error("SES send failed (\(response.status.code)): \(responseBody)")
            throw Abort(.internalServerError, reason: "Failed to send email")
        }

        app.logger.info("SES email sent to \(recipient)")
    }
}
