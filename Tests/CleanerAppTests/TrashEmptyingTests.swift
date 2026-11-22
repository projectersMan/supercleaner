import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class TrashEmptyingTests: XCTestCase {
    @MainActor
    func testSuccessfulEmptyingDisablesRepeatedRequests() async {
        let preferences = UserDefaults(suiteName: "TrashEmptyingTests.\(UUID().uuidString)")!
        let model = AppModel.makeTrashEmptyingCheckModel(fixture: TrashEmptyingFixture())
        let fixture = TrashEmptyingPresentationFixture(approved: true)
        let controller = TrashReminderController(preferences: preferences, confirmEmptyTrash: fixture.confirm,
            emptyTrash: {}, reportFailure: fixture.reportFailure)
        XCTAssertTrue(controller.canEmptyTrash(model: model))
        let success = await controller.requestEmptyTrash(model: model).value
        XCTAssertTrue(success)
        XCTAssertFalse(controller.canEmptyTrash(model: model))
        let duplicate = await controller.requestEmptyTrash(model: model).value
        XCTAssertFalse(duplicate)
        XCTAssertTrue(fixture.failures.isEmpty)
    }

    func testAlreadyEmptyTrashIsCheckedBeforeRequestingEmpty() throws {
        let script = FinderTrashEmptying.script
        let check = try XCTUnwrap(script.range(of: "if (count of items of trash) is 0"))
        let empty = try XCTUnwrap(script.range(of: "empty trash"))
        XCTAssertLessThan(check.lowerBound, empty.lowerBound)
    }

    func testFinderErrorAfterConcurrentEmptyingRequiresIndependentConfirmation() async throws {
        let runner = FinderScriptFixture(empty: true)
        try await FinderTrashEmptying.execute(using: { await runner.run($0) })
        let scripts = await runner.scripts
        XCTAssertEqual(scripts, [FinderTrashEmptying.script, FinderTrashEmptying.confirmationScript])
        XCTAssertFalse(FinderTrashEmptying.confirmationScript.contains("empty trash"))
    }

    func testFinderErrorWithRemainingItemsIsStillFailure() async {
        let runner = FinderScriptFixture(empty: false)
        let result = await Task { try await FinderTrashEmptying.execute(using: { await runner.run($0) }) }.result
        if case .success = result { XCTFail("A nonempty Trash must never be recorded as emptied") }
    }

    @MainActor
    func testNewZeroByteCleanupDuringEmptyingReenablesButton() async throws {
        let execution = TrashEmptyingFixture()
        let model = AppModel.makeTrashEmptyingCheckModel(fixture: execution)
        let presentation = TrashEmptyingPresentationFixture(approved: true)
        let preferences = UserDefaults(suiteName: "TrashEmptyingTests.\(UUID().uuidString)")!
        let controller = TrashReminderController(preferences: preferences, confirmEmptyTrash: presentation.confirm,
            emptyTrash: { try await execution.execute() }, reportFailure: presentation.reportFailure)
        let task = controller.requestEmptyTrash(model: model)
        await execution.waitUntilStarted()
        try model.checkTrashEmptyingExecutionGate(additionalBytes: 0)
        await execution.finish(.success(()))
        let success = await task.value
        XCTAssertTrue(success)
        XCTAssertTrue(controller.canEmptyTrash(model: model))
    }
}

private actor FinderScriptFixture {
    let empty: Bool
    private(set) var scripts: [String] = []
    init(empty: Bool) { self.empty = empty }
    func run(_ script: String) -> (status: Int32, stdout: Data, stderr: Data) {
        scripts.append(script)
        if scripts.count == 1 { return (1, Data(), Data("cancelled (-128)".utf8)) }
        return (0, Data((empty ? "SUPERCLEANER_TRASH_EMPTY_CONFIRMED" : "SUPERCLEANER_TRASH_NOT_EMPTY").utf8), Data())
    }
}
