import Foundation
import XCTest
@testable import CleanerCore

final class CleanupStrategySelectionStateTests: XCTestCase {
    func testExcludingRecommendedItemKeepsRecommendedStrategy() {
        let candidate = makeCandidate(risk: .safe)
        var state = CleanupStrategySelectionState(
            strategy: .smart,
            generationID: UUID(),
            selectedIDs: [candidate.id],
            excludedBaseIDs: []
        )

        state.toggle(candidate, baseEligibleIDs: [candidate.id])

        XCTAssertEqual(state.strategy, .smart)
        XCTAssertTrue(state.selectedIDs.isEmpty)
        XCTAssertEqual(state.excludedBaseIDs, [candidate.id])
        XCTAssertTrue(state.isAdjusted)
    }

    func testBlockedItemCannotEnterSelection() {
        let blocked = makeCandidate(risk: .blocked)
        var state = CleanupStrategySelectionState(
            strategy: .custom,
            generationID: UUID(),
            selectedIDs: [],
            excludedBaseIDs: []
        )

        state.toggle(blocked, baseEligibleIDs: [])

        XCTAssertFalse(state.selectedIDs.contains(blocked.id))
    }

    private func makeCandidate(risk: RiskLevel) -> CleanupCandidate {
        CleanupCandidate(
            url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"),
            displayName: "Fixture",
            category: .cache,
            bytes: 1,
            risk: risk,
            evidence: [],
            identity: FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .file),
            source: .general,
            lastAccessDate: nil,
            isActive: false
        )
    }
}
