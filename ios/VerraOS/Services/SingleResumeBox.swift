import Foundation

/// Resumes a checked continuation at most once (prevents fatal continuation misuse crashes).
///
/// Uses a locked one-shot handler instead of storing `CheckedContinuation` directly.
/// Holding the continuation in a generic class deinit crashes Swift 6.3’s Release
/// optimizer (`EarlyPerfInliner`).
nonisolated final class SingleResumeBox<T, E: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Result<T, E>) -> Void)?

    init(_ continuation: CheckedContinuation<T, E>) {
        handler = { continuation.resume(with: $0) }
    }

    func resume(returning value: T) {
        resume(with: .success(value))
    }

    func resume(throwing error: E) {
        resume(with: .failure(error))
    }

    func resume(with result: Result<T, E>) {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()
        handler?(result)
    }
}
