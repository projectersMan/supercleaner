import Foundation
import XCTest
@testable import CleanerCore

final class DeletionCancellationTests: XCTestCase {
    func testStopBeforeTrashDoesNotStartSystemMove() async throws {
        let fixture = try CancellationFixture()
        defer { fixture.remove() }
        let receipt = try await Task {
            try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate) { progress in
                if progress.phase == .movingToTrash, progress.currentURL != nil {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }.value
        let trashed = await fixture.fileSystem.trashed
        XCTAssertTrue(trashed.isEmpty, "Stop must be checked again after publishing the current item")
        XCTAssertTrue(receipt.results.allSatisfy { $0.disposition == .quarantined })
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual, "Stopped content must not be automatically retried")
    }

    func testStopDuringSystemMoveFinishesCurrentItemAndRetainsRemainderAcrossRestart() async throws {
        let fixture = try CancellationFixture()
        defer { fixture.remove() }
        await fixture.fileSystem.stopAfterFirstTrash()
        let receipt = try await Task {
            try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate)
        }.value
        let trashed = await fixture.fileSystem.trashed
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(receipt.results.filter { $0.disposition == .trashed }.count, 1)
        XCTAssertEqual(receipt.results.filter { $0.disposition == .quarantined }.count, 1)
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual)
        _ = try await fixture.coordinator.recoverPendingExecutions()
        _ = try await fixture.coordinator.processDue(at: Date().addingTimeInterval(86_400))
        let afterRestart = await fixture.fileSystem.trashed
        XCTAssertEqual(afterRestart.count, 1)
        let pending = try await fixture.resolutions.entries()
        XCTAssertTrue(pending.isEmpty)
    }

    func testStopDuringProcessingDoesNotContinueIntoTrash() async throws {
        let fixture = try CancellationFixture()
        defer { fixture.remove() }
        let receipt = try await Task {
            try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate) { progress in
                if progress.result?.status == .succeeded { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        let trashed = await fixture.fileSystem.trashed
        XCTAssertTrue(trashed.isEmpty)
        XCTAssertEqual(receipt.results.filter { $0.disposition == .quarantined }.count, 1)
        XCTAssertEqual(receipt.results.filter { $0.status == .skippedCancelled }.count, 1)
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual)
    }

    func testStopWhileSavingDoesNotBeginTrashAndSurvivesRestart() async throws {
        let fixture = try CancellationFixture()
        defer { fixture.remove() }
        let receipt = try await Task {
            try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate) { progress in
                if progress.phase == .savingResults { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        _ = try await fixture.coordinator.recoverPendingExecutions()
        _ = try await fixture.coordinator.processDue(at: Date().addingTimeInterval(86_400))
        let trashed = await fixture.fileSystem.trashed
        XCTAssertTrue(trashed.isEmpty)
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual)
    }

    func testLegacyResolutionJournalStillDecodes() throws {
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [])
        let entry = ResolutionJournalEntry(id: UUID(), action: .trash, receipt: receipt, startedAt: Date(), items: [])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        legacy.removeValue(forKey: "cancellationResults")
        let decoded = try JSONDecoder().decode(ResolutionJournalEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.cancellationResults)
        XCTAssertEqual(decoded, entry)
    }

    func testStopCheckpointSurvivesHistoryCommitFailure() async throws {
        let fixture = try CancellationFixture()
        defer { fixture.remove() }
        await fixture.fileSystem.stopAfterFirstTrash(historyToFail: fixture.history)
        do {
            _ = try await Task {
                try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate)
            }.value
            XCTFail("history failure must surface while retaining the stop checkpoint")
        } catch is HistoryStoreError { }
        _ = try await fixture.coordinator.recoverPendingExecutions()
        _ = try await fixture.coordinator.processDue(at: Date().addingTimeInterval(86_400))
        let trashed = await fixture.fileSystem.trashed
        XCTAssertEqual(trashed.count, 1, "Restart must replay completed results without starting stopped moves")
        let receipts = try await fixture.history.receipts()
        let receipt = try XCTUnwrap(receipts.first)
        XCTAssertEqual(receipt.results.filter { $0.disposition == .trashed }.count, 1)
        XCTAssertEqual(receipt.results.filter { $0.disposition == .quarantined }.count, 1)
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual)
        let pending = try await fixture.resolutions.entries()
        XCTAssertTrue(pending.isEmpty)
    }

    func testTwoLargeFilesStageTiming() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deletion-timing-\(UUID())")
        let fs = LocalFileSystem()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var candidates: [CleanupCandidate] = []
        for index in 0..<2 {
            let url = root.appendingPathComponent("installer-\(index).dmg")
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 300 * 1_048_576)
            try handle.close()
            candidates.append(.init(url: url, displayName: url.lastPathComponent, category: .largeFile,
                bytes: 300 * 1_048_576, risk: .review, evidence: [], identity: try await fs.identity(at: url),
                source: .diskAnalysis, lastAccessDate: nil, isActive: false))
        }
        let fixture = CancellationFixture.makeCoordinator(root: root, fileSystem: fs)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        let clock = DeletionStageClock()
        let receipt = try await fixture.coordinator.execute(plan: plan, retentionPolicy: .immediate) { clock.record($0) }
        clock.finish()
        defer {
            for result in receipt.results where result.disposition == .trashed {
                if let destination = result.destinationURL { try? FileManager.default.removeItem(at: destination) }
            }
        }
        XCTAssertEqual(receipt.results.filter { $0.disposition == .trashed }.count, 2)
    }
}

