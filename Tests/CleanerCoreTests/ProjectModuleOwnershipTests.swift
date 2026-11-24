import Foundation
import XCTest
@testable import CleanerCore

final class ProjectModuleOwnershipTests: XCTestCase {
    func testProjectDirectoriesAndCapacitySurviveEveryModuleCompletionOrder() throws {
        let fixture = OwnershipFixture()
        let orders: [[ScanModuleID]] = [[.projects, .agentEnvironment, .largeFiles], [.projects, .largeFiles, .agentEnvironment],
            [.agentEnvironment, .projects, .largeFiles], [.agentEnvironment, .largeFiles, .projects],
            [.largeFiles, .projects, .agentEnvironment], [.largeFiles, .agentEnvironment, .projects]]
        for order in orders {
            var accumulator = fixture.accumulator()
            var projectPublished = false
            for module in order {
                XCTAssertTrue(accumulator.apply(fixture.result(module)))
                if module == .projects { projectPublished = true }
                guard projectPublished else { continue }
                let report = accumulator.report
                let selection = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report)
                XCTAssertEqual(Set(selection.projects.map(\.id)), Set(fixture.directories.map(\.id)), "\(order), after \(module)")
                XCTAssertEqual(selection.bytes, 9_756_200_000, "\(order), after \(module)")
                XCTAssertEqual(try selection.buildPlan(using: PlanBuilder()).selectedBytes, selection.bytes)
                XCTAssertEqual(report.candidates.count, Set(report.candidates.map(\.url)).count)
            }
            XCTAssertTrue(accumulator.report.agentAssets.contains { $0.candidate.url == fixture.worktreeRoot })
            XCTAssertEqual(accumulator.report.candidates.first { $0.url == fixture.worktreeRoot }?.risk, .blocked)
        }
    }

    func testProtectedProjectArtifactCannotBeReplacedByPermissiveAgentCandidate() {
        let fixture = OwnershipFixture()
        let protected = fixture.directories[0].replacing(risk: .blocked,
            evidence: [Evidence(code: "deployment-key", summary: "Protected credentials")])
        let project = fixture.projectReport([protected])
        let agent = fixture.asset(protected, risk: .safe)
        var accumulator = fixture.accumulator()
        XCTAssertTrue(accumulator.apply(.init(generationID: fixture.generation, status: .init(module: .projects, state: .completed), payload: .projects(project))))
        XCTAssertTrue(accumulator.apply(.init(generationID: fixture.generation, status: .init(module: .agentEnvironment, state: .completed),
            payload: .agentEnvironment(.init(assets: [agent], reachedBudget: false)))))
        let item = accumulator.report.candidates.first { $0.url == protected.url }
        XCTAssertEqual(item?.source, .projectArtifacts)
        XCTAssertEqual(item?.risk, .blocked)
        XCTAssertTrue(DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: accumulator.report).projects.isEmpty)
    }

    func testProjectOwnershipKeepsSpecializedModelAndSystemProtectionPrecedence() {
        let fixture = OwnershipFixture()
        let model = CleanupCandidate(url: fixture.directories[0].url, displayName: "Model", category: .agentModelCache,
            bytes: fixture.directories[0].bytes, risk: .review, evidence: [], identity: fixture.directories[0].identity,
            source: .localAIModels, lastAccessDate: nil, isActive: false, defaultSelection: false, requiresExplicitSelection: true)
        let system = CleanupCandidate(url: fixture.directories[1].url, displayName: "Protected", category: .credential,
            bytes: fixture.directories[1].bytes, risk: .blocked, evidence: [], identity: fixture.directories[1].identity,
            source: .general, lastAccessDate: nil, isActive: false)
        let report = SystemScanReport(metadata: .init(generationID: fixture.generation, startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [:], generalCandidates: [system], applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: [],
            agentAssets: fixture.assets,
            localAIModelInventory: .init(models: [.init(provider: .keras, candidate: model)], coverage: .init(), limitations: [], scannedAt: Date()),
            projectScanReport: fixture.projectReport(Array(fixture.directories.prefix(2))))
        XCTAssertEqual(report.candidates.first { $0.url == model.url }?.source, .localAIModels)
        XCTAssertEqual(report.candidates.first { $0.url == system.url }?.source, .general)
        XCTAssertTrue(DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report).projects.isEmpty)
    }
}

private struct OwnershipFixture {
    let generation = UUID()
    let home = URL(fileURLWithPath: "/Users/tester")
    var worktreeRoot: URL { home.appendingPathComponent(".codex/worktrees/fixture/supercleaner") }
    let directories: [CleanupCandidate]
    var assets: [AgentAssetRecord] {
        Array(directories.prefix(2)).map { asset($0, risk: .blocked) } + [asset(Self.candidate(worktreeRoot, bytes: 0), risk: .blocked)]
    }

    init() {
        directories = [Self.candidate(URL(fileURLWithPath: "/Users/tester/.codex/worktrees/fixture/supercleaner/.build"), bytes: 4_610_000_000),
            Self.candidate(URL(fileURLWithPath: "/Users/tester/.codex/worktrees/fixture/supercleaner/build"), bytes: 646_200_000),
            Self.candidate(URL(fileURLWithPath: "/Users/tester/code/supercleaner/.build"), bytes: 2_960_000_000),
            Self.candidate(URL(fileURLWithPath: "/Users/tester/code/supercleaner/build"), bytes: 1_540_000_000)]
    }

    func accumulator() -> ProgressiveScanReportAccumulator {
        .init(generationID: generation, startedAt: Date(), rulesetVersion: "fixture", baseline: nil, initialStatuses: [:])
    }

    func projectReport(_ candidates: [CleanupCandidate]) -> ProjectScanReport {
        .init(startedAt: Date(), completedAt: Date(), roots: [home], artifacts: candidates.map {
            ProjectArtifact(projectURL: $0.url.deletingLastPathComponent(), candidate: $0)
        }, limitations: [])
    }

    func asset(_ candidate: CleanupCandidate, risk: RiskLevel) -> AgentAssetRecord {
        let duplicate = CleanupCandidate(url: candidate.url, displayName: candidate.displayName, category: .agentWorktree,
            bytes: candidate.bytes, risk: risk, evidence: [], identity: candidate.identity, source: .agentWorkspace,
            lastAccessDate: nil, isActive: false, defaultSelection: false)
        return .init(candidate: duplicate, provider: .codex, scope: .project, resourceKind: .gitWorktree,
            activity: .unknown, cleanupEligibility: risk == .blocked ? .protected : .retained, cleanupUnitURL: duplicate.url)
    }

    func result(_ module: ScanModuleID) -> SystemScanModuleResult {
        let payload: SystemScanModulePayload
        switch module {
        case .projects: payload = .projects(projectReport(directories))
        case .agentEnvironment: payload = .agentEnvironment(.init(assets: assets, reachedBudget: false))
        case .largeFiles: payload = .largeFiles(.init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), [])
        default: preconditionFailure("Unexpected module")
        }
        return .init(generationID: generation, status: .init(module: module, state: .completed), payload: payload)
    }

    private static func candidate(_ url: URL, bytes: UInt64) -> CleanupCandidate {
        CleanupCandidate(url: url, displayName: url.lastPathComponent, category: .developerCache, bytes: bytes,
            risk: .review, evidence: [], identity: .init(device: 1, inode: bytes + 1, size: bytes, modificationTime: 1, kind: .directory),
            source: .projectArtifacts, lastAccessDate: nil, isActive: false, defaultSelection: false)
    }
}
