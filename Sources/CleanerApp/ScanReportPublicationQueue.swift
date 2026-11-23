import Foundation

/// Publications build from the last committed report, even when module callbacks
/// arrive concurrently. The operation may suspend for background preparation;
/// later callbacks cannot capture a stale baseline while it is suspended.
@MainActor final class ScanReportPublicationQueue {
    private var tail: Task<Void, Never>?
    private var lastTicket: UUID?

    func perform(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        let previous = tail
        let ticket = UUID()
        let task = Task {
            await previous?.value
            await operation()
        }
        tail = task
        lastTicket = ticket
        await task.value
        if lastTicket == ticket { tail = nil; lastTicket = nil }
    }
}
