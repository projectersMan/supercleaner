import CleanerCore
import Foundation
import XCTest

final class CleanupRecommendationPolicyTests: XCTestCase {
    func testDeepModeSelectsOnlyRebuildableInactiveCandidates() {
        let policy = CleanupRecommendationPolicy()
        let safe = candidate(category: .log, risk: .safe)
        let cache = candidate(category: .developerCache, risk: .review)
        let session = candidate(category: .agentSession, risk: .review)
        let active = candidate(category: .cache, risk: .review, active: true)
        let blocked = candidate(category: .credential, risk: .blocked)

        XCTAssertEqual(
            policy.selectedIDs(for: [safe, cache, session, active, blocked], mode: .deep, currentSelection: []),
            Set([safe.id, cache.id])
        )
    }

    func testCustomModeCannotPreserveBlockedSelection() {
        let policy = CleanupRecommendationPolicy()
        let retained = candidate(category: .agentSession, risk: .review)
        let blocked = candidate(category: .credential, risk: .blocked)

        XCTAssertEqual(
            policy.selectedIDs(for: [retained, blocked], mode: .custom, currentSelection: [retained.id, blocked.id]),
            Set([retained.id])
        )
    }

    func testDefaultSelectionMatchesRecommendedCleanupGroups() {
        let policy = CleanupRecommendationPolicy()
        let safe = selectedCandidate(category: .cache, risk: .safe)
        let review = selectedCandidate(category: .cache, risk: .review)
        let notDefault = selectedCandidate(category: .cache, risk: .safe, defaultSelection: false)
        let active = selectedCandidate(category: .cache, risk: .safe, active: true)
        let manual = selectedCandidate(category: .cache, risk: .safe, requiresExplicitSelection: true)
        let unassignedSystemReview = selectedCandidate(
            category: .applicationSupport,
            risk: .review,
            defaultSelection: false,
            hasApplication: false
        )
        let unassignedManual = selectedCandidate(
            category: .applicationSupport,
            risk: .review,
            requiresExplicitSelection: true,
            hasApplication: false
        )
        let unassignedActive = selectedCandidate(
            category: .applicationSupport,
            risk: .review,
            active: true,
            hasApplication: false
        )
        let unassignedBlocked = selectedCandidate(
            category: .credential,
            risk: .blocked,
            hasApplication: false
        )

        XCTAssertEqual(
            policy.defaultSelectedIDs(for: [safe, review, notDefault, active, manual, unassignedSystemReview, unassignedManual, unassignedActive, unassignedBlocked]),
            [safe.id, review.id, notDefault.id]
        )

        let candidates = [safe, review, notDefault, active, manual, unassignedSystemReview, unassignedManual, unassignedActive, unassignedBlocked]
        let breakdown = policy.breakdown(for: candidates)
        XCTAssertEqual(
            policy.defaultSelectedIDs(for: candidates),
            Set((breakdown.recommended + breakdown.deepClean).filter(\.risk.isSelectable).map(\.id))
        )
        XCTAssertTrue(policy.defaultSelectedIDs(for: candidates).isDisjoint(with: Set(breakdown.retained.map(\.id))))
    }

    private func candidate(category: CleanupCategory, risk: RiskLevel, active: Bool = false) -> CleanupCandidate {
        selectedCandidate(category: category, risk: risk, active: active, defaultSelection: nil)
    }

    private func selectedCandidate(
        category: CleanupCategory,
        risk: RiskLevel,
        active: Bool = false,
        defaultSelection: Bool? = true,
        requiresExplicitSelection: Bool? = false,
        hasApplication: Bool = true
    ) -> CleanupCandidate {
        CleanupCandidate(
            url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"),
            displayName: "Fixture",
            category: category,
            bytes: 1,
            risk: risk,
            evidence: [],
            identity: FileIdentity(device: 1, inode: UInt64.random(in: 1...UInt64.max), size: 1, modificationTime: 1, kind: .directory),
            source: .general,
            lastAccessDate: nil,
            isActive: active,
            defaultSelection: defaultSelection,
            requiresExplicitSelection: requiresExplicitSelection,
            cleanupApplication: hasApplication
                ? CleanupApplication(bundleIdentifier: "example.fixture", name: "Fixture App", kind: "Application cache")
                : nil
        )
    }
}
