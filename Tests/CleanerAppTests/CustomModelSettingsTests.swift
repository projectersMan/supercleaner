import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class CustomModelSettingsTests: XCTestCase {
    @MainActor
    func testSavedRootsReloadIndependentlyFromProjectSettings() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let home = project.appendingPathComponent("Tests/temporary/model-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let suite = "CustomModelSettingsTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let runtime = CleanupRuntime(home: home)
        let projects = try await runtime.projectRoots.save([home.appendingPathComponent("projects")])
        let model = AppModel(home: home, preferences: preferences, readRunningApplicationIDs: { [] },
            readDiskCapacity: { _ in .unavailable(2) })
        let roots = [ModelStorageRoot(provider: .whisper, url: home.appendingPathComponent("models"))]
        let saved = await model.saveModelScanRoots(roots)
        XCTAssertTrue(saved)
        XCTAssertNil(model.modelScanRootsError)
        let reopened = AppModel(home: home, preferences: preferences, readRunningApplicationIDs: { [] },
            readDiskCapacity: { _ in .unavailable(2) })
        await reopened.loadModelScanRoots()
        XCTAssertEqual(reopened.modelScanRoots.map(\.id), roots.map(\.id))
        let unchanged = try await runtime.projectRoots.roots()
        XCTAssertEqual(unchanged, projects)
    }

    @MainActor
    func testInvalidModelRootConfigurationRevokesSelectionAndDashboardPlan() async throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let home = project.appendingPathComponent("Tests/temporary/model-settings-" + UUID().uuidString)
        let configuration = home.appendingPathComponent("Library/Application Support/SuperCleaner/model-scan-roots.json")
        try FileManager.default.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let data = Data("{\"schemaVersion\":1}".utf8)
        try data.write(to: configuration)
        let suite = "CustomModelSettingsTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(home: home, preferences: preferences, readRunningApplicationIDs: { [] },
            readDiskCapacity: { _ in .unavailable(2) })
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        model.selection = .localAIModels
        let candidate = try XCTUnwrap(report.localAIModelInventory?.candidates.first)
        model.selectedIDs = [candidate.id]
        await model.loadModelScanRoots()
        XCTAssertNotNil(model.modelScanRootsError)
        XCTAssertTrue(model.modelScanRootsNeedRefresh)
        XCTAssertFalse(model.canExecuteSelection)
        XCTAssertNil(model.cleanupCenterSelectionSummary(for: .localAIModels))
        model.toggle(candidate)
        XCTAssertEqual(model.selectedIDs, [candidate.id])
        XCTAssertEqual(try Data(contentsOf: configuration), data, "Invalid configuration must remain inspectable")
    }

}
