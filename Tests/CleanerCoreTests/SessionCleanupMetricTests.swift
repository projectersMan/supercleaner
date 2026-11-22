import XCTest
@testable import CleanerCore

final class SessionCleanupMetricTests: XCTestCase {
    func testModuleTotalsEqualSessionAcrossMixedReceiptsAndRetries() {
        let sources: [CandidateSource] = [.general, .historicalApplicationResidue, .application,
            .diskAnalysis, .agentWorkspace, .localAIModels, .projectArtifacts]
        let candidates = sources.enumerated().map { candidate($0.offset, source: $0.element) }
        let results = candidates.enumerated().map { index, candidate in
            OperationResult(candidateID: candidate.id, originalURL: candidate.url, disposition: .trashed,
                            status: .succeeded, bytes: UInt64(index * 10))
        }
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: results)
        var summary = CleanupSessionSummary()
        summary.record(receipt, attemptedCandidates: candidates)
        summary.record(receipt, attemptedCandidates: candidates)
        XCTAssertEqual(summary.itemCount, 7)
        XCTAssertEqual(summary.bytes, 210)
        XCTAssertEqual(summary.completedByModule[.general], .init(itemCount: 2, bytes: 10))
        XCTAssertEqual(summary.completedByModule[.localAIModels], .init(itemCount: 1, bytes: 50))

        let failed = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [
            .init(candidateID: candidates[2].id, originalURL: candidates[2].url,
                  disposition: .failed, status: .failed, bytes: 9_999),
            .init(candidateID: candidates[3].id, originalURL: candidates[3].url,
                  disposition: .skipped, status: .skippedCancelled, bytes: 9_999)
        ])
        summary.record(failed, attemptedCandidates: candidates)
        let retry = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [
            .init(candidateID: candidates[3].id, originalURL: candidates[3].url,
                  disposition: .quarantined, status: .succeeded, bytes: 12)
        ])
        summary.record(retry, attemptedCandidates: candidates)
        XCTAssertEqual(summary.completedByModule[.largeFiles], .init(itemCount: 2, bytes: 42))
        XCTAssertEqual(summary.itemCount, 8)
        XCTAssertEqual(summary.bytes, 222)
        XCTAssertEqual(summary.completedByModule.values.reduce(0) { $0 + $1.itemCount }, summary.itemCount)
        XCTAssertEqual(summary.completedByModule.values.reduce(UInt64(0)) { $0 + $1.bytes }, summary.bytes)
    }

    private func candidate(_ index: Int, source: CandidateSource) -> CleanupCandidate {
        CleanupCandidate(url: URL(fileURLWithPath: "/tmp/metric-\(index)"), displayName: "metric",
            category: .log, bytes: 999, risk: .safe, evidence: [],
            identity: .init(device: 1, inode: UInt64(index), size: 999, modificationTime: 1, kind: .file),
            source: source, lastAccessDate: nil, isActive: false)
    }

    func testAccumulatesAllModulesWithoutDuplicatingReceiptsOrCountingFailures() {
        var summary = CleanupSessionSummary()
        for bytes in [UInt64(100), 200, 300, 400] {
            let item = candidate(Int(bytes), source: .general)
            let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [
                .init(candidateID: item.id, originalURL: item.url, disposition: .quarantined, status: .succeeded, bytes: bytes),
                .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/failure"), disposition: .failed, status: .failed, bytes: 10_000),
                .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/skip"), disposition: .skipped, status: .skippedIdentityChanged, bytes: 10_000)
            ])
            summary.record(receipt, attemptedCandidates: [item])
            summary.record(receipt, attemptedCandidates: [item])
        }
        XCTAssertEqual(summary.bytes, 1_000)
        XCTAssertEqual(summary.itemCount, 4)
        XCTAssertEqual(CleanupSessionSummary().bytes, 0)
    }
}
