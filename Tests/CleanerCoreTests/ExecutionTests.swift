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
        XCTAssertTrue(await fileSystem.mutations().isEmpty)
    }
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
