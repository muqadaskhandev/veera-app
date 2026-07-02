import Foundation

@MainActor
final class ChatWebSocketService {
    static let shared = ChatWebSocketService()

    var onEvent: ((ChatEventDTO) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    func connect(accessToken: String) {
        disconnect()

        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/chat"
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]

        guard let url = components.url else { return }

        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        receiveLoopTask = Task { await receiveLoop() }
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func sendTyping(conversationID: UUID, isTyping: Bool) {
        let type = isTyping ? "typing.start" : "typing.stop"
        sendJSON(["type": type, "conversationID": conversationID.uuidString])
    }

    private func sendJSON(_ payload: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let task {
            do {
                let message = try await task.receive()
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
                if !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                }
                break
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
            let value = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: value) { return date }
            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let date = withoutFractional.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return try decoder.decode(T.self, from: data)
    }
}
