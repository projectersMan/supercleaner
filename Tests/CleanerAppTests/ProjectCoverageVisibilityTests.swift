import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class ProjectCoverageVisibilityTests: XCTestCase {
    @MainActor
    func testFreshProjectResultsShowSelectedAndProtectedArtifactsTogether() throws {
        let suite = "ProjectCoverageVisibilityTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            preferences: preferences, readRunningApplicationIDs: { [] })
        let baseline = try ResourceCleanupPresentationFixture.report()
        let projects = try XCTUnwrap(baseline.projectScanReport)
        struct Entry: Encodable { let projectURL: URL; let candidate: CleanupCandidate }
        let entries = projects.artifacts.enumerated().map { index, artifact in
            Entry(projectURL: artifact.projectURL,
                candidate: index == 0 ? artifact.candidate.replacing(risk: .blocked, evidence: artifact.candidate.evidence) : artifact.candidate)
        }
        let artifacts = try JSONDecoder().decode([ProjectArtifact].self, from: JSONEncoder().encode(entries))
        let report = baseline.replacing(moduleResult: .init(generationID: baseline.generationID,
            status: .init(module: .projects, state: .completed),
            payload: .projects(.init(startedAt: Date(), completedAt: Date(), roots: projects.roots,
                artifacts: artifacts, limitations: []))))
        model.install(report)
        XCTAssertEqual(model.resourceReviewFilters[.projects]?.scope, .all)
        XCTAssertEqual(Set(model.visibleCandidates(for: .projects).map(\.id)), Set(artifacts.map(\.id)))
        XCTAssertEqual(model.selectedIDs.intersection(artifacts.map(\.id)), [artifacts[1].id])
    }
}
