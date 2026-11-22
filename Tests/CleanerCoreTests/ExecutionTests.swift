import Foundation
import XCTest
@testable import CleanerCore

final class ExecutionTests: XCTestCase {
    func testStoppingStalledUninstallValidationReturnsWithoutWaitingForTheRead() async throws {
        let original = executionFixtureCandidate(path: "/tmp/association-a", inode: 2)
        let candidates = [original.url, URL(fileURLWithPath: "/tmp/association-b")].map { url in
            CleanupCandidate(url: url, displayName: "association", category: .applicationSupport, bytes: 1, risk: .review,
                evidence: [], identity: original.identity, source: .application, lastAccessDate: nil, isActive: false)
        }
        let plan = try PlanBuilder(ruleVersion: "rules-1").build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        let fileSystem = ExecutionFixtureFileSystem(url: original.url, identity: original.identity)
        let gate = StalledValidationGate()
        let release = Task {
            try? await Task.sleep(for: .seconds(1))
            await gate.release()
        }
        let executor = CleanupExecutor(fileSystem: fileSystem, quarantineRoot: URL(fileURLWithPath: "/tmp/quarantine"),
            currentRuleVersion: "rules-1", validateCandidate: { _ in await gate.read() })
        let operation = Task { await executor.execute(plan: plan) }
        await fulfillment(of: [gate.started], timeout: 1)
        operation.cancel()
        let receipt = await operation.value
        let releasedBeforeCompletion = await gate.released
        let calls = await gate.calls
        XCTAssertFalse(releasedBeforeCompletion, "A blocked read-only ownership check must not hold the uninstall window open")
        XCTAssertEqual(calls, 1, "A user stop must not begin another item's validation")
        XCTAssertFalse(receipt.results.contains { $0.status == .succeeded })
        await gate.release()
        release.cancel()
        _ = await release.value
        await Task.yield()
        let mutations = await fileSystem.mutations()
        XCTAssertTrue(mutations.isEmpty, "A late successful validation must never perform a move after the batch ended")
    }

