import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class ProjectArtifactActivityTests: XCTestCase {
    func testRunningAndUnknownActivityDoNotBlockProjectArtifactsOrInstallerProofs() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/Example")
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        for available in [true, false] {
            let context = ScanContext(homeDirectory: home, activePaths: [project], projectActivePaths: [project],
                activeProcessNames: ["swift", "node"], activityProbeAvailable: available, projectActivityAvailable: available)
            let report = try await scanner.scan(context: context)
            let directory = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == "dist" }?.candidate)
            let copy = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == "B.dmg" }?.candidate)
            for candidate in [directory, copy] {
                XCTAssertEqual(candidate.risk, .review)
                XCTAssertFalse(candidate.isActive)
                XCTAssertTrue(ResourceCleanupListPolicy.isSelectable(candidate))
                XCTAssertFalse(candidate.evidence.contains { $0.code == "active-project" })
                try await scanner.validateForExecution(candidate, context: context)
            }
            XCTAssertNotNil(copy.largeFileProof, "Ignoring activity must preserve duplicate-file proofs")
            let keeper = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == "A.dmg" }?.candidate)
            XCTAssertEqual(keeper.risk, .blocked, "The required retained copy must still be protected")
        }
    }

    func testLiveActivityDoesNotSkipProjectDeletionAndNormalRecoveryStillWorks() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let context = ScanContext(homeDirectory: home)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == "dist" }?.candidate)
        let copy = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == "B.dmg" }?.candidate)
        let plan = try PlanBuilder(ruleVersion: "activity-test").build(candidates: [candidate, copy], selectedIDs: [candidate.id, copy.id])
        let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("quarantine"), currentRuleVersion: "activity-test",
            isActive: { _ in true }, validateCandidate: { try await scanner.validateForExecution($0, context: context) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.count, 2)
        XCTAssertTrue(receipt.results.allSatisfy { $0.disposition == .quarantined })
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.url.path))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.count, 2)
        XCTAssertTrue(restored.results.allSatisfy { $0.disposition == .restored })
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.appendingPathComponent("output").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.url.path))
    }

    func testActivityOptOutPreservesCredentialAndPathProtectionAndOtherSourceActivity() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/Example")
        try Data("credential".utf8).write(to: project.appendingPathComponent("dist/deploy.key"))
        let protection = ProtectionPolicy(entries: [ProtectedPath(url: project.appendingPathComponent(".build"))], homeDirectory: home)
        let context = ScanContext(homeDirectory: home, activePaths: [project], protectionPolicy: protection,
            activityProbeAvailable: false, projectActivityAvailable: false)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let report = try await scanner.scan(context: context)
        for name in ["dist", ".build"] {
            let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == name }?.candidate)
            XCTAssertEqual(candidate.risk, .blocked)
            XCTAssertFalse(ResourceCleanupListPolicy.isSelectable(candidate))
        }
        XCTAssertNil(LargeFileContentAnalyzer.eligibleSnapshot(project.appendingPathComponent("Standalone.dmg"), context: context, installer: true))
    }

    private func fixture() throws -> URL {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/project-artifact-activity/fixtures/\(UUID())")
        let project = home.appendingPathComponent("code/Example")
        for name in [".build", "build", "dist"] {
            try FileManager.default.createDirectory(at: project.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data("output".utf8).write(to: project.appendingPathComponent("dist/output"))
        try Data(repeating: 43, count: 8192).write(to: project.appendingPathComponent("Standalone.dmg"))
        for name in ["A.dmg", "B.dmg"] {
            try Data(repeating: 42, count: 8192).write(to: project.appendingPathComponent("build/" + name))
        }
        return home
    }
}
