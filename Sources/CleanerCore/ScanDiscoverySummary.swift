import Foundation

/// Discovery totals describe the scan, independently of the user's cleanup selection.
public struct ScanDiscoverySummary: Equatable, Sendable {
    public let applicationCount: Int
    public let largeFileCount: Int
    public let agentCount: Int
    public let skillCount: Int
    public let mcpCount: Int

    public init(report: SystemScanReport) {
        applicationCount = report.applicationInventory.applications.count
        largeFileCount = report.diskUsageTree.largeFiles.count
        // Shared resources, Git worktrees and generic MCP stores are not Agent apps.
        let platforms: Set<AgentProvider> = [.codex, .claude, .cursor, .trae]
        var detectedProviders = Set(report.agentAssets.map(\.provider))
        detectedProviders.formUnion(report.agentSkills.map(\.provider))
        detectedProviders.formUnion(report.agentMCPConfigurations.map(\.provider))
        for (provider, coverage) in report.agentProviderCoverage where coverage.detectedRootCount > 0 {
            detectedProviders.insert(provider)
        }
        agentCount = detectedProviders.intersection(platforms).count
        skillCount = report.agentSkills.count
        mcpCount = report.agentMCPConfigurations.reduce(0) { $0 + $1.servers.count }
    }

    public func detail(for module: ScanModuleID) -> String? {
        switch module {
        case .general: nil
        case .applications: L10n.text("发现 {0} 个应用", String(describing: applicationCount))
        case .largeFiles: L10n.text("发现 {0} 个大文件", String(describing: largeFileCount))
        case .agentEnvironment: L10n.text("发现 {0} 个 Agent · {1} 个 Skill · {2} 个 MCP", String(describing: agentCount), String(describing: skillCount), String(describing: mcpCount))
        }
    }
}
