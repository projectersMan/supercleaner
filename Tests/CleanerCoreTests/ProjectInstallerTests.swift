import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class ProjectInstallerTests: XCTestCase {
    func testProjectDMGsAreDiscoveredAtRootAndInsideBuild() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/Example")
        _ = try Self.write("code/Example/Package.swift", home: home, byte: 1)
        let direct = try Self.write("code/Example/Release.dmg", home: home, byte: 2)
        let built = try Self.write("code/Example/build/Build.DMG", home: home, byte: 3)
        let dependency = try Self.write("code/Example/node_modules/vendor.dmg", home: home, byte: 4)
        let download = try Self.write("Downloads/Setup.dmg", home: home, byte: 5)
        let context = ScanContext(homeDirectory: home)
        let resources = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: context)
        let installers = resources.artifacts.filter { $0.candidate.url.pathExtension.lowercased() == "dmg" }
        XCTAssertEqual(Set(installers.map(\.candidate.url)), [direct, built, dependency])
        XCTAssertTrue(installers.filter { $0.candidate.url != dependency }.allSatisfy { $0.candidate.risk.isSelectable },
            "\(installers.map { ($0.candidate.url.path, $0.candidate.risk, $0.candidate.evidence) })")
        XCTAssertEqual(installers.first { $0.candidate.url == dependency }?.candidate.risk, .blocked)
        XCTAssertTrue(installers.allSatisfy { $0.projectURL.path == project.path })
        let baseline = await SystemScanCoordinator(diskUsageScanner: .init(minimumFileBytes: 1),
            largeFileIndex: ProjectInstallerIndex(urls: [direct, built, download])).scan(context: context, modules: [.largeFiles])
        let original = try XCTUnwrap(baseline)
        XCTAssertEqual(original.largeFileCandidates.map(\.url), [download])
        XCTAssertEqual(original.diskUsageTree.largeFiles.map(\.url), [download])
        let report = original.replacing(moduleResult: .init(generationID: original.generationID,
            status: .init(module: .projects, state: .completed), payload: .projects(resources)))
        let defaults = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
        XCTAssertEqual(Set(defaults.largeFiles.map(\.url)), [download])
        XCTAssertTrue(defaults.projects.contains { $0.url == direct })
        XCTAssertFalse(report.largeFileReviewCandidates.contains { $0.url == built })
        XCTAssertEqual(report.largeFileReviewTree.largeFiles.map(\.url), [download])
        let plan = try defaults.buildPlan(using: PlanBuilder())
        XCTAssertFalse(plan.selectedItems.contains { $0.candidate.url == built })
        XCTAssertTrue(plan.selectedItems.contains { $0.candidate.url == project.appendingPathComponent("build") })
        try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).validateForExecution(
            try XCTUnwrap(installers.first { $0.candidate.url == direct }?.candidate), context: context)
        for order in [[ScanModuleID.projects, .largeFiles], [.largeFiles, .projects]] {
            let generation = UUID()
            var accumulator = ProgressiveScanReportAccumulator(generationID: generation, startedAt: Date(),
                rulesetVersion: "fixture", baseline: nil, initialStatuses: [:])
            for module in order {
                let payload: SystemScanModulePayload = module == .projects ? .projects(resources)
                    : .largeFiles(report.diskUsageTree, report.largeFileCandidates)
                XCTAssertTrue(accumulator.apply(.init(generationID: generation,
                    status: .init(module: module, state: .completed), payload: payload)))
            }
            XCTAssertEqual(accumulator.report.largeFileReviewCandidates.map(\.url), [download])
            XCTAssertTrue(accumulator.report.candidates.contains { $0.url == built && $0.source == .projectArtifacts })
        }
    }

    func testProjectActivityDoesNotBlockDirectoriesOrOpenInstallers() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/Example")
        _ = try Self.write("code/Example/Package.swift", home: home, byte: 1)
        let dmg = try Self.write("code/Example/build/Release.dmg", home: home, byte: 2)
        let references: Set<URL> = [project, dmg]
        XCTAssertEqual(ProjectActivityProbe.activeFilePaths(in: references), [dmg])
        let context = ScanContext(homeDirectory: home, projectActivePaths: [project])
        XCTAssertFalse(context.isActive(dmg))
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let report = try await scanner.scan(context: context)
        XCTAssertEqual(report.artifacts.first { $0.candidate.url == dmg }?.candidate.risk, .review)
        XCTAssertEqual(report.artifacts.first { $0.candidate.url == project.appendingPathComponent("build") }?.candidate.risk, .review)
        let active = try await scanner.scan(context: ScanContext(homeDirectory: home, activePaths: [dmg], projectActivePaths: [project]))
        XCTAssertEqual(active.artifacts.first { $0.candidate.url == dmg }?.candidate.risk, .review)
    }

    func testDiscoveryUsesConfiguredRootsBeforePublishingLargeFiles() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("Workspaces")
        _ = try Self.write("Workspaces/Example/Package.swift", home: home, byte: 1)
        let project = try Self.write("Workspaces/Example/Release.dmg", home: home, byte: 2)
        let plain = try Self.write("Workspaces/NoProject/Setup.dmg", home: home, byte: 3)
        let download = try Self.write("Downloads/Setup.dmg", home: home, byte: 4)
        let store = ProjectScanRootsStore(url: home.appendingPathComponent("Library/Application Support/SuperCleaner/project-scan-roots.json"), home: home)
        _ = try await store.save([workspace])
        let coordinator = SystemScanCoordinator(diskUsageScanner: .init(minimumFileBytes: 1),
            largeFileIndex: ProjectInstallerIndex(urls: [project, plain, download]))
        let scopedResult = await coordinator.scan(context: ScanContext(homeDirectory: home), modules: [.largeFiles])
        let scoped = try XCTUnwrap(scopedResult)
        XCTAssertEqual(Set(scoped.largeFileCandidates.map(\.url)), [plain, download])
        _ = try await store.save([])
        let unscopedResult = await coordinator.scan(context: ScanContext(homeDirectory: home), modules: [.largeFiles])
        let unscoped = try XCTUnwrap(unscopedResult)
        XCTAssertEqual(Set(unscoped.largeFileCandidates.map(\.url)), [project, plain, download])
    }

    func testTrackedProjectDMGCanBeManuallySelectedAndRestored() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("code/Example/.build/checkouts/Sparkle")
        _ = try Self.write("code/Example/Package.swift", home: home, byte: 1)
        let dmg = try Self.write("code/Example/.build/checkouts/Sparkle/Tests/Release.dmg", home: home, byte: 2)
        let copy = try Self.write("code/Example/.build/checkouts/Sparkle/Tests/Copy.dmg", home: home, byte: 2)
        let initialized = try await BoundedProcess.run("/usr/bin/git", arguments: ["init", project.path], timeout: 3)
        XCTAssertEqual(initialized.status, 0)
        let added = try await BoundedProcess.run("/usr/bin/git", arguments: ["-C", project.path, "add", "Tests"], timeout: 3)
        XCTAssertEqual(added.status, 0)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let context = ScanContext(homeDirectory: home)
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url == dmg }?.candidate)
        let installers = report.artifacts.map(\.candidate).filter { $0.url == dmg || $0.url == copy }
        XCTAssertEqual(installers.count, 2)
        XCTAssertTrue(installers.allSatisfy(ResourceCleanupListPolicy.isSelectable))
        XCTAssertTrue(installers.allSatisfy { $0.requiresExplicitSelection == true && $0.defaultSelection == false })
        XCTAssertTrue(installers.allSatisfy { $0.largeFileProof == nil }, "Tracked fixtures must not acquire automatic duplicate keeper restrictions")
        XCTAssertEqual(report.artifacts.first { $0.candidate.url.lastPathComponent == ".build" }?.candidate.risk, .blocked)
        try await scanner.validateForExecution(candidate, context: context)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("quarantine"), currentRuleVersion: "fixture",
            validateCandidate: { try await scanner.validateForExecution($0, context: context) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.disposition, .quarantined)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.disposition, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dmg.path))
        let active = try await scanner.scan(context: ScanContext(homeDirectory: home, activePaths: [dmg]))
        XCTAssertEqual(active.artifacts.first { $0.candidate.url == dmg }?.candidate.risk, .review)
        let protected = try await scanner.scan(context: ScanContext(homeDirectory: home,
            protectionPolicy: ProtectionPolicy(entries: [ProtectedPath(url: dmg)], homeDirectory: home)))
        XCTAssertFalse(protected.artifacts.contains { $0.candidate.url == dmg && ResourceCleanupListPolicy.isSelectable($0.candidate) })
        let validation = await Task { try await scanner.validateForExecution(candidate, context: ScanContext(homeDirectory: home,
            protectionPolicy: ProtectionPolicy(entries: [ProtectedPath(url: dmg)], homeDirectory: home))) }.result
        guard case .failure = validation else { return XCTFail("Permanent path protection must still reject tracked items") }
    }

    func testProjectRoutingPreservesCopyProofAndKeepsItsRetainedFileAndParent() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        _ = try Self.write("code/Example/Package.swift", home: home, byte: 1)
        let keeper = try Self.write("code/Example/build/A.dmg", home: home, byte: 42)
        let copy = try Self.write("code/Example/build/B.dmg", home: home, byte: 42)
        let context = ScanContext(homeDirectory: home)
        let baseline = await SystemScanCoordinator(diskUsageScanner: .init(minimumFileBytes: 1),
            largeFileIndex: ProjectInstallerIndex(urls: [keeper, copy])).scan(context: context, modules: [.largeFiles])
        let resources = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: context)
        XCTAssertEqual(resources.artifacts.filter { ResourceCleanupListPolicy.isSelectable($0.candidate) }.map(\.candidate.url), [copy])
        XCTAssertNotNil(resources.artifacts.first { $0.candidate.url == copy }?.candidate.largeFileProof)
        let original = try XCTUnwrap(baseline)
        let report = original.replacing(moduleResult: .init(generationID: original.generationID,
            status: .init(module: .projects, state: .completed), payload: .projects(resources)))
        let defaults = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
        XCTAssertEqual(defaults.projects.map(\.url), [copy])
        XCTAssertNotNil(defaults.projects.first?.largeFileProof)
        XCTAssertEqual(try defaults.buildPlan(using: PlanBuilder()).selectedItems.map(\.candidate.url), [copy])
        let retained = try XCTUnwrap(report.candidates.first { $0.url == keeper })
        XCTAssertEqual(retained.risk, .blocked)
        let parent = try XCTUnwrap(report.candidates.first { $0.url.path == keeper.deletingLastPathComponent().path })
        XCTAssertEqual(parent.risk, .blocked)
        XCTAssertThrowsError(try PlanBuilder().build(candidates: report.candidates, selectedIDs: [retained.id, defaults.projects[0].id]))
    }

    func testTrackedBuildDirectoryAllowsReviewButCredentialsAndUnknownGitStillBlock() async throws {
        let home = Self.home()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        _ = try Self.write("code/Example/Package.swift", home: home, byte: 1)
        _ = try Self.write("code/Example/.build/output", home: home, byte: 2)
        let project = home.appendingPathComponent("code/Example")
        let initialized = try await BoundedProcess.run("/usr/bin/git", arguments: ["init", project.path], timeout: 3)
        XCTAssertEqual(initialized.status, 0)
        let added = try await BoundedProcess.run("/usr/bin/git", arguments: ["-C", project.path, "add", ".build/output"], timeout: 3)
        XCTAssertEqual(added.status, 0)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let context = ScanContext(homeDirectory: home)
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url.lastPathComponent == ".build" }?.candidate)
        XCTAssertEqual(candidate.risk, .review)
        XCTAssertEqual(candidate.requiresExplicitSelection, true)
        try await scanner.validateForExecution(candidate, context: context)
        _ = try Self.write("code/Example/.build/deploy.key", home: home, byte: 3)
        let validation = await Task { try await scanner.validateForExecution(candidate, context: context) }.result
        guard case .failure = validation else { return XCTFail("New credentials must prevent executing a tracked directory") }
        _ = try Self.write("code/Broken/Package.swift", home: home, byte: 1)
        _ = try Self.write("code/Broken/.git", home: home, byte: 4)
        _ = try Self.write("code/Broken/.build/output", home: home, byte: 2)
        let unknown = try await scanner.scan(context: context)
        let broken = try XCTUnwrap(unknown.artifacts.first { $0.projectURL.lastPathComponent == "Broken" }?.candidate)
        XCTAssertEqual(broken.risk, .blocked)
        XCTAssertTrue(broken.evidence.contains { $0.code == "git-status" && $0.summary == L10n.text("无法验证 Git 状态，保持保护") })
    }

    private static func home() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cleanup-center-resource-sync/fixtures/\(UUID())")
    }

    private static func write(_ path: String, home: URL, byte: UInt8) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: byte, count: 8192).write(to: url)
        return url
    }
}

private struct ProjectInstallerIndex: LargeFileMetadataIndexing {
    let urls: [URL]
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] { urls }
}
