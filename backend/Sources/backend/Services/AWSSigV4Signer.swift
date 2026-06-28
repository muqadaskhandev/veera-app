import Crypto
import Foundation

/// Minimal AWS Signature Version 4 signer for SES API requests.
enum AWSSigV4Signer {
    struct Credentials {
        let accessKeyID: String
        let secretAccessKey: String
        let sessionToken: String?
    }

    static func authorizationHeader(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data,
        service: String,
        region: String,
        credentials: Credentials,
        now: Date = Date()
    ) -> (authorization: String, amzDate: String, payloadHash: String) {
        let amzDate = Self.timestamp(now)
        let dateStamp = Self.dateStamp(now)
        let payloadHash = SHA256.hash(data: body).hex

        var signedHeaders = headers.reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value.trimmingCharacters(in: .whitespaces)
        }
        signedHeaders["host"] = url.host?.lowercased()
        signedHeaders["x-amz-date"] = amzDate
        if let sessionToken = credentials.sessionToken {
            signedHeaders["x-amz-security-token"] = sessionToken
        }

        let sortedHeaderKeys = signedHeaders.keys.sorted()
        let canonicalHeaders = sortedHeaderKeys
            .map { key in
                "\(key):\(signedHeaders[key]!)"
            }
            .joined(separator: "\n") + "\n"
        let signedHeadersList = sortedHeaderKeys.joined(separator: ";")

        let canonicalRequest = [
            method,
            url.path.isEmpty ? "/" : url.path,
            url.query ?? "",
            canonicalHeaders,
            signedHeadersList,
            payloadHash,
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            SHA256.hash(data: Data(canonicalRequest.utf8)).hex,
        ].joined(separator: "\n")

        let signingKey = Self.signingKey(
            secret: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: service
        )
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey).hex

        let authorization = [
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(credentialScope)",
            "SignedHeaders=\(signedHeadersList)",
            "Signature=\(signature)",
        ].joined(separator: ", ")

        return (authorization, amzDate, payloadHash)
    }

    private static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let secretKey = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        let dateKey = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: secretKey)))
        let regionKey = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: dateKey)))
        let serviceKey = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(service.utf8), using: regionKey)))
        return SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: serviceKey)))
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private extension HMAC<SHA256>.MAC {
    var hex: String { Data(self).map { String(format: "%02x", $0) }.joined() }
}
