import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class ProjectProtectionTests: XCTestCase {
    @MainActor
    func testProtectingProjectRootRevokesHiddenArtifactsAndPersists() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ProjectProtectionTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: home)
        }
        let model = AppModel(home: home, preferences: preferences, readRunningApplicationIDs: { [] },
            readDiskCapacity: { _ in .unavailable(2) })
        let report = try ResourceCleanupPresentationFixture.report()
        let projects = try XCTUnwrap(report.projectScanReport).artifacts.map(\.candidate)
        let projectURL = projects[0].url.deletingLastPathComponent()
        let unrelated = try XCTUnwrap(report.localAIModelInventory?.candidates.first)
        model.install(report)
        model.selection = .projects
        model.resourceReviewFilters[.projects]!.query = projects[0].displayName
        model.selectedIDs = Set(projects.map(\.id) + [unrelated.id])
        XCTAssertEqual(model.visibleCandidates(for: .projects).count, 1)

        await model.protect(projectURL).value

        XCTAssertEqual(model.selectedIDs, [unrelated.id])
        XCTAssertTrue(model.candidates(for: .projects).allSatisfy { !$0.risk.isSelectable })
        XCTAssertNil(model.cleanupCenterSelectionSummary(for: .projects))
        XCTAssertEqual(model.resourceReviewFilters[.projects]!.query, projects[0].displayName)
        let storedPolicy = try await CleanupRuntime(home: home, fileSystem: LocalFileSystem()).protections.snapshot()
        XCTAssertEqual(storedPolicy.entries.map(\.url), [projectURL.standardizedFileURL])
        XCTAssertThrowsError(try storedPolicy.validate(projects[1].url))
        XCTAssertNoThrow(try storedPolicy.validate(unrelated.url))
    }
}
