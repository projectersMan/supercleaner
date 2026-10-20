import XCTest
@testable import CleanerCore

final class ReviewFocusStateTests: XCTestCase {
    func testInvisibleFocusMovesToFirstVisibleCandidate() {
        let first = UUID()
        let second = UUID()
        var state = ReviewFocusState(focusedCandidateID: UUID())

        state.reconcile(visibleIDs: [first, second])

        XCTAssertEqual(state.focusedCandidateID, first)
    }

    func testVisibleFocusIsPreserved() {
        let first = UUID()
        let second = UUID()
        var state = ReviewFocusState(focusedCandidateID: second)

        state.reconcile(visibleIDs: [first, second])

        XCTAssertEqual(state.focusedCandidateID, second)
    }

    func testHiddenRequestedFocusFallsBackToFirstVisibleCandidate() {
        let first = UUID()
        let second = UUID()
        var state = ReviewFocusState()

        state.focus(UUID(), visibleIDs: [first, second])

        XCTAssertEqual(state.focusedCandidateID, first)
    }

    func testEmptyVisibleListClearsFocus() {
        var state = ReviewFocusState(focusedCandidateID: UUID())

        state.reconcile(visibleIDs: [])

        XCTAssertNil(state.focusedCandidateID)
    }
}
