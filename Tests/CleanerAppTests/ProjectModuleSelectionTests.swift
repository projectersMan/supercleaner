import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class ProjectModuleSelectionTests: XCTestCase {
    @MainActor
    func testActualProgressivePublicationPreservesProjectSelection() throws {
        try AppModel.checkNavigationPresentation()
    }

    @MainActor
    func testLateAgentPublicationPreservesProjectRowsTotalsAndDefaultSelection() throws {
        let suite = "ProjectModuleSelectionTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(home: ResourceCleanupPresentationFixture.home, preferences: preferences,
            readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) })
        let project = try ResourceCleanupPresentationFixture.report()
        model.install(project)
        model.selection = .projects
        let selected = model.selectedIDs
        let rows = model.visibleCandidates(for: .projects).map(\.id)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(model.cleanupCenterSelection?.bytes, 700)
        model.install(try reportWithAgentOverlap(project))
        XCTAssertEqual(model.visibleCandidates(for: .projects).map(\.id), rows)
        XCTAssertEqual(model.selectedIDs, selected)
        XCTAssertEqual(model.cleanupCenterSelection?.bytes, 700)
        XCTAssertEqual(model.selectedBytes, 700)
    }

    @MainActor
    func testLateAgentPublicationDoesNotReapplyManuallyDeselectedProjectItems() throws {
        let suite = "ProjectModuleSelectionTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(home: ResourceCleanupPresentationFixture.home, preferences: preferences,
            readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) })
        let project = try ResourceCleanupPresentationFixture.report()
        model.install(project)
        model.selection = .projects
        let item = try XCTUnwrap(project.projectScanReport?.artifacts.first?.candidate)
        model.toggle(item)
        let selected = model.selectedIDs
        XCTAssertFalse(selected.contains(item.id))
        let expected = UInt64(700) - item.bytes
        model.install(try reportWithAgentOverlap(project))
        XCTAssertEqual(model.visibleCandidates(for: .projects).count, 2)
        XCTAssertEqual(model.selectedIDs, selected)
        XCTAssertEqual(model.cleanupCenterSelection?.bytes, expected)
        XCTAssertEqual(model.selectedBytes, expected)
    }

    private func reportWithAgentOverlap(_ report: SystemScanReport) throws -> SystemScanReport {
        let projects = try XCTUnwrap(report.projectScanReport).artifacts.map(\.candidate)
        let assets = projects.map { candidate in
            let duplicate = CleanupCandidate(url: candidate.url, displayName: candidate.displayName, category: .agentWorktree,
                bytes: candidate.bytes, risk: .blocked, evidence: [], identity: candidate.identity, source: .agentWorkspace,
                lastAccessDate: nil, isActive: false, defaultSelection: false)
            return AgentAssetRecord(candidate: duplicate, provider: .codex, scope: .project, resourceKind: .gitWorktree,
                activity: .unknown, cleanupEligibility: .protected, cleanupUnitURL: duplicate.url)
        }
        return report.replacing(moduleResult: .init(generationID: report.generationID,
            status: .init(module: .agentEnvironment, state: .completed), payload: .agentEnvironment(.init(assets: assets, reachedBudget: false))))
    }
}
