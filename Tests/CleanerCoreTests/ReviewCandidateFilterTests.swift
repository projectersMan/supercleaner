import Foundation
import XCTest
@testable import CleanerCore

final class ReviewCandidateFilterTests: XCTestCase {
    func testQueryMatchesNameCaseInsensitively() {
        let candidate = candidate(name: "Codex Cache", path: "/tmp/item", risk: .review, evidence: "cache")
        XCTAssertTrue(ReviewCandidateFilter(query: "codex").includes(candidate, selectedIDs: []))
    }

    func testRiskFilterExcludesOtherRisk() {
        let candidate = candidate(name: "Codex Skills", path: "/tmp/item", risk: .blocked, evidence: "knowledge")
        XCTAssertFalse(ReviewCandidateFilter(query: "codex", risks: [.review]).includes(candidate, selectedIDs: []))
    }

    func testEvidenceDetailsAreSearchable() {
        let candidate = candidate(name: "Item", path: "/tmp/item", risk: .review, evidence: "protected knowledge")
        XCTAssertTrue(ReviewCandidateFilter(query: "knowledge").includes(candidate, selectedIDs: []))
    }

    func testSelectedOnlyUsesSelectionWithoutChangingCandidate() {
        let candidate = candidate(name: "Item", path: "/tmp/item", risk: .review, evidence: "cache")
        let filter = ReviewCandidateFilter(selectedOnly: true)
        XCTAssertFalse(filter.includes(candidate, selectedIDs: []))
        XCTAssertTrue(filter.includes(candidate, selectedIDs: [candidate.id]))
    }

    private func candidate(name: String, path: String, risk: RiskLevel, evidence: String) -> CleanupCandidate {
        CleanupCandidate(
            url: URL(fileURLWithPath: path),
            displayName: name,
            category: .cache,
            bytes: 1,
            risk: risk,
            evidence: [Evidence(code: "fixture", summary: evidence, details: "detail \(evidence)")],
            identity: FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .file),
            source: .general,
            lastAccessDate: nil,
            isActive: false
        )
    }
}
