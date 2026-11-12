import XCTest
@testable import CleanerCore

final class CleanupCompletionPerformanceTests: XCTestCase {
    func testTrashResolutionPublishesItsOwnStageAndCounts() async {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("trash-progress-\(UUID())")
        let quarantine = home.appendingPathComponent("Quarantine")
        let planID = UUID(), candidateID = UUID()
        let original = home.appendingPathComponent("payload")
        let source = quarantine.appendingPathComponent(planID.uuidString).appendingPathComponent(candidateID.uuidString + "-payload")
        let receipt = OperationReceipt(planID: planID, startedAt: Date(), completedAt: Date(),
            results: [.init(candidateID: candidateID, originalURL: original, destinationURL: source,
                disposition: .quarantined, status: .succeeded, bytes: 1)], overallStatus: .completed)
        let entry = ResolutionJournalEntry(id: UUID(), action: .trash, receipt: receipt, startedAt: Date(),
            items: [.init(candidateID: candidateID, sourceURL: source, destinationURL: nil, sourceExistedAtPreparation: false)])
        let captured = CapturedCompletionProgress()
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: .init(homeDirectory: home),
            quarantineRoot: quarantine, currentRuleVersion: "fixture")
        let results = await executor.resolve(entry) { captured.append($0) }
        let updates = captured.values
        XCTAssertEqual(updates.map(\.phase), [.movingToTrash, .movingToTrash])
        XCTAssertEqual(updates.map(\.completed), [0, 1])
        XCTAssertEqual(updates.map(\.total), [1, 1])
        XCTAssertEqual(updates.first?.currentURL, original)
        XCTAssertEqual(results.first?.status, .sourceMissing)
    }
    func testDeclarationCacheReusesOnlyExactCurrentSource() async {
        let cache = ApplicationDataDeclarationCache()
        let first = Data("app.setPath('userData',path.join(app.getPath('appData'),'First'));".utf8)
        let changed = Data("app.setPath('userData',path.join(app.getPath('appData'),'Changed'));".utf8)
        let a = await cache.names(in: first)
        let b = await cache.names(in: first)
        let c = await cache.names(in: changed)
        let parsed = await cache.parseCount
        XCTAssertEqual(a, ["First"])
        XCTAssertEqual(b, a)
        XCTAssertEqual(c, ["Changed"])
        XCTAssertEqual(parsed, 2)
    }

    func testHistoryReuseSeesOtherWriterAndRejectsCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-reuse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let reader = HistoryStore(url: url), writer = HistoryStore(url: url)
        let first = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [], overallStatus: .completed)
        try await reader.append(first)
        _ = try await reader.receipts()
        let second = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [], overallStatus: .completed)
        try await writer.append(second)
        let updated = try await reader.receipts()
        XCTAssertEqual(updated.map(\.id), [first.id, second.id])
        try Data("invalid".utf8).write(to: url)
        do { _ = try await reader.receipts(); XCTFail("a cached result must not hide invalid current data") } catch { }
    }

    func testLargeInventoryAliasReconciliationUsesLexicalPaths() {
        let candidates = (0..<50_000).map { index in
            CleanupCandidate(url: URL(fileURLWithPath: "/Users/fixture/agent/item-\(index)"),
                displayName: "item", category: .cache, bytes: 1, risk: .review, evidence: [],
                identity: .init(device: 1, inode: UInt64(index + 1), size: 1, modificationTime: 1, kind: .file),
                source: .general, lastAccessDate: nil, isActive: false)
        }
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(),
            results: [.init(candidateID: candidates[0].id, originalURL: candidates[0].url,
                disposition: .quarantined, status: .succeeded, bytes: 1)], overallStatus: .completed)
        let outcome = DefaultCleanupAttemptOutcome(attemptedCandidates: [candidates[0]], receipt: receipt)
        var tracking = DefaultCleanupTrackingState(selectedCandidateIDs: [candidates[0].id, candidates[1].id],
            uninstallSelectedItemIDs: [], cleanedCandidateIDs: [], failures: [])
        let start = Date()
        tracking.reconcileSuccessfulAliases(outcome: outcome, knownCandidates: candidates)
        let elapsed = Date().timeIntervalSince(start)
        print("Completion aliases: 50,000 candidates / one removal = \(elapsed)s")
        XCTAssertEqual(tracking.selectedCandidateIDs, [candidates[1].id])
        XCTAssertEqual(tracking.cleanedCandidateIDs, [candidates[0].id])
        XCTAssertLessThan(elapsed, 1, "finishing one item must not normalize 50,000 paths through Foundation")
    }
}

private final class CapturedCompletionProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExecutionProgress] = []
    var values: [ExecutionProgress] { lock.withLock { storage } }
    func append(_ value: ExecutionProgress) { lock.withLock { storage.append(value) } }
}
