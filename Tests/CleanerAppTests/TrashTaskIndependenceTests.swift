import CleanerCore
import Combine
import Foundation
import XCTest
@testable import CleanerApp

final class TrashTaskIndependenceTests: XCTestCase {
    @MainActor
    func testReadOnlyFullScanCanBeginWhileTrashIsEmptying() async {
        let model = makeModel()
        defer { model.cancelScan() }
        XCTAssertTrue(model.beginTrashEmptying())

        model.continueScanWithCurrentPermissions()

        XCTAssertTrue(model.isScanRunning)
        XCTAssertTrue(model.trashEmptyingInProgress)
        XCTAssertFalse(model.canBeginTrashEmptying)
        XCTAssertFalse(model.canExecuteSelection)
        XCTAssertFalse(model.canExecuteUninstallBatch)
    }

    @MainActor
    func testFullScanEntryStillChecksPermissionsWhileTrashIsEmptying() async {
        let model = makeModel()
        defer { model.cancelScan() }
        XCTAssertTrue(model.beginTrashEmptying())

        model.startFullScan()

        XCTAssertTrue(model.checkingScanPermissions)
        for await checking in model.$checkingScanPermissions.values {
            if !checking { break }
        }
        XCTAssertFalse(model.checkingScanPermissions)
        XCTAssertTrue(model.trashEmptyingInProgress)
    }

    @MainActor
    func testModuleRefreshCanBeRequestedWhileTrashIsEmptying() async {
        let model = makeModel()
        defer { model.cancelScan() }
        XCTAssertTrue(model.beginTrashEmptying())

        model.refreshModule(.largeFiles)

        XCTAssertEqual(model.scanProgressByModule[.largeFiles]?.state, .waiting)
        XCTAssertTrue(model.trashEmptyingInProgress)
        XCTAssertFalse(model.canRunOneClickCleanup)
    }

    @MainActor
    func testBrowsingAndSelectionDoNotReleaseMutationGate() async {
        let model = makeModel()
        let candidate = model.systemReport!.generalCandidates[0]
        model.selectedIDs = [candidate.id]
        XCTAssertTrue(model.beginTrashEmptying())

        model.openScanResult(.general)
        model.toggle(candidate)

        XCTAssertEqual(model.selection, .systemCleanup)
        XCTAssertFalse(model.selectedIDs.contains(candidate.id))
        model.toggle(candidate)
        XCTAssertTrue(model.selectedIDs.contains(candidate.id))
        XCTAssertFalse(model.canExecuteSelection)
        XCTAssertFalse(model.canExecuteUninstallBatch)
        XCTAssertFalse(model.canBeginTrashEmptying)
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(),
            results: [.init(candidateID: candidate.id, originalURL: candidate.url,
                destinationURL: candidate.url.appendingPathExtension("retained"),
                disposition: .quarantined, status: .succeeded, bytes: candidate.bytes)], overallStatus: .completed)
        model.requestRestore(receipt)
        model.requestPermanentDeletion(receipt)
        XCTAssertNil(model.restoreConfirmationReceipt)
        XCTAssertNil(model.purgeConfirmationReceipt)
    }

    @MainActor
    private func makeModel() -> AppModel {
        AppModel.makeTrashEmptyingCheckModel(fixture: TrashEmptyingFixture())
    }
}
