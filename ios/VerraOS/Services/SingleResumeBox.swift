import Foundation

/// Resumes a checked continuation at most once (prevents fatal continuation misuse crashes).
final class SingleResumeBox<T, E: Error> {
    private var continuation: CheckedContinuation<T, E>?

    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }

    func resume(throwing error: E) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    func resume(with result: Result<T, E>) {
        switch result {
        case .success(let value):
            resume(returning: value)
        case .failure(let error):
            resume(throwing: error)
        }
    }
}
