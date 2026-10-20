import Foundation

public enum HistoryStoreError: Error, Sendable {
    case simulatedInterruptedCommit
    case receiptNotFound
}

public actor HistoryStore {
    private let url: URL
    private let manager: FileManager
    private var failNextCommit = false

    public init(url: URL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    public func append(_ receipt: OperationReceipt) throws {
        var all = try receipts()
        all.append(receipt)
        try commit(all)
    }

    public func upsert(_ receipt: OperationReceipt) throws {
        var all = try receipts()
        if let index = all.firstIndex(where: { $0.id == receipt.id }) {
            all[index] = receipt
        } else {
            all.append(receipt)
        }
        try commit(all)
    }

    public func receipts() throws -> [OperationReceipt] {
        guard manager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([OperationReceipt].self, from: Data(contentsOf: url))
    }

    public func receipt(id: UUID) throws -> OperationReceipt? {
        try receipts().first { $0.id == id }
    }

    public func replace(_ receipt: OperationReceipt) throws {
        var all = try receipts()
        guard let index = all.firstIndex(where: { $0.id == receipt.id }) else {
            throw HistoryStoreError.receiptNotFound
        }
        all[index] = receipt
        try commit(all)
    }

    public func failNextCommitForTesting() {
        failNextCommit = true
    }

    private func commit(_ receipts: [OperationReceipt]) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipts)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".history-\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if failNextCommit {
            failNextCommit = false
            try? manager.removeItem(at: temporary)
            throw HistoryStoreError.simulatedInterruptedCommit
        }
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}