private struct CancellationFixture {
    let root: URL
    let fileSystem: CancellationFileSystem
    let plan: CleanupPlan
    let coordinator: CleanupExecutionCoordinator
    let history: HistoryStore
    let schedules: QuarantineScheduleStore
    let resolutions: ResolutionJournalStore

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deletion-cancel-\(UUID())")
        self.root = root
        let candidates = (0..<2).map { index in
            CleanupCandidate(url: root.appendingPathComponent("payload-\(index)"), displayName: "payload", category: .largeFile,
                bytes: 1, risk: .review, evidence: [],
                identity: .init(device: 1, inode: UInt64(index + 1), size: 1, modificationTime: 1, kind: .file),
                source: .diskAnalysis, lastAccessDate: nil, isActive: false)
        }
        plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        fileSystem = CancellationFileSystem(candidates: candidates)
        let graph = Self.makeCoordinator(root: root, fileSystem: fileSystem)
        coordinator = graph.coordinator; history = graph.history; schedules = graph.schedules; resolutions = graph.resolutions
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    static func makeCoordinator(root: URL, fileSystem: any FileSystemAccess) -> (coordinator: CleanupExecutionCoordinator, history: HistoryStore, schedules: QuarantineScheduleStore, resolutions: ResolutionJournalStore) {
        let executor = CleanupExecutor(fileSystem: fileSystem, pathPolicy: .init(homeDirectory: root),
            quarantineRoot: root.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture")
        let history = HistoryStore(url: root.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedules.json"))
        let resolutions = ResolutionJournalStore(url: root.appendingPathComponent("resolution.json"))
        let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules,
            executor: executor, resolutionJournalStore: resolutions)
        let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history,
            journalStore: ExecutionJournalStore(url: root.appendingPathComponent("execution.json")),
            resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance, now: Date.init)
        return (coordinator, history, schedules, resolutions)
    }
}

private actor CancellationFileSystem: FileSystemAccess {
    var entries: [URL: FileIdentity]
    private(set) var trashed: [URL] = []
    private var shouldStop = false
    private var historyToFail: HistoryStore?
    init(candidates: [CleanupCandidate]) { entries = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url, $0.identity) }) }
    func stopAfterFirstTrash(historyToFail: HistoryStore? = nil) { shouldStop = true; self.historyToFail = historyToFail }
    func identity(at url: URL) throws -> FileIdentity {
        guard let identity = entries[url] else { throw FileSystemError.missing(url) }; return identity
    }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func move(_ source: URL, to destination: URL) throws { entries[destination] = try identity(at: source); entries.removeValue(forKey: source) }
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) async -> URL {
        entries.removeValue(forKey: url); trashed.append(url)
        if let historyToFail { await historyToFail.failNextCommitForTesting() }
        if shouldStop { withUnsafeCurrentTask { $0?.cancel() } }
        return URL(fileURLWithPath: "/fixture-trash/" + url.lastPathComponent)
    }
}

private final class DeletionStageClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start = Date()
    private var previousPhase: ExecutionProgress.Phase?
    func record(_ progress: ExecutionProgress) {
        lock.withLock {
            guard previousPhase != progress.phase else { return }
            previousPhase = progress.phase
            print("Deletion timing: \(progress.phase) at \(Date().timeIntervalSince(start))s")
        }
    }
    func finish() { print("Deletion timing: finished at \(Date().timeIntervalSince(start))s") }
}
