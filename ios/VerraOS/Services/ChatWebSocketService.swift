import Foundation

@MainActor
final class ChatWebSocketService {
    static let shared = ChatWebSocketService()

    var onEvent: ((ChatEventDTO) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var accessToken: String?

    func connect(accessToken: String) {
        disconnect()
        self.accessToken = accessToken
        openSocket(accessToken: accessToken)
        receiveLoopTask = Task { await receiveLoop() }
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        accessToken = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendTyping(conversationID: UUID, isTyping: Bool) {
        let type = isTyping ? "typing.start" : "typing.stop"
        sendJSON(["type": type, "conversationID": conversationID.uuidString])
    }

    private func openSocket(accessToken: String) {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/chat"
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]

        guard let url = components.url else { return }

        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
    }

    private func sendJSON(_ payload: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receiveLoop() async {
        var backoffSeconds: Double = 1
        while !Task.isCancelled {
            guard let task else { break }
            do {
                let message = try await task.receive()
                backoffSeconds = 1
                switch message {
                case .string(let text):
                    handle(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handle(text: text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if Task.isCancelled { break }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                try? await Task.sleep(for: .seconds(backoffSeconds))
                backoffSeconds = min(backoffSeconds * 2, 15)
                guard !Task.isCancelled, let token = accessToken else { break }
                openSocket(accessToken: token)
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? APIClient.shared.decode(ChatEventDTO.self, from: data) else {
            return
        }
        onEvent?(event)
    }
}

extension APIClient {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                let withFractional = ISO8601DateFormatter()
                withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = withFractional.date(from: value) { return date }
                let withoutFractional = ISO8601DateFormatter()
                withoutFractional.formatOptions = [.withInternetDateTime]
                if let date = withoutFractional.date(from: value) { return date }
            }
            if let value = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: value)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return try decoder.decode(T.self, from: data)
    }
}
