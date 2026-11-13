import Foundation
import XCTest
@testable import CleanerCore

final class RunningApplicationSnapshotTests: XCTestCase {
    @MainActor func testWorkspacePropertiesAreReadOffTheMainThread() async {
        let observation = ThreadObservation()
        let identifiers = await RunningApplicationSnapshot.identifiers(read: {
            observation.record()
            return ["org.example.fixture"]
        })
        XCTAssertFalse(observation.wasMainThread)
        XCTAssertEqual(identifiers, ["org.example.fixture"])
    }
}

private final class ThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    func record() { lock.withLock { value = Thread.isMainThread } }
    var wasMainThread: Bool { lock.withLock { value } }
}
