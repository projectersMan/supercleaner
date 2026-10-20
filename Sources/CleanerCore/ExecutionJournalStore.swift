import Foundation

public enum ExecutionJournalStoreError: Error, Sendable {
    case simulatedInterruptedCommit
}

public enum ResolutionAction: String, Codable, Hashable, Sendable {
    case restore
    case trash
    case purge
}

public struct ResolutionJournalItem: Codable, Hashable, Sendable {
    public let candidateID: UUID
    public let sourceURL: URL
    public let destinationURL: URL?
    public let sourceExistedAtPreparation: Bool

    public init(
        candidateID: UUID,
        sourceURL: URL,
        destinationURL: URL?,
        sourceExistedAtPreparation: Bool
    ) {
        self.candidateID = candidateID
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sourceExistedAtPreparation = sourceExistedAtPreparation
    }
}

public struct ResolutionJournalEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let action: ResolutionAction
    public let receipt: OperationReceipt
    public let startedAt: Date
    public let items: [ResolutionJournalItem]

    public init(
        id: UUID,
        action: ResolutionAction,
        receipt: OperationReceipt,
        startedAt: Date,
        items: [ResolutionJournalItem]
    ) {
        self.id = id
        self.action = action
        self.receipt = receipt
        self.startedAt = startedAt
        self.items = items
    }

    func isFullyResolved(by results: [OperationResult]) -> Bool {
        let expectedCandidateIDs = Set(
            receipt.results.filter { $0.disposition == .quarantined }.map(\.candidateID)
        )
        let resolvedCandidateIDs = Set(results.compactMap { result -> UUID? in
            switch action {
            case .restore:
                return result.disposition == .restored
                    && [.restored, .restoreConflict].contains(result.status)
                    ? result.candidateID
                    : nil
            case .trash:
                return result.disposition == .trashed && result.status == .succeeded
                    ? result.candidateID
                    : nil
            case .purge:
                return (result.disposition == .permanentlyDeleted && result.status == .succeeded)
                    || (result.disposition == .unavailable && result.status == .sourceMissing)
                    ? result.candidateID
                    : nil
            }
        })
        return expectedCandidateIDs.isSubset(of: resolvedCandidateIDs)
    }
}

public struct ExecutionJournalEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let plan: CleanupPlan
    public let startedAt: Date
    public let retentionPolicy: QuarantineRetentionPolicy

    public init(
        id: UUID,
        plan: CleanupPlan,
        startedAt: Date,
        retentionPolicy: QuarantineRetentionPolicy
    ) {
        self.id = id
        self.plan = plan
        self.startedAt = startedAt
        self.retentionPolicy = retentionPolicy
    }
}

public actor ResolutionJournalStore {
    private let url: URL
    private let manager: FileManager
    private var failNextCommit = false

    public init(url: URL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    public func entries() throws -> [ResolutionJournalEntry] {
        guard manager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ResolutionJournalEntry].self, from: Data(contentsOf: url))
    }

    public func upsert(_ entry: ResolutionJournalEntry) throws {
        var all = try entries()
        if let index = all.firstIndex(where: { $0.id == entry.id }) {
            all[index] = entry
        } else {
            all.append(entry)
        }
        try commit(all)
    }

    public func remove(id: UUID) throws {
        let all = try entries()
        let remaining = all.filter { $0.id != id }
        guard remaining.count != all.count else { return }
        try commit(remaining)
    }

    public func failNextCommitForTesting() {
        failNextCommit = true
    }

    private func commit(_ entries: [ResolutionJournalEntry]) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entries.sorted { $0.startedAt < $1.startedAt })
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".resolution-journal-\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if failNextCommit {
            failNextCommit = false
            try manager.removeItem(at: temporary)
            throw ExecutionJournalStoreError.simulatedInterruptedCommit
        }
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}

public actor ExecutionJournalStore {
    private let url: URL
    private let manager: FileManager
    private var failNextCommit = false

    public init(url: URL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    public func entries() throws -> [ExecutionJournalEntry] {
        guard manager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ExecutionJournalEntry].self, from: Data(contentsOf: url))
    }

    public func entry(id: UUID) throws -> ExecutionJournalEntry? {
        try entries().first { $0.id == id }
    }

    public func upsert(_ entry: ExecutionJournalEntry) throws {
        var all = try entries()
        if let index = all.firstIndex(where: { $0.id == entry.id }) {
            all[index] = entry
        } else {
            all.append(entry)
        }
        try commit(all)
    }

    public func remove(id: UUID) throws {
        let all = try entries()
        let remaining = all.filter { $0.id != id }
        guard remaining.count != all.count else { return }
        try commit(remaining)
    }

    public func failNextCommitForTesting() {
        failNextCommit = true
    }

    private func commit(_ entries: [ExecutionJournalEntry]) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entries.sorted { $0.startedAt < $1.startedAt })
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".execution-journal-\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if failNextCommit {
            failNextCommit = false
            try manager.removeItem(at: temporary)
            throw ExecutionJournalStoreError.simulatedInterruptedCommit
        }
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}
