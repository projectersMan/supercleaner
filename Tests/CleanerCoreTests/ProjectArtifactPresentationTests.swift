import Foundation
import XCTest
@testable import CleanerCore

final class ProjectArtifactPresentationTests: XCTestCase {
    func testProjectDefaultsRepresentContainedInstallersByTheirCleanableDirectory() throws {
        let parent = candidate("build", directory: true, bytes: 100, risk: .review)
        let nested = candidate("build/Release.dmg", directory: false, bytes: 40, risk: .review)
        let direct = candidate("Release.dmg", directory: false, bytes: 30, risk: .review)
        let sibling = candidate("build-old/Old.dmg", directory: false, bytes: 20, risk: .review)
        let report = report([nested, parent, direct, sibling])
        let defaults = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
        XCTAssertEqual(Set(defaults.projects.map(\.id)), [parent.id, direct.id, sibling.id])
        XCTAssertEqual(defaults.bytes, 150)
        XCTAssertEqual(try defaults.buildPlan(using: PlanBuilder()).selectedBytes, 150)
        XCTAssertEqual(report.projectScanReport?.artifacts.count, 4, "Raw ownership and validation evidence must be retained")
    }

    func testProtectedDirectoriesKeepTheirIndividuallyCleanableInstaller() {
        let parent = candidate(".build", directory: true, bytes: 100, risk: .blocked)
        let nested = candidate(".build/Release.dmg", directory: false, bytes: 40, risk: .review)
        let report = report([parent, nested])
        let defaults = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
        XCTAssertEqual(defaults.projects.map(\.id), [nested.id])
        XCTAssertEqual(defaults.bytes, 40)
    }

    func testHiddenProjectInstallersDoNotReappearAsLargeFiles() {
        let parent = candidate("build", directory: true, bytes: 100, risk: .review)
        let nested = candidate("build/Release.dmg", directory: false, bytes: 40, risk: .review)
        let large = CleanupCandidate(url: nested.url, displayName: nested.displayName, category: .largeFile, bytes: nested.bytes,
            risk: .review, evidence: [], identity: nested.identity, source: .diskAnalysis, lastAccessDate: nil,
            isActive: false, defaultSelection: true)
        let report = report([parent, nested], largeFiles: [large])
        XCTAssertEqual(report.projectInstallerPaths, [nested.url.path])
        XCTAssertTrue(report.largeFileReviewCandidates.isEmpty)
        let defaults = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
        XCTAssertEqual(defaults.projects.map(\.id), [parent.id])
        XCTAssertEqual(defaults.candidates.map(\.id), [parent.id])
        XCTAssertEqual(defaults.bytes, 100)
    }

    private func candidate(_ path: String, directory: Bool, bytes: UInt64, risk: RiskLevel) -> CleanupCandidate {
        let url = URL(fileURLWithPath: "/Tests/project-artifact-row-dedup/code/Example").appendingPathComponent(path)
        return CleanupCandidate(url: url, displayName: url.lastPathComponent,
            category: directory ? .developerCache : .installerArtifact, bytes: bytes, risk: risk, evidence: [],
            identity: .init(device: 1, inode: UInt64(path.utf8.reduce(0) { $0 + Int($1) }), size: bytes,
                modificationTime: 1, kind: directory ? .directory : .file),
            source: .projectArtifacts, lastAccessDate: nil, isActive: false, defaultSelection: false)
    }

    private func report(_ candidates: [CleanupCandidate], largeFiles: [CleanupCandidate] = []) -> SystemScanReport {
        let project = URL(fileURLWithPath: "/Tests/project-artifact-row-dedup/code/Example")
        return SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [.projects: .init(module: .projects, state: .completed), .largeFiles: .init(module: .largeFiles, state: .completed)],
            generalCandidates: [], applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: largeFiles,
            agentAssets: [], projectScanReport: .init(startedAt: Date(), completedAt: Date(), roots: [project.deletingLastPathComponent()],
                artifacts: candidates.map { ProjectArtifact(projectURL: project, candidate: $0) }, limitations: []))
    }
}
