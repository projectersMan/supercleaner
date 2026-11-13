import CleanerCore
import Foundation

/// Synthetic, read-only records for the Agent select-all self-check and UI check.
enum AgentSelectionFixture {
    static let home = URL(fileURLWithPath: "/tmp/SuperCleaner-Agent-Selection-Fixture")

    static func report(additionalSkillCount: Int = 0) -> SystemScanReport {
        let specifications: [(String, AgentProvider, AgentScope, RiskLevel)] = [
            ("Global Skill", .shared, .shared, .review),
            ("Codex Skill", .codex, .project, .review),
            ("Claude Skill", .claude, .project, .review),
            ("Protected Skill", .codex, .project, .blocked)
        ]
        var skills = [SkillCatalogEntry]()
        var assets = [AgentAssetRecord]()
        let skillSpecifications = specifications + (0..<additionalSkillCount).map { index in
            ("Bulk Skill \(index)", AgentProvider.codex, AgentScope.project, RiskLevel.review)
        }
        for (index, specification) in skillSpecifications.enumerated() {
            let (name, provider, scope, risk) = specification
            let root = home.appendingPathComponent("skills/skill-\(index)")
            skills.append(.init(id: root.path, logicalID: "skill-\(index)", provider: provider, scope: scope,
                source: scope == .shared ? .shared : .project, kind: .workflow, skillRootURL: root,
                manifestURL: root.appendingPathComponent("SKILL.md"), displayName: name,
                summary: "Selection validation fixture", tags: [], triggers: [], tools: [],
                pluginName: nil, registryName: nil, pluginVersion: nil, parseStatus: .manifestParsed, sourceAssetURLs: [root]))
            assets.append(asset(root, provider: provider, scope: scope, kind: .skill, risk: risk))
        }
        var configurations = [MCPConfigurationRecord]()
        for (index, specification) in specifications.enumerated() {
            let (name, provider, scope, risk) = specification
            let url = home.appendingPathComponent("mcp/config-\(index).json")
            configurations.append(.init(provider: provider, scope: scope, fileURL: url,
                sourceLabel: name.replacingOccurrences(of: "Skill", with: "MCP"), parseStatus: .parsed,
                servers: [.init(name: "fixture", transport: .stdio)]))
            assets.append(asset(url, provider: provider, scope: scope, kind: .mcpDefinition, risk: risk))
        }
        return SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "selection-fixture"),
            modules: [.agentEnvironment: .init(module: .agentEnvironment, state: .completed)], generalCandidates: [],
            applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: assets, agentSkills: skills, agentMCPConfigurations: configurations)
    }

    private static func asset(_ url: URL, provider: AgentProvider, scope: AgentScope,
                              kind: AgentResourceKind, risk: RiskLevel) -> AgentAssetRecord {
        let candidate = CleanupCandidate(url: url, displayName: url.lastPathComponent, category: .agentSandbox,
            bytes: 1_000, risk: risk, evidence: [],
            identity: .init(device: 1, inode: 1, size: 1_000, modificationTime: 1, kind: kind == .skill ? .directory : .file),
            source: .agentWorkspace, lastAccessDate: nil, isActive: false)
        return .init(candidate: candidate, provider: provider, scope: scope, resourceKind: kind,
            activity: .completed, cleanupEligibility: risk == .blocked ? .protected : .retained, cleanupUnitURL: url)
    }
}