    func testChangedIdentityIsSkippedWithoutMutation() async throws {
        let candidate = executionFixtureCandidate(path: "/tmp/item")
        let plan = try PlanBuilder(ruleVersion: "rules-1").build(candidates: [candidate], selectedIDs: [candidate.id], now: Date())
        let fileSystem = ExecutionFixtureFileSystem(url: candidate.url, identity: executionFixtureCandidate(path: "/tmp/item", inode: 99).identity)
        let executor = CleanupExecutor(fileSystem: fileSystem, pathPolicy: PathPolicy(homeDirectory: URL(fileURLWithPath: "/Users/tester")), quarantineRoot: URL(fileURLWithPath: "/tmp/quarantine"), currentRuleVersion: "rules-1")
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .skippedIdentityChanged)
        let mutations = await fileSystem.mutations()
        XCTAssertTrue(mutations.isEmpty)
    }

    func testPreparedBatchReusesValidationAndCoalescesGeneralActivityLookup() async throws {
        let first = executionFixtureCandidate(path: "/tmp/item-a", inode: 2)
        // This fixture returns one identity for all paths (two synthetic hard links).
        let second = executionFixtureCandidate(path: "/tmp/item-b", inode: 2)
        let plan = try PlanBuilder(ruleVersion: "rules-1").build(
            candidates: [first, second], selectedIDs: [first.id, second.id], now: Date()
        )
        let calls = ExecutionCallCounter()
        let fileSystem = ExecutionFixtureFileSystem(url: first.url, identity: first.identity)
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: URL(fileURLWithPath: "/Users/tester")),
            quarantineRoot: URL(fileURLWithPath: "/tmp/quarantine"),
            currentRuleVersion: "rules-1",
            isActive: { _ in await calls.increment("active"); return false },
            loadProtection: { await calls.increment("protection"); return ProtectionPolicy() },
            loadRuleVersion: { await calls.increment("rule-version"); return "rules-1" },
            validateCandidate: { _ in await calls.increment("serial-validation") },
            prepareValidationBatch: { candidates in
                await calls.increment("prepare")
                return CleanupValidationBatch(
                    ruleVersion: "rules-1",
                    results: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, .valid) }),
                    verifyRuleState: { await calls.increment("rule-state") }
                )
            }
        )

        _ = await executor.execute(plan: plan)
        let counts = await calls.snapshot()

        XCTAssertEqual(counts["prepare"], 1)
        XCTAssertEqual(counts["rule-state"], 2)
        XCTAssertEqual(counts["protection"], 2)
        XCTAssertEqual(counts["rule-version", default: 0], 0)
        XCTAssertEqual(counts["serial-validation", default: 0], 0)
        XCTAssertEqual(counts["active"], 1)
    }

    func testPreparedBatchRefusalPreventsMutation() async throws {
        let candidate = executionFixtureCandidate(path: "/tmp/item")
        let plan = try PlanBuilder(ruleVersion: "rules-1").build(candidates: [candidate], selectedIDs: [candidate.id], now: Date())
        let fileSystem = ExecutionFixtureFileSystem(url: candidate.url, identity: candidate.identity)
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: URL(fileURLWithPath: "/Users/tester")),
            quarantineRoot: URL(fileURLWithPath: "/tmp/quarantine"),
            currentRuleVersion: "rules-1",
            prepareValidationBatch: { candidates in
                CleanupValidationBatch(
                    ruleVersion: "rules-1",
                    results: [candidates[0].id: .refused("fixture refusal")],
                    verifyRuleState: {}
                )
            }
        )

        let receipt = await executor.execute(plan: plan)
        let mutations = await fileSystem.mutations()

        XCTAssertEqual(receipt.results.first?.status, .skippedProtected)
        XCTAssertTrue(mutations.isEmpty)
    }

    func testPreparedBatchRuleChangePreventsMutation() async throws {
        let candidate = executionFixtureCandidate(path: "/tmp/item")
        let plan = try PlanBuilder(ruleVersion: "rules-1").build(candidates: [candidate], selectedIDs: [candidate.id], now: Date())
        let fileSystem = ExecutionFixtureFileSystem(url: candidate.url, identity: candidate.identity)
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: URL(fileURLWithPath: "/Users/tester")),
            quarantineRoot: URL(fileURLWithPath: "/tmp/quarantine"),
            currentRuleVersion: "rules-1",
            prepareValidationBatch: { candidates in
                CleanupValidationBatch(
                    ruleVersion: "rules-1",
                    results: [candidates[0].id: .valid],
                    verifyRuleState: { throw RuleStoreError.interruptedCommit }
                )
            }
        )

        let receipt = await executor.execute(plan: plan)
        let mutations = await fileSystem.mutations()

        XCTAssertEqual(receipt.results.first?.status, .skippedProtected)
        XCTAssertTrue(mutations.isEmpty)
    }
}

private actor StalledValidationGate {
    nonisolated let started = XCTestExpectation(description: "Read-only validation started")
    private(set) var released = false
    private(set) var calls = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func read() async {
        calls += 1
        started.fulfill()
        if released { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        released = true
        let all = waiting; waiting.removeAll()
        all.forEach { $0.resume() }
    }
}

private actor ExecutionCallCounter {
    private var values: [String: Int] = [:]
    func increment(_ key: String) { values[key, default: 0] += 1 }
    func snapshot() -> [String: Int] { values }
}

private actor ExecutionFixtureFileSystem: FileSystemAccess {
    let url: URL
    let storedIdentity: FileIdentity
    var writes: [String] = []
    init(url: URL, identity: FileIdentity) { self.url = url; storedIdentity = identity }
    func identity(at url: URL) throws -> FileIdentity { storedIdentity }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { url == self.url }
    func move(_ source: URL, to destination: URL) { writes.append("move") }
    func createDirectory(_ url: URL) { writes.append("mkdir") }
    func removeEmptyDirectory(_ url: URL) { writes.append("rmdir") }
    func trash(_ url: URL) -> URL { writes.append("trash"); return url }
    func mutations() -> [String] { writes }
}
