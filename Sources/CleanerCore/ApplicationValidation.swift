import Foundation

/// Run read-only validation off the caller and let an explicit Stop return even
/// if a system read ignores cancellation. Late replies cannot authorize a move.
enum ApplicationValidation {
    static func run(operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        let reply = ValidationReply()
        let work = Task.detached {
            do { try Task.checkCancellation(); try await operation(); reply.finish(.success(())) }
            catch { reply.finish(.failure(error)) }
        }
        defer { work.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { reply.begin($0) }
        } onCancel: {
            reply.finish(.failure(CancellationError()))
            work.cancel()
        }
    }
}

private final class ValidationReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var outcome: Result<Void, any Error>?
    func begin(_ continuation: CheckedContinuation<Void, any Error>) {
        let completed = lock.withLock { () -> Result<Void, any Error>? in
            if let outcome { return outcome }
            self.continuation = continuation
            return nil
        }
        if let completed { continuation.resume(with: completed) }
    }
    func finish(_ outcome: Result<Void, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            guard self.outcome == nil else { return nil }
            self.outcome = outcome
            let pending = continuation; continuation = nil
            return pending
        }
        pending?.resume(with: outcome)
    }
}
