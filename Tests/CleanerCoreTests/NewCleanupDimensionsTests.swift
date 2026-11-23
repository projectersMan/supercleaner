import Foundation
import XCTest
@testable import CleanerCore

final class NewCleanupDimensionsTests: XCTestCase {
    func testModelExecutionUsesModelScopeValidationInsteadOfBundledRuleLookup() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/local-ai-projects-disk/fixtures/model-validation-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let candidate = CleanupCandidate(url: home.appendingPathComponent("not-a-model"), displayName: "Invalid model",
            category: .agentModelCache, bytes: 1, risk: .review, evidence: [],
            identity: FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .directory),
            source: .localAIModels, lastAccessDate: nil, isActive: false,
            ruleID: "local-ai-model.huggingFace", defaultSelection: false, requiresExplicitSelection: true)
        let runtime = CleanupRuntime(home: home)
        let result = await Task { try await runtime.validateForExecution(candidate) }.result
        guard case let .failure(error) = result,
              case .executionRefused = error as? RuleScanError else {
            XCTFail("A model must reach its dedicated scope validator: \(result)")
            return
        }
    }

    func testNewDimensionsHaveIndependentNavigationAndActionBars() {
        let policy = AppNavigationPolicy()
        XCTAssertEqual(policy.scanResultDestination(for: .localAIModels, state: .completed), .localAIModels)
        XCTAssertEqual(policy.scanResultDestination(for: .projects, state: .limited), .projects)
        XCTAssertTrue(policy.showsDimensionActionBar(for: .localAIModels))
        XCTAssertTrue(policy.showsDimensionActionBar(for: .projects))
        XCTAssertFalse(policy.showsScanningPlaceholder(for: .projects, globalScanIsRunning: true, availableModules: [.projects]))
        XCTAssertTrue(policy.showsScanningPlaceholder(for: .localAIModels, globalScanIsRunning: true, availableModules: [.projects]))
    }

    func testModelAndProjectScansStayIndependentAndReconcileConfirmedCleanup() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/local-ai-projects-disk/fixtures/new-dimensions-\(UUID())")
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let blob = home.appendingPathComponent(".cache/huggingface/hub/models--org--fixture/blobs/weights.bin")
        let manifest = home.appendingPathComponent("code/Example/Package.swift")
        let artifact = home.appendingPathComponent("code/Example/.build/output")
        for file in [blob, manifest, artifact] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-14 * 86_400)], ofItemAtPath: file.path)
        }
        let context = ScanContext(homeDirectory: home, fileSystem: LocalFileSystem(), activePaths: [],
            activityProbeAvailable: true, projectActivityAvailable: true)
        let result = await SystemScanCoordinator().scan(context: context, modules: [.localAIModels, .projects])
        let report = try XCTUnwrap(result)
        XCTAssertEqual(report.modules[.localAIModels]?.state, .completed)
        XCTAssertEqual(report.modules[.projects]?.state, .completed)
        XCTAssertNil(report.modules[.agentEnvironment])
        let model = try XCTUnwrap(report.localAIModelInventory?.models.first?.candidate)
        let project = try XCTUnwrap(report.projectScanReport?.artifacts.first?.candidate)
        XCTAssertEqual(model.source, .localAIModels)
        XCTAssertEqual(project.source, .projectArtifacts)
        XCTAssertEqual(CleanupScopePolicy().candidates(for: .localAIModels, from: report.candidates).map(\.id), [model.id])
        XCTAssertEqual(CleanupScopePolicy().candidates(for: .projects, from: report.candidates).map(\.id), [project.id])
        XCTAssertFalse(model.defaultSelection == true)
        XCTAssertFalse(project.defaultSelection == true)
        XCTAssertEqual(Set(DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report).candidates.map(\.id)), [project.id])

        let results = [model, project].map {
            OperationResult(candidateID: $0.id, originalURL: $0.url, disposition: .quarantined, status: .succeeded, bytes: $0.bytes)
        }
        let reconciled = report.reconcilingCleanup(results)
        XCTAssertTrue(reconciled.candidates.isEmpty)
        XCTAssertTrue(reconciled.localAIModelInventory?.models.isEmpty == true)
        XCTAssertTrue(reconciled.projectScanReport?.artifacts.isEmpty == true)
    }
}
