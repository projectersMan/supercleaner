import CleanerCore
import Combine
import Foundation

/// Only the sidebar observes capacity changes; periodic reads never invalidate cleanup lists.
@MainActor
final class DiskCapacityMonitor: ObservableObject {
    @Published private(set) var snapshot: DiskCapacitySnapshot?
    @Published private(set) var readError: String?
    private let directory: URL
    private let refreshInterval: TimeInterval
    private let read: @Sendable (URL) async -> DiskCapacityReadResult
    private var heartbeat: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    init(directory: URL, refreshInterval: TimeInterval,
         read: @escaping @Sendable (URL) async -> DiskCapacityReadResult) {
        precondition(refreshInterval > 0, "Disk capacity refresh interval must be positive")
        self.directory = directory
        self.refreshInterval = refreshInterval
        self.read = read
    }

    func start() {
        refresh()
        guard heartbeat == nil else { return }
        heartbeat = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        let directory = directory
        let read = read
        refreshTask = Task { [weak self] in
            let result = await read(directory)
            guard let self else { return }
            switch result {
            case let .available(value):
                if snapshot?.volumeURL != value.volumeURL || snapshot?.totalBytes != value.totalBytes
                    || snapshot?.availableBytes != value.availableBytes {
                    snapshot = value
                }
                if readError != nil { readError = nil }
            case let .unavailable(code):
                if snapshot != nil { snapshot = nil }
                let message = NSError(domain: NSPOSIXErrorDomain, code: Int(code)).localizedDescription
                if readError != message { readError = message }
            }
            refreshTask = nil
        }
    }

    func waitForRefresh() async { await refreshTask?.value }
}
