import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Unexpected server response"
        case .server(let message): return message
        case .decoding(let error): return error.localizedDescription
        }
    }
}

struct APIClient {
    static let shared = APIClient()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: value) { return date }
            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let date = withoutFractional.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }()

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            do {
                return try Self.decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        }

        if let apiError = try? Self.decoder.decode(APIErrorResponse.self, from: data) {
            throw APIError.server(apiError.reason)
        }
        let fallback = String(data: data, encoding: .utf8) ?? "Request failed"
        throw APIError.server(fallback)
    }
}

private struct APIErrorResponse: Decodable {
    let reason: String
}

private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
