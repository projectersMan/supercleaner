import Foundation
import XCTest
@testable import CleanerCore

final class HistoryStoreTests: XCTestCase {
    func testInterruptedWritePreservesPreviousHistoryAndStoreRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(url: root.appendingPathComponent("history.json"))
        let first = OperationReceipt(planID: UUID(), startedAt: Date(timeIntervalSince1970: 1), completedAt: Date(timeIntervalSince1970: 2), results: [])
        let second = OperationReceipt(planID: UUID(), startedAt: Date(timeIntervalSince1970: 3), completedAt: Date(timeIntervalSince1970: 4), results: [])
        try await store.append(first)
        await store.failNextCommitForTesting()
        do { try await store.append(second); XCTFail("commit should fail") } catch {}
        XCTAssertEqual(try await store.receipts(), [first])
        try await store.append(second)
        XCTAssertEqual(try await store.receipts(), [first, second])
    }

    func testUpsertInsertsThenReplacesReceiptWithoutDuplicatingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(url: root.appendingPathComponent("history.json"))
        let receipt = OperationReceipt(
            planID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            results: []
        )
        let updated = OperationReceipt(
            id: receipt.id,
            planID: receipt.planID,
            startedAt: receipt.startedAt,
            completedAt: Date(timeIntervalSince1970: 3),
            results: [],
            overallStatus: .partial
        )

        try await store.upsert(receipt)
        try await store.upsert(updated)
        let receipts = try await store.receipts()

        XCTAssertEqual(receipts, [updated])
    }
}
