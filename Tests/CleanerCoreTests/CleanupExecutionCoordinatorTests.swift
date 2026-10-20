import Foundation
import XCTest
@testable import CleanerCore

final class CleanupExecutionCoordinatorTests: XCTestCase {
    func testJournalCommitFailurePreventsFileSystemMutation() async throws {
        let fixture = try makeFixture()
        await fixture.journal.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.execute(plan: fixture.plan, retentionPolicy: .hours24)
            XCTFail("execution should stop when the journal cannot commit")
        } catch is ExecutionJournalStoreError {
            let mutations = await fixture.fileSystem.mutations()
            let receipts = try await fixture.history.receipts()
            XCTAssertTrue(mutations.isEmpty)
            XCTAssertTrue(receipts.isEmpty)
        }
    }

    func testExecutionPersistsHistoryAndScheduleBeforeClearingJournal() async throws {
        let fixture = try makeFixture()

        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        let persistedReceipt = try await fixture.history.receipt(id: receipt.id)
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        let journalEntries = try await fixture.journal.entries()

        XCTAssertEqual(persistedReceipt, receipt)
        XCTAssertEqual(schedule?.policy, .hours24)
        XCTAssertTrue(journalEntries.isEmpty)
    }

    func testStartupRecoveryReconstructsMovedItemAndFinalizesJournal() async throws {
        let fixture = try makeFixture()
        let entry = ExecutionJournalEntry(
            id: UUID(),
            plan: fixture.plan,
            startedAt: fixture.now,
            retentionPolicy: .days2
        )
        let destination = fixture.quarantineRoot
            .appendingPathComponent(fixture.plan.id.uuidString, isDirectory: true)
            .appendingPathComponent(
                fixture.candidate.id.uuidString + "-" + fixture.candidate.url.lastPathComponent
            )
        await fixture.fileSystem.replaceSource(with: destination)
        try await fixture.journal.upsert(entry)

        let recovered = try await fixture.coordinator.recoverPendingExecutions()
        let persistedReceipt = try await fixture.history.receipt(id: entry.id)
        let schedule = try await fixture.schedules.schedule(receiptID: entry.id)
        let journalEntries = try await fixture.journal.entries()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].id, entry.id)
        XCTAssertEqual(recovered[0].results.first?.disposition, .quarantined)
        XCTAssertEqual(persistedReceipt, recovered[0])
        XCTAssertEqual(schedule?.policy, .days2)
        XCTAssertTrue(journalEntries.isEmpty)
    }

    func testDuplicatePlanIDIsRejectedBeforeFileSystemMutation() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        await fixture.fileSystem.clearMutations()

        do {
            _ = try await fixture.coordinator.execute(
                plan: fixture.plan,
                retentionPolicy: .hours24
            )
            XCTFail("duplicate plan ID should be rejected")
        } catch let error as CleanupExecutionCoordinatorError {
            XCTAssertEqual(error, .duplicatePlanID(fixture.plan.id))
        }

        let mutations = await fixture.fileSystem.mutations()
        XCTAssertTrue(mutations.isEmpty)
    }

    func testRestoreJournalCommitFailurePreventsFileSystemMutation() async throws {
        let fixture = try makeFixture()
        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        await fixture.fileSystem.clearMutations()
        await fixture.resolutionJournal.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.restore(receipt: receipt)
            XCTFail("restore should stop when its resolution journal cannot commit")
        } catch is ExecutionJournalStoreError {
            let mutations = await fixture.fileSystem.mutations()
            let persistedReceipt = try await fixture.history.receipt(id: receipt.id)
            XCTAssertTrue(mutations.isEmpty)
            XCTAssertEqual(persistedReceipt, receipt)
        }
    }

    func testPurgeJournalCommitFailurePreventsFileSystemMutation() async throws {
        let fixture = try makeFixture()
        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        await fixture.fileSystem.clearMutations()
        await fixture.resolutionJournal.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.purge(receipt: receipt)
            XCTFail("purge should stop when its resolution journal cannot commit")
        } catch is ExecutionJournalStoreError {
            let mutations = await fixture.fileSystem.mutations()
            let persistedReceipt = try await fixture.history.receipt(id: receipt.id)
            XCTAssertTrue(mutations.isEmpty)
            XCTAssertEqual(persistedReceipt, receipt)
        }
    }

    func testStartupRecoveryFinalizesRestoreAfterHistoryCommitFailure() async throws {
        let fixture = try makeFixture()
        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        await fixture.history.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.restore(receipt: receipt)
            XCTFail("restore finalization should surface history commit failure")
        } catch is HistoryStoreError {
            let pendingResolutions = try await fixture.resolutionJournal.entries()
            XCTAssertEqual(pendingResolutions.count, 1)
        }

        _ = try await fixture.coordinator.recoverPendingExecutions()
        let recoveredReceipt = try await fixture.history.receipt(id: receipt.id)
        let pendingResolutions = try await fixture.resolutionJournal.entries()
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(recoveredReceipt?.results.first?.disposition, .restored)
        XCTAssertTrue(pendingResolutions.isEmpty)
        XCTAssertNil(schedule)
    }

    func testStartupRecoveryFinalizesPurgeAfterHistoryCommitFailure() async throws {
        let fixture = try makeFixture()
        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        await fixture.history.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.purge(receipt: receipt)
            XCTFail("purge finalization should surface history commit failure")
        } catch is HistoryStoreError {
            let pendingResolutions = try await fixture.resolutionJournal.entries()
            XCTAssertEqual(pendingResolutions.count, 1)
        }

        _ = try await fixture.coordinator.recoverPendingExecutions()
        let recoveredReceipt = try await fixture.history.receipt(id: receipt.id)
        let pendingResolutions = try await fixture.resolutionJournal.entries()
        let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(recoveredReceipt?.results.first?.disposition, .permanentlyDeleted)
        XCTAssertTrue(pendingResolutions.isEmpty)
        XCTAssertNil(schedule)
    }

    func testMaintenanceHistoryFailurePersistsAttemptAndOneHourBackoff() async throws {
        let fixture = try makeFixture()
        let receipt = try await fixture.coordinator.execute(
            plan: fixture.plan,
            retentionPolicy: .hours24
        )
        try await fixture.coordinator.reschedule(
            receiptID: receipt.id,
            policy: .hours24,
            at: fixture.now.addingTimeInterval(-86_400)
        )
        await fixture.history.failNextCommitForTesting()

        do {
            _ = try await fixture.coordinator.processDue(at: fixture.now)
            XCTFail("maintenance should surface history commit failure")
        } catch is HistoryStoreError {
            let schedule = try await fixture.schedules.schedule(receiptID: receipt.id)
            let earlyRetry = try await fixture.schedules.dueSchedules(
                at: fixture.now.addingTimeInterval(3_599)
            )
            let dueRetry = try await fixture.schedules.dueSchedules(
                at: fixture.now.addingTimeInterval(3_600)
            )
            XCTAssertEqual(schedule?.lastAttemptAt, fixture.now)
            XCTAssertEqual(schedule?.failureReason?.code, .historyPersistenceFailed)
            XCTAssertTrue(earlyRetry.isEmpty)
            XCTAssertEqual(dueRetry.map(\.receiptID), [receipt.id])
        }
    }

    private func makeFixture() throws -> CoordinatorFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date(timeIntervalSince1970: 50_000)
        let candidate = coordinatorCandidate()
        let plan = try PlanBuilder(
            ruleVersion: "rules-1",
            planTTL: 300
        ).build(candidates: [candidate], selectedIDs: [candidate.id], now: now)
        let quarantineRoot = root.appendingPathComponent("quarantine", isDirectory: true)
        let fileSystem = CoordinatorFixtureFileSystem(
            source: candidate.url,
            identity: candidate.identity
        )
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            quarantineRoot: quarantineRoot,
            currentRuleVersion: "rules-1",
            now: { now },
            permanentRemove: { url in try await fileSystem.removePermanently(url) }
        )
        let history = HistoryStore(url: root.appendingPathComponent("history.json"))
        let journal = ExecutionJournalStore(url: root.appendingPathComponent("journal.json"))
        let resolutionJournal = ResolutionJournalStore(
            url: root.appendingPathComponent("resolution-journal.json")
        )
        let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedules.json"))
        let maintenance = QuarantineMaintenanceCoordinator(
            historyStore: history,
            scheduleStore: schedules,
            executor: executor,
            resolutionJournalStore: resolutionJournal
        )
        let coordinator = CleanupExecutionCoordinator(
            executor: executor,
            historyStore: history,
            journalStore: journal,
            resolutionJournalStore: resolutionJournal,
            scheduleStore: schedules,
            maintenanceCoordinator: maintenance,
            now: { now }
        )
        return CoordinatorFixture(
            root: root,
            now: now,
            candidate: candidate,
            plan: plan,
            quarantineRoot: quarantineRoot,
            fileSystem: fileSystem,
            history: history,
            journal: journal,
            resolutionJournal: resolutionJournal,
            schedules: schedules,
            coordinator: coordinator
        )
    }
}

