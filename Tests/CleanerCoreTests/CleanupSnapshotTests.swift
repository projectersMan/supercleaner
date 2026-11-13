import Foundation
import XCTest
@testable import CleanerCore

final class CleanupSnapshotTests: XCTestCase {
    func testRemovalPreservesCandidatePrecedenceOrderAndSharedCoverageRoots() {
        let first = candidate("/tmp/cleanup-snapshot/a", source: .general)
        let alias = candidate(first.url.path, source: .diskAnalysis)
        let removed = candidate("/tmp/cleanup-snapshot/b", source: .general)
        let last = candidate("/tmp/cleanup-snapshot/c", source: .diskAnalysis)
        let applications = ApplicationInventory(applications: [], coverage: .init(scannedRoots: [removed.url]), scannedAt: Date())
        let original = report(general: [first, removed], large: [alias, last], applications: applications)
        let updated = original.reconcilingCleanup([success(removed)])
        XCTAssertEqual(updated.candidates.map(\.id), [first.id, last.id])
        XCTAssertNil(updated.candidate(id: removed.id))
        XCTAssertNil(updated.candidate(id: alias.id), "the original path winner must remain the indexed candidate")
        XCTAssertEqual(updated.candidate(id: first.id), first)
        XCTAssertTrue(updated.coverage.scannedRoots.contains(removed.url), "a root still covered by another module must stay")

        let withoutSharedCoverage = report(general: [first, removed], large: [])
            .reconcilingCleanup([success(removed)])
        XCTAssertEqual(withoutSharedCoverage.coverage.scannedRoots, [first.url])
        let dotted = candidate("/tmp/cleanup-snapshot/sub/../dotted", source: .general)
        XCTAssertTrue(report(general: [dotted], large: []).reconcilingCleanup([success(dotted)]).coverage.scannedRoots.isEmpty)
        XCTAssertEqual(updated.metadata, original.metadata)
        XCTAssertEqual(updated.modules, original.modules)
    }

    func testStatusChangesRefreshCoverageWithoutChangingTheCandidateIndex() {
        let item = candidate("/tmp/cleanup-snapshot/item", source: .general)
        let original = report(general: [item], large: [])
        let denied = URL(fileURLWithPath: "/tmp/cleanup-snapshot/denied")
        let limitation = ScanLimitation(title: "denied", path: denied, impact: "partial", recovery: "retry", reason: .access)
        let updated = original.updatingModuleStatuses([.general: .init(module: .general, state: .limited, limitations: [limitation])])
        XCTAssertEqual(updated.candidates, original.candidates)
        XCTAssertEqual(updated.candidate(id: item.id), item)
        XCTAssertEqual(updated.coverage.unavailableRoots, [denied])
        XCTAssertEqual(updated.coverage.scannedRoots, original.coverage.scannedRoots)
    }

    func testRemovalOfRetainedCopyInvalidatesProofInEveryIndex() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("cleanup-proof-\(UUID())").resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let target = root.appendingPathComponent("target"), retained = root.appendingPathComponent("retained")
        try Data([1, 2, 3]).write(to: target)
        try Data([1, 2, 3]).write(to: retained)
        let proof = LargeFileCleanupProof(reason: .identicalCopy,
            target: try XCTUnwrap(LargeFileContentSnapshot.at(target)), retained: [try XCTUnwrap(LargeFileContentSnapshot.at(retained))])
        let item = CleanupCandidate(url: target, displayName: "target", category: .largeFile, bytes: 3, risk: .review,
            evidence: [], identity: try await LocalFileSystem().identity(at: target), source: .diskAnalysis,
            lastAccessDate: nil, isActive: false, largeFileProof: proof)
        let removal = OperationResult(candidateID: UUID(), originalURL: retained, disposition: .quarantined, bytes: 3)
        let updated = report(general: [], large: [item]).reconcilingCleanup([removal])
        XCTAssertNil(updated.largeFileCandidates.first?.largeFileProof)
        XCTAssertNil(updated.candidates.first?.largeFileProof)
        XCTAssertNil(updated.candidate(id: item.id)?.largeFileProof)
    }

    func testRemovalIndexKeepsPathBoundariesAndLexicalNormalization() {
        let index = CleanupPathIndex(paths: ["/tmp/removed/cache"])
        XCTAssertTrue(index.contains(URL(fileURLWithPath: "/tmp/removed/cache")))
        XCTAssertTrue(index.contains(URL(fileURLWithPath: "/tmp/removed/cache/child")))
        XCTAssertTrue(index.contains(URL(fileURLWithPath: "/tmp/removed/other/../cache/child")))
        XCTAssertFalse(index.contains(URL(fileURLWithPath: "/tmp/removed/cache-other/child")))
        XCTAssertFalse(index.contains(URL(fileURLWithPath: "/tmp/removed/cache/../keep")))
        XCTAssertTrue(CleanupPathIndex(paths: ["/"]).contains(URL(fileURLWithPath: "/any/path")))
    }

    private func candidate(_ path: String, source: CandidateSource) -> CleanupCandidate {
        .init(url: URL(fileURLWithPath: path), displayName: "item", category: source == .general ? .log : .largeFile,
            bytes: 1, risk: .review, evidence: [], identity: .init(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .file),
            source: source, lastAccessDate: nil, isActive: false)
    }
    private func success(_ item: CleanupCandidate) -> OperationResult {
        .init(candidateID: item.id, originalURL: item.url, disposition: .quarantined, bytes: item.bytes)
    }
    private func report(general: [CleanupCandidate], large: [CleanupCandidate], applications: ApplicationInventory? = nil) -> SystemScanReport {
        .init(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "test"),
            modules: [.general: .init(module: .general, state: .completed)], generalCandidates: general,
            applicationInventory: applications ?? .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: large, agentAssets: [])
    }
}
