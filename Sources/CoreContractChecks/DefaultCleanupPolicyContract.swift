import CleanerCore
import Foundation

func runDefaultCleanupPolicyContracts() {
    let systemSafe = defaultCleanupCandidate(path: "/tmp/system-cache", source: .general, risk: .safe)
    let systemReview = defaultCleanupCandidate(path: "/tmp/review-cache", source: .general, risk: .review)
    let largeSafe = defaultCleanupCandidate(path: "/tmp/large.iso", source: .diskAnalysis, risk: .safe, category: .largeFile)
    let largeReview = defaultCleanupCandidate(path: "/tmp/review-large.iso", source: .diskAnalysis, risk: .review, category: .largeFile)
    let appSafe = defaultCleanupCandidate(path: "/Applications/Safe.app", source: .application, risk: .safe, category: .application)
    let appReview = defaultCleanupCandidate(path: "/Applications/Review.app", source: .application, risk: .review, category: .application)
    let agentSafe = defaultCleanupCandidate(path: "/tmp/agent-cache", source: .agentWorkspace, risk: .safe, category: .agentPackageCache)
    let agentActive = defaultCleanupCandidate(path: "/tmp/active-agent-cache", source: .agentWorkspace, risk: .safe, category: .agentPackageCache, isActive: true)
    let now = Date(timeIntervalSince1970: 100)
    let application = InstalledApplication(
        bundleURL: appSafe.url,
        bundleIdentifier: "com.example.safe",
        name: "Safe",
        version: "1",
        isRunning: false,
        isSystem: false
    )
    let applicationInventory = ApplicationInventory(applications: [application], coverage: CoverageSummary(), scannedAt: now)
    let uninstallInventory = ApplicationUninstallInventory(
        applicationInventory: applicationInventory,
        analyses: [
            ApplicationUninstallAnalysis(
                application: application,
                plan: UninstallPlan(
                    application: application,
                    items: [
                        UninstallItem(candidate: appSafe, containsUserData: false, isShared: false),
                        UninstallItem(candidate: appReview, containsUserData: false, isShared: false),
                    ]
                ),
                state: .complete
            )
        ]
    )
    let skillRoot = URL(fileURLWithPath: "/Users/tester/.codex/skills/test-skill", isDirectory: true)
    let skill = SkillCatalogEntry(
        id: skillRoot.path, logicalID: "test-skill", provider: .codex, scope: .global,
        source: .userInstalled, kind: .workflow, skillRootURL: skillRoot,
        manifestURL: skillRoot.appendingPathComponent("SKILL.md"), displayName: "Test Skill",
        summary: nil, tags: [], triggers: [], tools: [], pluginName: nil, registryName: nil,
        pluginVersion: nil, parseStatus: .manifestParsed, sourceAssetURLs: [skillRoot]
    )
    let mcpConfiguration = MCPConfigurationRecord(
        provider: .claude, scope: .global,
        fileURL: URL(fileURLWithPath: "/Users/tester/.claude.json"),
        sourceLabel: "Claude", parseStatus: .parsed,
        servers: [.init(name: "files", transport: .stdio), .init(name: "docs", transport: .http)]
    )
    let largeFileNodes = [largeSafe, largeReview].map { candidate in
        DiskUsageNode(
            url: candidate.url, kind: .file, ownBytes: candidate.bytes, recursiveBytes: candidate.bytes,
            childCount: 0, modifiedAt: now, isReadable: true, children: .loaded([])
        )
    }
    let report = SystemScanReport(
        metadata: ScanGenerationMetadata(startedAt: now, completedAt: now, rulesetVersion: "test"),
        modules: Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
            ($0, ScanModuleStatus(module: $0, state: .completed, completedAt: now))
        }),
        generalCandidates: [systemSafe, systemReview],
        applicationInventory: applicationInventory,
        applicationUninstallInventory: uninstallInventory,
        diskUsageTree: DiskUsageTree(roots: largeFileNodes, largeFiles: largeFileNodes, coverage: CoverageSummary(), scannedAt: now),
        largeFileCandidates: [largeSafe, largeReview],
        agentAssets: [
            AgentAssetRecord(candidate: agentSafe, provider: .codex, scope: .global, resourceKind: .packageCache, activity: .completed, cleanupEligibility: .recommended, cleanupUnitURL: agentSafe.url),
            AgentAssetRecord(candidate: agentActive, provider: .codex, scope: .global, resourceKind: .packageCache, activity: .active, cleanupEligibility: .recommended, cleanupUnitURL: agentActive.url),
        ],
        agentSkills: [skill],
        agentMCPConfigurations: [mcpConfiguration],
        agentProviderCoverage: [
            .cursor: .init(provider: .cursor, state: .unavailable, detectedRootCount: 1, scannedAssetCount: 0),
            .shared: .init(provider: .shared, state: .complete, detectedRootCount: 1, scannedAssetCount: 1),
            .git: .init(provider: .git, state: .complete, detectedRootCount: 1, scannedAssetCount: 1),
            .genericMCP: .init(provider: .genericMCP, state: .complete, detectedRootCount: 1, scannedAssetCount: 1),
        ]
    )

    let selection = DefaultCleanupPolicy().selection(for: report)
    require(Set(selection.systemCleanup.map(\.id)) == [systemSafe.id, systemReview.id], "one-click cleanup must match the system automatic-cleanup plan")
    require(selection.agentEnvironment.isEmpty, "Agent 环境默认不应进入一键清理；必须由用户显式选择目录后再执行")
    require(selection.applicationUninstall.isEmpty, "applications must require manual selection, even when uninstall items are safe")
    require(selection.largeFiles.isEmpty, "large files must require manual selection, even when candidates are safe")
    require(
        Set(selection.candidates.map(\.id)) == [systemSafe.id, systemReview.id],
        "one-click system cleanup must include only system automatic-cleanup items"
    )
    require(selection.bytes == systemSafe.bytes + systemReview.bytes, "one-click totals must exclude every manually selected dimension")
    let summary = ScanDiscoverySummary(report: report)
    require(summary.applicationCount == 1, "application summary must count installed apps, not uninstall items")
    require(summary.largeFileCount == 2, "large-file summary must count discovered files, not selections")
    require(summary.agentCount == 3, "Agent summary must count distinct detected platforms, including unreadable roots, but exclude generic resource stores")
    require(summary.skillCount == 1, "Skill summary must count catalog entries, not every file inside a Skill")
    require(summary.mcpCount == 2, "MCP summary must count server definitions, not config files")
    require(summary.detail(for: .general) == nil, "system cleanup must retain its existing status presentation")
}

private func defaultCleanupCandidate(
    path: String,
    source: CandidateSource,
    risk: RiskLevel,
    category: CleanupCategory = .cache,
    isActive: Bool = false
) -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: path),
        displayName: URL(fileURLWithPath: path).lastPathComponent,
        category: category,
        bytes: 10,
        risk: risk,
        evidence: [],
        identity: FileIdentity(device: 1, inode: UInt64(path.utf8.reduce(0) { $0 + UInt64($1) }), size: 10, modificationTime: 1, kind: .directory),
        source: source,
        lastAccessDate: nil,
        isActive: isActive
    )
}
