import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class DashboardModuleSummaryTests: XCTestCase {
    @MainActor
    func testLargeFileManualAndRecommendedSelectionsSharePageMetrics() throws {
        let model = makeModel()
        let base = try ResourceCleanupPresentationFixture.report()
        let recommended = largeFile("setup.dmg", recommended: true, bytes: 100)
        let manual = largeFile("video.mov", recommended: false, bytes: 200)
        let report = base.replacing(moduleResult: .init(generationID: base.generationID,
            status: .init(module: .largeFiles, state: .completed),
            payload: .largeFiles(base.diskUsageTree, [recommended, manual])))
        model.install(report)
        model.selectedIDs = [recommended.id]
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.kind, .recommended)
        model.selectedIDs.insert(manual.id)
        model.selection = .largeFiles
        XCTAssertEqual(model.selectedBytes, 300)
        model.selection = .cleanupCenter
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.kind, .mixed)
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.metrics, .init(itemCount: 2, bytes: 300))
        XCTAssertEqual(model.defaultCleanupSummary(for: .largeFiles), .init(itemCount: 1, bytes: 100))
        model.selectedIDs.remove(recommended.id)
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.kind, .manual)
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.metrics, .init(itemCount: 1, bytes: 200))
        model.showsDuplicateLargeFilesOnly = true
        XCTAssertNil(model.cleanupCenterSelectionSummary(for: .largeFiles))
        model.showsDuplicateLargeFilesOnly = false
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.metrics.itemCount, 1)
    }

    @MainActor
    func testUninstallSelectionUsesApplicationSummaryOutsideApplicationPage() throws {
        let model = makeModel()
        model.install(ApplicationPresentationFixture.report())
        let plan = try XCTUnwrap(model.applicationUninstallPlans.first)
        let item = try XCTUnwrap(plan.items.first)
        model.uninstallSelectedIDs = [item.id]
        model.selection = .applications
        let page = model.uninstallBatchSummary
        model.selection = .cleanupCenter
        let summary = try XCTUnwrap(model.cleanupCenterSelectionSummary(for: .applications))
        XCTAssertEqual(summary.kind, .manual)
        XCTAssertEqual(summary.metrics, .init(itemCount: page.itemCount, bytes: page.bytes))
        XCTAssertEqual(summary.metrics, .init(itemCount: 1, bytes: 1_000))
        XCTAssertNil(model.defaultCleanupSummary(for: .applications))
        model.uninstallSelectedIDs.removeAll()
        XCTAssertNil(model.cleanupCenterSelectionSummary(for: .applications))
    }

    @MainActor
    func testManualSelectionSurvivesNavigationAndClearingUpdatesDashboard() throws {
        let model = makeModel()
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        model.selection = .localAIModels
        let candidates = model.candidates(for: .localAIModels)
        model.selectedIDs = Set(candidates.map(\.id))
        let pageBytes = model.selectedBytes
        model.selection = .cleanupCenter
        let summary = try XCTUnwrap(model.cleanupCenterSelectionSummary(for: .localAIModels))
        XCTAssertEqual(summary.kind, .manual)
        XCTAssertEqual(summary.metrics, .init(itemCount: 2, bytes: pageBytes))
        XCTAssertEqual(summary.metrics.bytes, 300)
        XCTAssertNil(model.defaultCleanupSummary(for: .localAIModels))
        XCTAssertEqual(model.sessionCleanupSummary.itemCount, 0)
        model.selection = .localAIModels
        model.clearCurrentSelection()
        model.selection = .cleanupCenter
        XCTAssertNil(model.cleanupCenterSelectionSummary(for: .localAIModels))
    }

    @MainActor
    func testCleanupThenNewSelectionAndRescanPreserveModuleSessionTotals() throws {
        let model = makeModel()
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        let models = model.candidates(for: .localAIModels)
        let project = try XCTUnwrap(model.candidates(for: .projects).first)
        let receipt = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [
            .init(candidateID: models[0].id, originalURL: models[0].url,
                  disposition: .trashed, status: .succeeded, bytes: 80),
            .init(candidateID: project.id, originalURL: project.url,
                  disposition: .failed, status: .failed, bytes: 300)
        ])
        model.recordCompletedCleanup(receipt, attemptedCandidates: [models[0], project])
        model.recordCompletedCleanup(receipt, attemptedCandidates: [models[0], project])
        model.selectedIDs.insert(models[1].id)
        model.selection = .cleanupCenter
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .localAIModels)?.metrics, .init(itemCount: 1, bytes: 200))
        XCTAssertEqual(model.sessionCleanupSummary.completedByModule[.localAIModels], .init(itemCount: 1, bytes: 80))
        XCTAssertNil(model.sessionCleanupSummary.completedByModule[.projects])
        XCTAssertEqual(model.sessionCleanupSummary.itemCount, 1)
        XCTAssertEqual(model.sessionCleanupSummary.bytes, 80)
        model.install(try ResourceCleanupPresentationFixture.report())
        XCTAssertEqual(model.sessionCleanupSummary.completedByModule[.localAIModels], .init(itemCount: 1, bytes: 80))
        XCTAssertEqual(model.sessionCleanupSummary.completedByModule.values.reduce(0) { $0 + $1.itemCount }, model.sessionCleanupSummary.itemCount)
        XCTAssertEqual(model.sessionCleanupSummary.completedByModule.values.reduce(UInt64(0)) { $0 + $1.bytes }, model.sessionCleanupSummary.bytes)
    }

    @MainActor
    private func makeModel() -> AppModel {
        let suite = "DashboardModuleSummaryTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
        return AppModel(home: ResourceCleanupPresentationFixture.home, preferences: preferences,
            readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) })
    }

    private func largeFile(_ name: String, recommended: Bool, bytes: UInt64) -> CleanupCandidate {
        CleanupCandidate(url: ResourceCleanupPresentationFixture.home.appendingPathComponent("Downloads/" + name),
            displayName: name, category: .largeFile, bytes: bytes, risk: .review,
            evidence: recommended ? [.init(code: "installer-type", summary: "DMG")] : [],
            identity: .init(device: 1, inode: bytes, size: bytes, modificationTime: 1, kind: .file),
            source: .diskAnalysis, lastAccessDate: nil, isActive: false, defaultSelection: recommended)
    }
}
