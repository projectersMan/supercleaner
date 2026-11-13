import Foundation
import XCTest
@testable import CleanerCore

final class OverlappingCleanupSelectionTests: XCTestCase {
    func test216SelectedEntriesBecomeEightExecutableRoots() throws {
        var candidates = [CleanupCandidate]()
        for root in 0..<8 {
            let path = "/tmp/cleanup-selection/root-\(root)"
            candidates.append(candidate(path, kind: .directory, bytes: 0))
            candidates += (0..<26).map { candidate(path + "/file-\($0)", kind: .file, bytes: 10) }
        }
        XCTAssertEqual(candidates.count, 216)
        let plan = try PlanBuilder().build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        XCTAssertEqual(plan.selectedItems.count, 8)
        XCTAssertEqual(plan.selectedBytes, 2_080)
        XCTAssertTrue(plan.selectedItems.allSatisfy { $0.candidate.identity.kind == .directory })
    }

    func testUnselectedParentNeverBroadensChildSelection() throws {
        let parent = candidate("/tmp/cleanup-selection/root", kind: .directory)
        let child = candidate("/tmp/cleanup-selection/root/child", kind: .file)
        let plan = try PlanBuilder().build(candidates: [parent, child], selectedIDs: [child.id])
        XCTAssertEqual(plan.selectedItems.map(\.id), [child.id])
    }

    func testCoveredBlockedEntryIsStillRejected() {
        let parent = candidate("/tmp/cleanup-selection/root", kind: .directory)
        let child = candidate("/tmp/cleanup-selection/root/child", kind: .file, risk: .blocked)
        XCTAssertThrowsError(try PlanBuilder().build(candidates: [parent, child], selectedIDs: [parent.id, child.id]))
    }

    func testSiblingPrefixAndSymbolicLinkDoNotCoverOtherEntries() throws {
        let parent = candidate("/tmp/cleanup-selection/root", kind: .directory)
        let sibling = candidate("/tmp/cleanup-selection/root-other/file", kind: .file)
        let link = candidate("/tmp/cleanup-selection/link", kind: .symbolicLink)
        let beneathLink = candidate("/tmp/cleanup-selection/link/file", kind: .file)
        let items = [parent, sibling, link, beneathLink]
        let plan = try PlanBuilder().build(candidates: items, selectedIDs: Set(items.map(\.id)))
        XCTAssertEqual(plan.selectedItems.count, 4)
    }

    func testNestedDirectoriesMoveOnceAndRestoreTheirContents() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library/Caches/fixture")
        let child = root.appendingPathComponent("nested/payload.bin")
        try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: child)
        let fileSystem = LocalFileSystem()
        var candidates = [CleanupCandidate]()
        for url in [child, root, child.deletingLastPathComponent()] {
            candidates.append(.init(url: url, displayName: url.lastPathComponent, category: .cache, bytes: 7,
                risk: .safe, evidence: [], identity: try await fileSystem.identity(at: url),
                source: .general, lastAccessDate: nil, isActive: false))
        }
        let display = CleanupSelection.executionCandidates(from: candidates)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        XCTAssertEqual(display.map(\.id), plan.selectedItems.map(\.id))
        XCTAssertEqual(display.count, 1)
        let executor = CleanupExecutor(fileSystem: fileSystem, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture")
        let progress = SelectionProgressCapture()
        let receipt = await executor.execute(plan: plan) { progress.append($0) }
        XCTAssertEqual(receipt.results.count, 1)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        XCTAssertEqual(Set(progress.values.map(\.total)), [1])
        XCTAssertEqual(progress.values.last?.completed, 1)
        XCTAssertEqual(DeletionResultPresentation(results: receipt.results).deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertEqual(try Data(contentsOf: child), Data("payload".utf8))
    }

    private func candidate(_ path: String, kind: FileIdentity.Kind, bytes: UInt64 = 10, risk: RiskLevel = .review) -> CleanupCandidate {
        .init(url: URL(fileURLWithPath: path), displayName: URL(fileURLWithPath: path).lastPathComponent,
            category: .agentSandbox, bytes: bytes, risk: risk, evidence: [],
            identity: .init(device: 1, inode: 1, size: bytes, modificationTime: 1, kind: kind),
            source: .agentWorkspace, lastAccessDate: nil, isActive: false)
    }
}

private final class SelectionProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [ExecutionProgress]()
    var values: [ExecutionProgress] { lock.withLock { storage } }
    func append(_ progress: ExecutionProgress) { lock.withLock { storage.append(progress) } }
}
