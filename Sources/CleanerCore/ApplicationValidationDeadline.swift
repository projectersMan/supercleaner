import Foundation

enum ApplicationValidationDeadlineError: Error, Sendable, CustomStringConvertible {
    case timedOut
    var description: String { L10n.text("安全校验超时，未执行删除；可稍后重试。") }
}

/// One allowance for all associated-data checks, including the check immediately
/// before each move. The source app keeps a separate allowance afterward.
actor ApplicationValidationBudget {
    private let timeout: TimeInterval
    private var remaining: TimeInterval
    private var stalled = false
    init(seconds: TimeInterval) { timeout = seconds; remaining = seconds }
    var associationBudgetExhausted: Bool { stalled || remaining <= 0 }

    func validate(_ candidate: CleanupCandidate, operation: @escaping @Sendable () async throws -> Void) async throws {
        let association = candidate.category != .application
        if association && associationBudgetExhausted { throw ApplicationValidationDeadlineError.timedOut }
        let started = ContinuousClock.now
        defer {
            if association {
                let elapsed = started.duration(to: .now).components
                remaining -= Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            }
        }
        do {
            try await ApplicationValidationDeadline.run(seconds: association ? min(timeout, remaining) : timeout, operation: operation)
        } catch ApplicationValidationDeadlineError.timedOut {
            stalled = true
            throw ApplicationValidationDeadlineError.timedOut
        }
    }
}

/// Only read-only validation runs here. A timed-out result cannot resume the
/// executor or authorize a late move, even if a blocking system read returns later.
enum ApplicationValidationDeadline {
    static func run(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> Void) async throws {
        let reply = ValidationReply()
        let work = Task.detached {
            do { try await operation(); reply.finish(.success(())) }
            catch { reply.finish(.failure(error)) }
        }
        let timer = Task.detached {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            reply.finish(.failure(ApplicationValidationDeadlineError.timedOut))
            work.cancel()
        }
        defer { work.cancel(); timer.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { reply.begin($0) }
        } onCancel: {
            reply.finish(.failure(CancellationError()))
            work.cancel(); timer.cancel()
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
