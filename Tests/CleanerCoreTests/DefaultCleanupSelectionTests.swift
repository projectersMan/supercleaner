import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class DefaultCleanupSelectionTests: XCTestCase {
    func testProjectDefaultsAreDisabledUntilUserOptsIn() {
        let project = Self.candidate("code/.build", source: .projectArtifacts, directory: true)
        let report = Self.report(general: [project], large: [], agent: [])
        XCTAssertTrue(DefaultCleanupPolicy().selection(for: report).projects.isEmpty)
        XCTAssertTrue(DefaultCleanupPolicy().selection(for: report, selectedIDs: [project.id],
            automaticallySelectedAgentIDs: []).projects.isEmpty)
        XCTAssertEqual(DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report).projects.map(\.id), [project.id])
    }

    func testProjectOptInIncludesTrackedButStillExcludesBlockedActiveAndIncompleteItems() {
        let safe = Self.candidate("code/.build", source: .projectArtifacts, directory: true)
        var items = [safe]
        for (name, risk, active, evidence) in [
            ("tracked", RiskLevel.review, false, [Evidence]()),
            ("blocked", RiskLevel.blocked, false, [Evidence]()),
            ("active", RiskLevel.review, true, [Evidence]()),
            ("incomplete", RiskLevel.review, false, [Evidence(code: "scan-incomplete-budget", summary: "budget")])
        ] {
            items.append(CleanupCandidate(url: safe.url.deletingLastPathComponent().appendingPathComponent(name),
                displayName: name, category: .developerCache, bytes: 100, risk: risk, evidence: evidence,
                identity: safe.identity, source: .projectArtifacts, lastAccessDate: nil, isActive: active,
                defaultSelection: false, requiresExplicitSelection: true))
        }
        let report = Self.report(general: items, large: [], agent: [])
        let result = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report,
            selectedIDs: Set(items.map(\.id)), automaticallySelectedAgentIDs: [])
        XCTAssertEqual(result.projects.map(\.id), [safe.id, items[1].id])
        XCTAssertTrue(DefaultCleanupPolicy().selection(for: report, selectedIDs: Set(items.map(\.id)),
            automaticallySelectedAgentIDs: []).projects.isEmpty)
    }

    func testAllDefaultsIncludeStillSelectedResourcesAndAutomaticRecommendations() throws {
        let system = Self.candidate("Library/Logs/cache", source: .general, directory: false)
        let deselected = Self.candidate("Library/Logs/keep", source: .general, directory: false)
        let large = Self.candidate("Downloads/setup.dmg", source: .diskAnalysis, directory: false)
            .withLargeFileInstaller("DMG", preselected: true)
        let manualLarge = Self.candidate("Downloads/manual.bin", source: .diskAnalysis, directory: false)
        let agent = Self.candidate("agent/automatic", source: .agentWorkspace, directory: false)
        let manualAgent = Self.candidate("agent/manual", source: .agentWorkspace, directory: false)
        let model = Self.candidate("models/manual", source: .localAIModels, directory: false)
        let project = Self.candidate("code/.build", source: .projectArtifacts, directory: false)
        let app = Self.candidate("Applications/Manual.app", source: .application, directory: true)
        let report = Self.report(general: [system, deselected, model, project, app],
            large: [large, manualLarge], agent: [agent, manualAgent])
        let selected = Set([system, large, manualLarge, agent, manualAgent, model, project, app].map(\.id))
        let result = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report, selectedIDs: selected,
            automaticallySelectedAgentIDs: [agent.id, deselected.id])
        XCTAssertEqual(Set(result.candidates.map(\.id)), [system.id, large.id, agent.id, project.id])
        XCTAssertEqual(result.bytes, 400)
        let plan = try result.buildPlan(using: PlanBuilder())
        XCTAssertEqual(Set(plan.selectedItems.map(\.id)), Set(result.candidates.map(\.id)))
        XCTAssertEqual(plan.selectedBytes, result.bytes)
        XCTAssertEqual(result.candidates(for: .general).map(\.id), [system.id])
        XCTAssertEqual(result.candidates(for: .largeFiles).map(\.id), [large.id])
        XCTAssertEqual(result.candidates(for: .agentEnvironment).map(\.id), [agent.id])
        XCTAssertTrue(result.candidates(for: .localAIModels).isEmpty)
        XCTAssertEqual(result.candidates(for: .projects).map(\.id), [project.id])
        XCTAssertTrue(result.candidates(for: .applications).isEmpty)
        let cleared = DefaultCleanupPolicy(preselectProjectArtifacts: true).selection(for: report, selectedIDs: [],
            automaticallySelectedAgentIDs: [agent.id])
        XCTAssertTrue(cleared.candidates.isEmpty)
    }

    func testAutomaticAgentSelectionCannotIncludeBlockedOrActiveItems() {
        let safe = Self.candidate("agent/cache", source: .agentWorkspace, directory: false)
        let blocked = CleanupCandidate(url: URL(fileURLWithPath: "/Users/fixture/agent/blocked"),
            displayName: "blocked", category: .agentSandbox, bytes: 100, risk: .blocked, evidence: [],
            identity: safe.identity, source: .agentWorkspace, lastAccessDate: nil, isActive: false)
        let active = CleanupCandidate(url: URL(fileURLWithPath: "/Users/fixture/agent/active"),
            displayName: "active", category: .agentSandbox, bytes: 100, risk: .review, evidence: [],
            identity: safe.identity, source: .agentWorkspace, lastAccessDate: nil, isActive: true)
        let ids = Set([safe, blocked, active].map(\.id))
        let result = DefaultCleanupPolicy().selection(for: Self.report(general: [], large: [], agent: [safe, blocked, active]),
            selectedIDs: ids, automaticallySelectedAgentIDs: ids)
        XCTAssertEqual(result.agentEnvironment.map(\.id), [safe.id])
    }

    func testResourcesExcludeActiveBlockedAndIncompleteCandidates() {
        let safe = Self.candidate("models/eligible", source: .localAIModels, directory: false)
        var items = [safe]
        for (name, risk, active, evidence) in [
            ("blocked", RiskLevel.blocked, false, [Evidence]()),
            ("active", RiskLevel.review, true, [Evidence]()),
            ("incomplete", RiskLevel.review, false, [Evidence(code: "scan-incomplete-budget", summary: "budget")])
        ] {
            items.append(CleanupCandidate(url: safe.url.deletingLastPathComponent().appendingPathComponent(name),
                displayName: name, category: .agentModelCache, bytes: 100, risk: risk, evidence: evidence,
                identity: safe.identity, source: .localAIModels, lastAccessDate: nil, isActive: active,
                defaultSelection: false, requiresExplicitSelection: true))
        }
        let result = DefaultCleanupPolicy().selection(for: Self.report(general: items, large: [], agent: []),
            selectedIDs: Set(items.map(\.id)), automaticallySelectedAgentIDs: [])
        XCTAssertEqual(ResourceCleanupListPolicy.selectableCandidates(items).map(\.id), [safe.id])
        XCTAssertTrue(result.localAIModels.isEmpty)
    }

    func testAggregateAndModuleTotalsUseExecutableParentOperations() {
        let root = Self.candidate("agent/cache", source: .agentWorkspace, directory: true)
        let child = Self.candidate("agent/cache/child", source: .agentWorkspace, directory: false)
        let other = Self.candidate("Library/Logs/log", source: .general, directory: false)
        let selection = DefaultCleanupSelection(systemCleanup: [other], applicationUninstall: [],
            largeFiles: [], agentEnvironment: [root, child, child], localAIModels: [], projects: [])
        XCTAssertEqual(selection.candidates.count, 2)
        XCTAssertEqual(selection.bytes, 300)
        XCTAssertEqual(selection.candidates(for: .agentEnvironment).count, 1)
        XCTAssertEqual(selection.candidates(for: .agentEnvironment).first?.bytes, 200)
    }

    func testModuleSummariesDoNotCountItemsCoveredByAnotherModule() {
        let parent = Self.candidate("Library/Caches", source: .general, directory: true)
        let child = Self.candidate("Library/Caches/agent", source: .agentWorkspace, directory: false)
        let selection = DefaultCleanupSelection(systemCleanup: [parent], applicationUninstall: [],
            largeFiles: [], agentEnvironment: [child], localAIModels: [], projects: [])
        XCTAssertEqual(selection.candidates.map(\.id), [parent.id])
        XCTAssertEqual(selection.candidates(for: .general).map(\.id), [parent.id])
        XCTAssertTrue(selection.candidates(for: .agentEnvironment).isEmpty)
    }

    func testMixedPlanPreservesCopyProofBeforeAliasAndParentConsolidation() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dashboard-all-default/fixtures/\(UUID())")
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        var large = [CleanupCandidate]()
        var aliases = [CleanupCandidate]()
        for name in ["A.dmg", "B.dmg"] {
            let url = downloads.appendingPathComponent(name)
            try Data(repeating: 42, count: 8192).write(to: url)
            let identity = try await LocalFileSystem().identity(at: url)
            large.append(.init(url: url, displayName: name, category: .largeFile, bytes: identity.size,
                risk: .review, evidence: [], identity: identity, source: .diskAnalysis,
                lastAccessDate: nil, isActive: false))
            aliases.append(.init(url: url, displayName: name, category: .installerArtifact, bytes: identity.size,
                risk: .review, evidence: [], identity: identity, source: .general,
                lastAccessDate: nil, isActive: false))
        }
        let analysis = LargeFileContentAnalyzer(context: .init(homeDirectory: home), minimumBytes: 1,
            preselectInstallers: false).analyze(large)
        let copy = try XCTUnwrap(analysis.candidates.first { $0.isLargeFilePreselected && $0.largeFileProof != nil })
        let parent = CleanupCandidate(url: downloads, displayName: "Downloads", category: .cache, bytes: 16_384,
            risk: .review, evidence: [], identity: try await LocalFileSystem().identity(at: downloads),
            source: .general, lastAccessDate: nil, isActive: false)
        for system in [aliases, [parent]] {
            let selection = DefaultCleanupSelection(systemCleanup: system, applicationUninstall: [],
                largeFiles: [copy], agentEnvironment: [], localAIModels: [], projects: [])
            XCTAssertThrowsError(try selection.buildPlan(using: PlanBuilder())) { error in
                XCTAssertEqual(error as? PlanBuilderError, .retainedLargeFileSelected(copy.id))
            }
        }
    }

    private static func candidate(_ path: String, source: CandidateSource, directory: Bool) -> CleanupCandidate {
        CleanupCandidate(url: URL(fileURLWithPath: "/Users/fixture/" + path), displayName: path,
            category: source == .diskAnalysis ? .largeFile : source == .agentWorkspace ? .agentSandbox : .log,
            bytes: 100, risk: .safe, evidence: [],
            identity: .init(device: 1, inode: 1, size: 100, modificationTime: 1, kind: directory ? .directory : .file),
            source: source, lastAccessDate: nil, isActive: false)
    }

    private static func report(general: [CleanupCandidate], large: [CleanupCandidate], agent: [CleanupCandidate]) -> SystemScanReport {
        SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map { ($0, .init(module: $0, state: .completed)) }),
            generalCandidates: general, applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: large,
            agentAssets: agent.map { .init(candidate: $0, provider: .codex, scope: .global, resourceKind: .buildCache,
                activity: .completed, cleanupEligibility: .retained, cleanupUnitURL: $0.url) })
    }
}
