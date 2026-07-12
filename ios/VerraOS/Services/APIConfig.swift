import Foundation

enum APIConfig {
    /// Simulator can use localhost; a physical device uses a public tunnel when LAN is blocked.
    static let baseURL: URL = {
        #if targetEnvironment(simulator)
        URL(string: "http://127.0.0.1:8080")!
        #else
        URL(string: "https://bird-wealth-cindy-redhead.trycloudflare.com")!
        #endif
    }()
}
