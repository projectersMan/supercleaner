import Foundation
import XCTest
@testable import CleanerCore

final class AgentAssetGroupingTests: XCTestCase {
    func testHierarchyPreservesProviderScopeAndResourceOwnership() {
        let codex = asset(provider: .codex, scope: .global, kind: .buildCache, eligibility: .recommended)
        let shared = asset(provider: .shared, scope: .shared, kind: .skill, eligibility: .protected)
        let groups = AgentAssetGrouping.group([shared, codex])

        XCTAssertEqual(groups.map(\.provider), [.codex, .shared])
        XCTAssertEqual(groups.flatMap(\.scopes).flatMap(\.resourceGroups).flatMap(\.assets).count, 2)
    }

    func testProtectedAssetsAreExcludedFromGroupSelection() {
        let protected = asset(provider: .shared, scope: .shared, kind: .skill, eligibility: .protected)
        let selected = asset(provider: .shared, scope: .shared, kind: .buildCache, eligibility: .recommended)
        let group = AgentAssetGrouping.group([protected, selected])[0].scopes[0].resourceGroups.first { $0.resourceKind == .buildCache }!

        XCTAssertEqual(AgentAssetGrouping.selectableIDs(in: group), [selected.id])
        XCTAssertFalse(AgentAssetGrouping.selectableIDs(in: group).contains(protected.id))
    }

    private func asset(provider: AgentProvider, scope: AgentScope, kind: AgentResourceKind, eligibility: AgentCleanupEligibility) -> AgentAssetRecord {
        let id = UUID()
        let candidate = CleanupCandidate(
            id: id,
            url: URL(fileURLWithPath: "/Users/tester/\(id.uuidString)"),
            displayName: kind.rawValue,
            category: kind == .skill ? .agentSkill : .developerCache,
            bytes: 1,
            risk: eligibility == .protected ? .blocked : .safe,
            evidence: [],
            identity: FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .directory),
            source: .agentWorkspace,
            lastAccessDate: nil,
            isActive: false
        )
        return AgentAssetRecord(candidate: candidate, provider: provider, scope: scope, resourceKind: kind, activity: .completed, cleanupEligibility: eligibility, cleanupUnitURL: candidate.url)
    }
}
