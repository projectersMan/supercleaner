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

    private func candidate(category: CleanupCategory, risk: RiskLevel, active: Bool = false) -> CleanupCandidate {
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
            isActive: active
        )
    }
}
