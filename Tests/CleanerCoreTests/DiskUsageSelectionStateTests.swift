import Foundation
import XCTest
@testable import CleanerCore

final class DiskUsageSelectionStateTests: XCTestCase {
    func testDirectoriesCannotBecomeSelected() {
        var state = DiskUsageSelectionState()
        state.toggle(node(kind: .directory))
        XCTAssertTrue(state.selectedFileURLs.isEmpty)
    }

    func testReadableConcreteFileCanBecomeSelected() {
        let file = node(kind: .file)
        var state = DiskUsageSelectionState()
        state.toggle(file)
        XCTAssertEqual(state.selectedFileURLs, [file.url])
    }

    private func node(kind: FileIdentity.Kind) -> DiskUsageNode {
        DiskUsageNode(
            url: URL(fileURLWithPath: "/Users/tester/Downloads/item"),
            kind: kind,
            ownBytes: 1,
            recursiveBytes: 1,
            childCount: 0,
            modifiedAt: Date(timeIntervalSince1970: 1),
            isReadable: true,
            children: .loaded([])
        )
    }
}
