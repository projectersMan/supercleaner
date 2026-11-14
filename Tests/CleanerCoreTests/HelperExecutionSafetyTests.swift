import Foundation
import XCTest
@testable import CleanerCore

final class HelperExecutionSafetyTests: XCTestCase {
    func testRestartedInputMethodCannotReachPrivilegedMove() async throws {
        let source = URL(fileURLWithPath: "/Library/Input Methods/Fixture.app")
        let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
        let candidate = CleanupCandidate(url: source, displayName: "Fixture", category: .application, bytes: 3,
            risk: .review, evidence: [], identity: identity, source: .application, lastAccessDate: nil, isActive: false)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
        let operations = HelperSafetyFileSystem(source: source, identity: identity)
        let executor = CleanupExecutor(fileSystem: operations,
            quarantineRoot: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("application-uninstall-eligibility/Quarantine"),
            currentRuleVersion: "fixture", privilegedApplications: operations,
            finalCandidateCheck: { _ in throw ApplicationExecutionRejection.ownershipChanged })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.map(\.status), [.skippedProtected])
        let sourceRemains = await operations.fileExists(source)
        XCTAssertTrue(sourceRemains, "a final runtime refusal must leave the application in place on the Helper path")
    }
}

private actor HelperSafetyFileSystem: FileSystemAccess, PrivilegedApplicationOperations {
    private var entries: [URL: FileIdentity]
    init(source: URL, identity: FileIdentity) { entries = [source: identity] }
    func identity(at url: URL) throws -> FileIdentity {
        guard let identity = entries[url] else { throw FileSystemError.missing(url) }
        return identity
    }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func createDirectory(_ url: URL) { }
    func removeEmptyDirectory(_ url: URL) { }
    func trash(_ url: URL) -> URL { url }
    func move(_ source: URL, to destination: URL) throws {
        let identity = try identity(at: source)
        entries.removeValue(forKey: source)
        entries[destination] = identity
    }
    func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) throws -> Bool {
        try move(candidate.url, to: destination)
        return true
    }
    func restore(source: URL, destination: URL, planID: UUID) throws -> Bool {
        try move(source, to: destination)
        return true
    }
    func purge(source: URL, planID: UUID) -> Bool {
        entries.removeValue(forKey: source)
        return true
    }
}
