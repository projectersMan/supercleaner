import Foundation
import XCTest
@testable import CleanerCore

final class ExecutionTests: XCTestCase {
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
        let second = executionFixtureCandidate(path: "/tmp/item-b", inode: 3)
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
