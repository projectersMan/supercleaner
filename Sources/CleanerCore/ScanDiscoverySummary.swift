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
        case .applications: "发现 \(applicationCount) 个应用"
        case .largeFiles: "发现 \(largeFileCount) 个大文件"
        case .agentEnvironment: "发现 \(agentCount) 个 Agent · \(skillCount) 个 Skill · \(mcpCount) 个 MCP"
        }
    }
}
