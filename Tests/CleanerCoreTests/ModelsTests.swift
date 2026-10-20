import Foundation
import XCTest
@testable import CleanerCore

final class ModelsTests: XCTestCase {
    func testRiskDefaults() {
        XCTAssertTrue(RiskLevel.safe.isSelectableByDefault)
        XCTAssertFalse(RiskLevel.review.isSelectableByDefault)
        XCTAssertFalse(RiskLevel.blocked.isSelectable)
    }

    func testCandidateRoundTripPreservesIdentity() throws {
        let identity = FileIdentity(
            device: 1,
            inode: 2,
            size: 3,
            modificationTime: 4,
            kind: .directory
        )
        let candidate = CleanupCandidate(
            id: UUID(uuidString: "D7111412-4DD2-47E8-9A30-BB1D9778552E")!,
            url: URL(fileURLWithPath: "/tmp/cache", isDirectory: true),
            displayName: "Build cache",
            category: .developerCache,
            bytes: 3,
            risk: .safe,
            evidence: [Evidence(code: "old-cache", summary: "Unused for 30 days")],
            identity: identity,
            source: .general,
            lastAccessDate: nil,
            isActive: false
        )

        let data = try JSONEncoder().encode(candidate)
        XCTAssertEqual(try JSONDecoder().decode(CleanupCandidate.self, from: data), candidate)
    }

    func testPlanSeparatesSelectedAndBlockedItems() {
        let safe = CleanupCandidate.fixture(path: "/tmp/a", risk: .safe)
        let blocked = CleanupCandidate.fixture(path: "/tmp/b", risk: .blocked)
        let plan = CleanupPlan(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 400),
            items: [PlanItem(candidate: safe, isSelected: true), PlanItem(candidate: blocked, isSelected: false)]
        )

        XCTAssertEqual(plan.selectedItems.map(\.candidate.id), [safe.id])
        XCTAssertEqual(plan.blockedItems.map(\.candidate.id), [blocked.id])
    }

    func testSelectionDefaultsMatchRiskAndBlockedCannotBeForced() {
        let safe = PlanItem(candidate: .fixture(path: "/tmp/safe", risk: .safe))
        let review = PlanItem(candidate: .fixture(path: "/tmp/review", risk: .review))
        let blocked = PlanItem(candidate: .fixture(path: "/tmp/blocked", risk: .blocked), isSelected: true)
        XCTAssertTrue(safe.isSelected)
        XCTAssertFalse(review.isSelected)
        XCTAssertFalse(blocked.isSelected)
    }
}

private extension CleanupCandidate {
    static func fixture(path: String, risk: RiskLevel) -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(),
            url: URL(fileURLWithPath: path),
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            category: .cache,
            bytes: 1,
            risk: risk,
            evidence: [],
            identity: FileIdentity(device: 1, inode: 2, size: 1, modificationTime: 3, kind: .file),
            source: .general,
            lastAccessDate: nil,
            isActive: false
        )
    }
}