private final class CoordinatorFixture {
    let root: URL
    let now: Date
    let candidate: CleanupCandidate
    let plan: CleanupPlan
    let quarantineRoot: URL
    let fileSystem: CoordinatorFixtureFileSystem
    let history: HistoryStore
    let journal: ExecutionJournalStore
    let resolutionJournal: ResolutionJournalStore
    let schedules: QuarantineScheduleStore
    let coordinator: CleanupExecutionCoordinator

    init(
        root: URL,
        now: Date,
        candidate: CleanupCandidate,
        plan: CleanupPlan,
        quarantineRoot: URL,
        fileSystem: CoordinatorFixtureFileSystem,
        history: HistoryStore,
        journal: ExecutionJournalStore,
        resolutionJournal: ResolutionJournalStore,
        schedules: QuarantineScheduleStore,
        coordinator: CleanupExecutionCoordinator
    ) {
        self.root = root
        self.now = now
        self.candidate = candidate
        self.plan = plan
        self.quarantineRoot = quarantineRoot
        self.fileSystem = fileSystem
        self.history = history
        self.journal = journal
        self.resolutionJournal = resolutionJournal
        self.schedules = schedules
        self.coordinator = coordinator
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor CoordinatorFixtureFileSystem: FileSystemAccess {
    private let source: URL
    private var entries: [URL: FileIdentity]
    private var writes: [String] = []

    init(source: URL, identity: FileIdentity) {
        self.source = source
        entries = [source: identity]
    }

    func identity(at url: URL) throws -> FileIdentity {
        guard let identity = entries[url] else { throw FileSystemError.missing(url) }
        return identity
    }

    func children(of url: URL) -> [URL] {
        []
    }

    func isReadable(_ url: URL) -> Bool {
        entries[url] != nil
    }

    func isWritable(_ url: URL) -> Bool {
        true
    }

    func fileExists(_ url: URL) -> Bool {
        entries[url] != nil
    }

    func move(_ source: URL, to destination: URL) throws {
        guard let identity = entries.removeValue(forKey: source) else {
            throw FileSystemError.missing(source)
        }
        entries[destination] = identity
        writes.append("move")
    }

    func createDirectory(_ url: URL) {
        writes.append("mkdir")
    }

    func removeEmptyDirectory(_ url: URL) {
        writes.append("rmdir")
    }

    func trash(_ url: URL) -> URL {
        writes.append("trash")
        return url
    }

    func mutations() -> [String] {
        writes
    }

    func clearMutations() {
        writes.removeAll()
    }

    func replaceSource(with destination: URL) {
        entries[destination] = entries.removeValue(forKey: source)
    }

    func removePermanently(_ url: URL) throws {
        guard entries.removeValue(forKey: url) != nil else {
            throw FileSystemError.missing(url)
        }
        writes.append("permanent-remove")
    }
}

private func coordinatorCandidate() -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: "/tmp/coordinated-cleanup"),
        displayName: "coordinated-cleanup",
        category: .cache,
        bytes: 10,
        risk: .safe,
        evidence: [Evidence(code: "fixture", summary: "fixture")],
        identity: FileIdentity(
            device: 1,
            inode: 2,
            size: 10,
            modificationTime: 3,
            kind: .file
        ),
        source: .general,
        lastAccessDate: nil,
        isActive: false
    )
}
