import XCTest
@testable import CleanerCore

final class DeletionResultOrderingTests: XCTestCase {
    func testIncompleteFilesAndInstallationReceiptsPrecedeSuccessfulItems() {
        let firstSuccess = result("success-1", disposition: .trashed, status: .succeeded)
        let skipped = result("skipped", disposition: .skipped, status: .skippedProtected)
        let secondSuccess = result("success-2", disposition: .quarantined, status: .succeeded)
        let failed = result("failed", disposition: .failed, status: .failed)
        let receiptFailure = result("installer-receipt", disposition: .failed, status: .failed)
        let files = [firstSuccess, skipped, secondSuccess, failed]
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(),
            results: files, overallStatus: .partial, installationReceiptResults: [receiptFailure])
        let presentation = DeletionResultPresentation(receipt: receipt)
        XCTAssertEqual(presentation.orderedResults.map(\.id),
                       [skipped, failed, receiptFailure, firstSuccess, secondSuccess].map(\.id))
        XCTAssertEqual(presentation.deletedCount, 2)
        XCTAssertEqual(presentation.incompleteCount, 3)
        XCTAssertEqual(receipt.results, files, "Display order must not rewrite the execution record")
    }

    func testSuccessfulDispositionWithFailedStatusStillAppearsFirst() {
        let success = result("success", disposition: .trashed, status: .succeeded)
        let incomplete = result("incomplete", disposition: .trashed, status: .failed)
        let presentation = DeletionResultPresentation(results: [success, incomplete])
        XCTAssertEqual(presentation.orderedResults.map(\.id), [incomplete.id, success.id])
        XCTAssertEqual(presentation.deletedCount, 1)
        XCTAssertEqual(presentation.failedCount, 1)
    }

    private func result(_ name: String, disposition: OperationDisposition, status: OperationStatus) -> OperationResult {
        .init(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/fixture/\(name)"),
              disposition: disposition, status: status, bytes: 10)
    }
}
