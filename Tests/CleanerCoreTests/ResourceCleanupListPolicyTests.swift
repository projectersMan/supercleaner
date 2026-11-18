import Foundation
import XCTest
@testable import CleanerCore

final class ResourceCleanupListPolicyTests: XCTestCase {
    func testProjectScopesRemoveCleanableWithoutChangingModelScopes() {
        XCTAssertEqual(ResourceCleanupListScope.scopes(for: .projects), [.all, .protected, .selected])
        XCTAssertEqual(ResourceCleanupListScope.scopes(for: .localAIModels), [.all, .cleanable, .protected, .selected])
    }

    func testScopesIncludeManualResourcesButProtectActiveBlockedAndIncompleteItems() {
        let manual = candidate(path: "Models/Manual", bytes: 10, risk: .review, isActive: false, evidence: [])
        let active = candidate(path: "Models/Active", bytes: 20, risk: .review, isActive: true, evidence: [])
        let blocked = candidate(path: "Models/Blocked", bytes: 30, risk: .blocked, isActive: false, evidence: [])
        let incomplete = candidate(path: "Models/Incomplete", bytes: 40, risk: .review, isActive: false,
            evidence: [Evidence(code: "scan-incomplete-access", summary: "Unreadable")])
        let items = [manual, active, blocked, incomplete]
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .cleanable,
            sortOrder: .size, selectedIDs: []).map(\.id), [manual.id])
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .protected,
            sortOrder: .size, selectedIDs: []).map(\.id), [incomplete.id, blocked.id, active.id])
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .selected,
            sortOrder: .size, selectedIDs: [manual.id]).map(\.id), [manual.id])
    }

    func testVisibleGroupSelectionPreservesHiddenAndOtherDimensionChoices() {
        let visible = candidate(path: "Models/Visible", bytes: 10, risk: .review, isActive: false, evidence: [])
        let hidden = candidate(path: "Models/Hidden", bytes: 20, risk: .review, isActive: false, evidence: [])
        let active = candidate(path: "Models/VisibleActive", bytes: 30, risk: .review, isActive: true, evidence: [])
        let otherDimensionID = UUID()
        var selection = CleanupStrategySelectionState(strategy: .custom, generationID: UUID(),
            selectedIDs: [hidden.id, otherDimensionID], excludedBaseIDs: [])
        let items = ResourceCleanupListPolicy.visibleCandidates([visible, hidden, active], query: "Visible", scope: .all,
            sortOrder: .size, selectedIDs: selection.selectedIDs)
        let selectable = ResourceCleanupListPolicy.selectableCandidates(items)
        XCTAssertEqual(selection.selectionState(for: Set(selectable.map(\.id))), .none)
        selection.toggleCategory(candidates: selectable, baseEligibleIDs: [], includesManualOnly: true)
        XCTAssertEqual(selection.selectedIDs, [visible.id, hidden.id, otherDimensionID])
        XCTAssertEqual(selection.selectionState(for: Set(selectable.map(\.id))), .all)
        selection.toggleCategory(candidates: selectable, baseEligibleIDs: [], includesManualOnly: true)
        XCTAssertEqual(selection.selectedIDs, [hidden.id, otherDimensionID])
    }

    func testSearchFindsEvidenceAndSortsBySelectionSizeOrDirectory() {
        let alpha = candidate(path: "Alpha/small", bytes: 10, risk: .review, isActive: false,
            evidence: [Evidence(code: "project-root", summary: "Project Alpha", details: "/source/Alpha")])
        let beta = candidate(path: "Beta/large", bytes: 100, risk: .review, isActive: false, evidence: [])
        let items = [beta, alpha]
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "  SOURCE/alpha  ", scope: .all,
            sortOrder: .size, selectedIDs: []).map(\.id), [alpha.id])
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .all,
            sortOrder: .size, selectedIDs: [alpha.id]).map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .all,
            sortOrder: .selection, selectedIDs: [alpha.id]).map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(ResourceCleanupListPolicy.visibleCandidates(items, query: "", scope: .all,
            sortOrder: .directory, selectedIDs: []).map(\.id), [alpha.id, beta.id])
    }

    private func candidate(path: String, bytes: UInt64, risk: RiskLevel, isActive: Bool, evidence: [Evidence]) -> CleanupCandidate {
        CleanupCandidate(url: URL(fileURLWithPath: "/Tests/dashboard-compact-trash/\(path)"), displayName: path,
            category: .agentModelCache, bytes: bytes, risk: risk, evidence: evidence,
            identity: FileIdentity(device: 1, inode: bytes, size: bytes, modificationTime: 1, kind: .directory),
            source: .localAIModels, lastAccessDate: nil, isActive: isActive,
            defaultSelection: false, requiresExplicitSelection: true)
    }
}
