import XCTest
@testable import CleanerCore

final class SessionCleanupMetricTests: XCTestCase {
    func testAccumulatesAllModulesWithoutDuplicatingReceiptsOrCountingFailures() {
        var summary = CleanupSessionSummary()
        for bytes in [UInt64(100), 200, 300, 400] {
            let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [
                .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/item"), disposition: .quarantined, status: .succeeded, bytes: bytes),
                .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/failure"), disposition: .failed, status: .failed, bytes: 10_000),
                .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/skip"), disposition: .skipped, status: .skippedIdentityChanged, bytes: 10_000)
            ])
            summary.record(receipt)
            summary.record(receipt)
        }
        XCTAssertEqual(summary.bytes, 1_000)
        XCTAssertEqual(summary.itemCount, 4)
        XCTAssertEqual(CleanupSessionSummary().bytes, 0)
    }
}
