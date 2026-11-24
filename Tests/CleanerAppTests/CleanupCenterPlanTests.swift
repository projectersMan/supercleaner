import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class CleanupCenterPlanTests: XCTestCase {
    @MainActor
    func testNewPreferencesPreselectProjectsAndExplicitOptOutPersists() throws {
        let (model, preferences) = makeModel()
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        XCTAssertTrue(model.preselectProjectArtifacts)
        XCTAssertEqual(model.selectedIDs, Set(try XCTUnwrap(report.projectScanReport).artifacts.map(\.id)))
        preferences.set(false, forKey: "projects.preselectArtifacts")
        let reopened = AppModel(home: FileManager.default.temporaryDirectory, preferences: preferences,
            readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) })
        reopened.install(report)
        XCTAssertFalse(reopened.preselectProjectArtifacts)
        XCTAssertTrue(reopened.selectedIDs.isEmpty)
    }

    @MainActor
    func testCombinedPlanIncludesManualModelsApplicationsAndRecommendedLargeFiles() throws {
        let (model, _) = makeModel()
        let base = try ResourceCleanupPresentationFixture.report()
        let large = [largeFile("setup.dmg", bytes: 100, recommended: true),
            largeFile("movie.mov", bytes: 200, recommended: false)]
        let report = base.replacing(moduleResult: .init(generationID: base.generationID,
            status: .init(module: .largeFiles, state: .completed), payload: .largeFiles(base.diskUsageTree, large)))
            .replacing(moduleResult: .init(generationID: base.generationID,
                status: .init(module: .applications, state: .completed),
                payload: .applications(ApplicationPresentationFixture.report().applicationUninstallInventory)))
        model.install(report)
        model.selectedIDs = Set(report.generalCandidates.map(\.id) + large.map(\.id)
            + (report.localAIModelInventory?.candidates.map(\.id) ?? [])
            + (report.projectScanReport?.artifacts.map(\.id) ?? []))
        let application = try XCTUnwrap(model.applicationUninstallPlans.first?.items.first)
        model.uninstallSelectedIDs = [application.id]
        model.resourceReviewFilters[.localAIModels]!.query = "hidden-by-search"
        model.showsDuplicateLargeFilesOnly = true
        model.selection = .cleanupCenter

        let selection = try XCTUnwrap(model.cleanupCenterSelection)
        let plan = try selection.buildPlan(using: PlanBuilder())
        XCTAssertEqual(selection.candidates.count, 9)
        XCTAssertEqual(selection.bytes, 3_400)
        XCTAssertEqual(plan.selectedBytes, selection.bytes)
        XCTAssertEqual(Set(plan.selectedItems.map(\.id)), Set(selection.candidates.map(\.id)))
        XCTAssertEqual(selection.localAIModels.count, 2)
        XCTAssertEqual(selection.applicationUninstall.map(\.id), [application.id])
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .largeFiles)?.kind, .mixed)
        XCTAssertEqual(model.defaultCleanupSelection?.largeFiles.map(\.id), [large[0].id])
        XCTAssertTrue(model.canRunOneClickCleanup)

        model.uninstallSelectedIDs.removeAll()
        XCTAssertTrue(model.cleanupCenterSelection?.applicationUninstall.isEmpty == true)
        model.selectedIDs.removeAll()
        XCTAssertFalse(model.canRunOneClickCleanup)
        XCTAssertEqual(model.cleanupCenterSelection?.bytes, 0)
    }

    @MainActor
    func testManualOnlySelectionEnablesCombinedCleanupWithoutBecomingRecommended() throws {
        let (model, _) = makeModel()
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        let models = try XCTUnwrap(report.localAIModelInventory).candidates
        model.selectedIDs = Set(models.map(\.id))
        XCTAssertTrue(model.defaultCleanupSelection?.candidates.isEmpty == true)
        XCTAssertEqual(model.cleanupCenterSelectionSummary(for: .localAIModels)?.kind, .manual)
        XCTAssertEqual(model.cleanupCenterSelection?.bytes, 300)
        XCTAssertTrue(model.canRunOneClickCleanup)
    }

    @MainActor
    func testCombinedPlanCountsSelectedParentOnceAcrossModules() throws {
        let (model, _) = makeModel()
        let base = try ResourceCleanupPresentationFixture.report()
        let project = try XCTUnwrap(base.projectScanReport?.artifacts.first?.candidate)
        let nested = largeFile("nested.bin", bytes: 50, recommended: false,
            url: project.url.appendingPathComponent("nested.bin"))
        let report = base.replacing(moduleResult: .init(generationID: base.generationID,
            status: .init(module: .largeFiles, state: .completed), payload: .largeFiles(base.diskUsageTree, [nested])))
        model.install(report)
        model.selectedIDs = [project.id, nested.id]
        let selection = try XCTUnwrap(model.cleanupCenterSelection)
        let plan = try selection.buildPlan(using: PlanBuilder())
        XCTAssertEqual(selection.candidates.map(\.id), [project.id])
        XCTAssertEqual(selection.bytes, project.bytes)
        XCTAssertEqual(plan.selectedItems.map(\.id), [project.id])
        XCTAssertEqual(plan.selectedBytes, selection.bytes)
    }

    @MainActor
    func testRecommendedSelectionIncludesVerifiedCachesInTheExecutionPlan() throws {
        let (model, _) = makeModel()
        let base = try ResourceCleanupPresentationFixture.report()
        let home = ResourceCleanupPresentationFixture.home
        let log = CleanupCandidate(url: home.appendingPathComponent("Library/Logs/old.log"), displayName: "Old log",
            category: .log, bytes: 10, risk: .safe, evidence: [],
            identity: .init(device: 1, inode: 101, size: 10, modificationTime: 1, kind: .file),
            source: .general, lastAccessDate: nil, isActive: false, defaultSelection: true)
        let cache = CleanupCandidate(url: home.appendingPathComponent(".npm/_cacache"), displayName: "Download cache",
            category: .developerCache, bytes: 20, risk: .review,
            evidence: [.init(code: "verified-cleanup-scope", summary: "fixture.download"),
                       .init(code: "verified-regenerable-cache", summary: "fixture.download")],
            identity: .init(device: 1, inode: 102, size: 20, modificationTime: 1, kind: .directory),
            source: .general, lastAccessDate: nil, isActive: true, ruleID: "fixture.download", defaultSelection: false)
        let data = CleanupCandidate(url: home.appendingPathComponent("Library/Application Support/old.user"), displayName: "User data",
            category: .applicationSupport, bytes: 30, risk: .review, evidence: [],
            identity: .init(device: 1, inode: 103, size: 30, modificationTime: 1, kind: .directory),
            source: .historicalApplicationResidue, lastAccessDate: nil, isActive: false,
            defaultSelection: false, requiresExplicitSelection: true)
        model.install(SystemScanReport(metadata: base.metadata, modules: base.modules,
            generalCandidates: [log, cache, data], applicationInventory: base.applicationInventory,
            diskUsageTree: base.diskUsageTree, largeFileCandidates: [], agentAssets: []))
        model.selection = .systemCleanup

        model.setCleanupMode(.deep)
        XCTAssertEqual(model.selectedIDs, [log.id, cache.id])
        model.setCleanupMode(.smart)
        XCTAssertEqual(model.selectedIDs, [log.id, cache.id])
        XCTAssertEqual(Set(model.defaultCleanupSelection?.systemCleanup.map(\.id) ?? []), [log.id, cache.id])
        model.toggle(cache)
        XCTAssertEqual(model.selectedIDs, [log.id])
        model.toggle(cache)

        let selection = try XCTUnwrap(model.cleanupCenterSelection)
        let plan = try selection.buildPlan(using: PlanBuilder())
        XCTAssertEqual(Set(selection.systemCleanup.map(\.id)), [log.id, cache.id])
        XCTAssertEqual(Set(plan.selectedItems.map(\.id)), [log.id, cache.id])
        XCTAssertEqual(plan.selectedBytes, 30)
        XCTAssertFalse(model.selectedIDs.contains(data.id))
    }

    @MainActor
    func testSystemGroupCannotGrantIndividualConsentToUnknownOrHistoricalData() throws {
        let (model, _) = makeModel()
        let base = try ResourceCleanupPresentationFixture.report()
        let items = [manualSystemCandidate("UnknownCache", category: .cache, source: .general),
            manualSystemCandidate("HistoricalData", category: .applicationSupport, source: .historicalApplicationResidue),
            manualSystemCandidate("SharedResidue", category: .cache, source: .historicalApplicationResidue)]
        model.install(SystemScanReport(metadata: base.metadata, modules: base.modules,
            generalCandidates: items, applicationInventory: base.applicationInventory,
            diskUsageTree: base.diskUsageTree, largeFileCandidates: [], agentAssets: []))
        model.selection = .systemCleanup
        let group = try XCTUnwrap(SystemCleanupApplicationGroup.groups(items).first)
        XCTAssertEqual(group.id, "system-and-unassigned")

        model.toggleCleanupCategory(group.candidates, includesManualOnly: true)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.cleanupSelectionState(for: group.candidates, includesManualOnly: true), .none)

        for item in items { model.toggle(item) }
        XCTAssertEqual(model.selectedIDs, Set(items.map(\.id)))
        XCTAssertEqual(Set(try XCTUnwrap(model.cleanupCenterSelection).systemCleanup.map(\.id)), Set(items.map(\.id)))
        model.clearCurrentSelection()
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(model.cleanupCenterSelection).systemCleanup.isEmpty)
    }

    private func manualSystemCandidate(_ name: String, category: CleanupCategory, source: CandidateSource) -> CleanupCandidate {
        CleanupCandidate(url: ResourceCleanupPresentationFixture.home.appendingPathComponent(name), displayName: name,
            category: category, bytes: 10, risk: .review, evidence: [],
            identity: .init(device: 1, inode: UInt64(name.count), size: 10, modificationTime: 1, kind: .directory),
            source: source, lastAccessDate: nil, isActive: false, defaultSelection: false, requiresExplicitSelection: true)
    }

    @MainActor
    private func makeModel() -> (AppModel, UserDefaults) {
        let suite = "CleanupCenterPlanTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (AppModel(home: ResourceCleanupPresentationFixture.home, preferences: preferences,
            readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) }), preferences)
    }

    private func largeFile(_ name: String, bytes: UInt64, recommended: Bool, url: URL? = nil) -> CleanupCandidate {
        CleanupCandidate(url: url ?? ResourceCleanupPresentationFixture.home.appendingPathComponent("Downloads/" + name),
            displayName: name, category: .largeFile, bytes: bytes, risk: .review,
            evidence: recommended ? [.init(code: "installer-type", summary: "DMG")] : [],
            identity: .init(device: 1, inode: bytes, size: bytes, modificationTime: 1, kind: .file),
            source: .diskAnalysis, lastAccessDate: nil, isActive: false, defaultSelection: recommended)
    }
}
