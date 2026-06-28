import Foundation

enum APIConfig {
    /// Simulator reaches the Mac host at 127.0.0.1. Use your LAN IP for a physical device.
    static let baseURL = URL(string: "http://127.0.0.1:8080")!
}
