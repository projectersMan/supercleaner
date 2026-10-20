import Foundation

public enum SystemScanModulePayload: Sendable {
    case general(ScanReport)
    case applications(ApplicationUninstallInventory)
    case largeFiles(DiskUsageTree, [CleanupCandidate])
    case agentEnvironment(AgentAssetInventory)
}

public struct ProgressiveScanReportAccumulator: Sendable {
    public let generationID: UUID
    public private(set) var report: SystemScanReport

    public init(
        generationID: UUID,
        startedAt: Date,
        rulesetVersion: String,
        baseline: SystemScanReport?,
        initialStatuses: [ScanModuleID: ScanModuleStatus]
    ) {
        self.generationID = generationID
        let emptyApplicationInventory = ApplicationInventory(
            applications: [],
            coverage: CoverageSummary(),
            scannedAt: startedAt
        )
        report = SystemScanReport(
            metadata: ScanGenerationMetadata(
                generationID: generationID,
                startedAt: startedAt,
                completedAt: startedAt,
                rulesetVersion: rulesetVersion
            ),
            modules: initialStatuses,
            generalCandidates: baseline?.generalCandidates ?? [],
            applicationInventory: baseline?.applicationInventory ?? emptyApplicationInventory,
            applicationUninstallInventory: baseline?.applicationUninstallInventory,
            diskUsageTree: baseline?.diskUsageTree ?? DiskUsageTree(
                roots: [],
                largeFiles: [],
                coverage: CoverageSummary(),
                scannedAt: startedAt
            ),
            largeFileCandidates: baseline?.largeFileCandidates ?? [],
            agentAssets: baseline?.agentAssets ?? [],
            agentSkills: baseline?.agentSkills ?? [],
            agentMCPConfigurations: baseline?.agentMCPConfigurations ?? [],
            agentProviderCoverage: baseline?.agentProviderCoverage ?? [:],
            agentSkillDuplicatesCollapsedCount: baseline?.agentSkillDuplicatesCollapsedCount ?? 0,
            agentScanCoverage: baseline?.agentScanCoverage ?? CoverageSummary()
        )
    }

    @discardableResult
    public mutating func apply(_ result: SystemScanModuleResult) -> Bool {
        guard result.generationID == generationID,
              [.completed, .limited].contains(result.status.state)
        else { return false }
        report = report.replacing(moduleResult: result)
        return true
    }
}

public struct SystemScanReport: Sendable {
    public let metadata: ScanGenerationMetadata
    public let modules: [ScanModuleID: ScanModuleStatus]
    public let generalCandidates: [CleanupCandidate]
    public let applicationInventory: ApplicationInventory
    public let applicationUninstallInventory: ApplicationUninstallInventory
    public let diskUsageTree: DiskUsageTree
    public let largeFileCandidates: [CleanupCandidate]
    public let agentAssets: [AgentAssetRecord]
    public let agentSkills: [SkillCatalogEntry]
    public let agentMCPConfigurations: [MCPConfigurationRecord]
    public let agentProviderCoverage: [AgentProvider: AgentProviderCoverage]
    public let agentSkillDuplicatesCollapsedCount: Int
    public let agentScanCoverage: CoverageSummary
    public let candidates: [CleanupCandidate]
    public let coverage: CoverageSummary
    private let candidatesByID: [UUID: CleanupCandidate]

    public var generationID: UUID { metadata.generationID }
    public var startedAt: Date { metadata.startedAt }
    public var completedAt: Date { metadata.completedAt }
    public var rulesetVersion: String { metadata.rulesetVersion }

    public func candidate(id: UUID) -> CleanupCandidate? { candidatesByID[id] }

    private static func materializeCandidates(
        generalCandidates: [CleanupCandidate],
        largeFileCandidates: [CleanupCandidate],
        agentAssets: [AgentAssetRecord]
    ) -> [CleanupCandidate] {
        var seenPaths = Set<String>()
        return (generalCandidates + largeFileCandidates + agentAssets.map(\.candidate))
            .filter { seenPaths.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    public var isCommitEligible: Bool {
        ScanModuleID.allCases.allSatisfy { modules[$0]?.state.isTerminal == true }
            && modules.values.contains { [.completed, .limited].contains($0.state) }
    }

    public init(
        metadata: ScanGenerationMetadata,
        modules: [ScanModuleID: ScanModuleStatus],
        generalCandidates: [CleanupCandidate],
        applicationInventory: ApplicationInventory,
        applicationUninstallInventory: ApplicationUninstallInventory? = nil,
        diskUsageTree: DiskUsageTree,
        largeFileCandidates: [CleanupCandidate],
        agentAssets: [AgentAssetRecord],
        agentSkills: [SkillCatalogEntry] = [],
        agentMCPConfigurations: [MCPConfigurationRecord] = [],
        agentProviderCoverage: [AgentProvider: AgentProviderCoverage] = [:],
        agentSkillDuplicatesCollapsedCount: Int = 0,
        agentScanCoverage: CoverageSummary = CoverageSummary()
    ) {
        self.metadata = metadata
        self.modules = modules
        self.generalCandidates = generalCandidates
        self.applicationInventory = applicationInventory
        self.applicationUninstallInventory = applicationUninstallInventory
            ?? ApplicationUninstallInventory(applicationInventory: applicationInventory, analyses: [])
        self.diskUsageTree = diskUsageTree
        self.largeFileCandidates = largeFileCandidates
        self.agentAssets = agentAssets
        self.agentSkills = agentSkills
        self.agentMCPConfigurations = agentMCPConfigurations
        self.agentProviderCoverage = agentProviderCoverage
        self.agentSkillDuplicatesCollapsedCount = agentSkillDuplicatesCollapsedCount
        self.agentScanCoverage = agentScanCoverage
        let materializedCandidates = Self.materializeCandidates(
            generalCandidates: generalCandidates,
            largeFileCandidates: largeFileCandidates,
            agentAssets: agentAssets
        )
        candidates = materializedCandidates
        candidatesByID = Dictionary(
            materializedCandidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        coverage = Self.combinedCoverage(applicationInventory.coverage, diskUsageTree.coverage, agentScanCoverage)
    }

    public func replacing(
        module: ScanModuleID,
        payload: SystemScanModulePayload,
        completedAt: Date
    ) -> SystemScanReport {
        var nextModules = modules
        var general = generalCandidates
        var applicationAnalysis = applicationUninstallInventory
        var diskTree = diskUsageTree
        var largeCandidates = largeFileCandidates
        var agents = agentAssets
        var skills = agentSkills
        var mcpConfigurations = agentMCPConfigurations
        var agentCoverage = agentProviderCoverage
        var scanCoverage = agentScanCoverage
        var skillDuplicatesCollapsedCount = agentSkillDuplicatesCollapsedCount
        var replacementStatus = ScanModuleStatus(
            module: module,
            state: .completed,
            startedAt: completedAt,
            completedAt: completedAt,
            message: nil
        )
        switch payload {
        case let .general(report): general = report.candidates
        case let .applications(inventory):
            applicationAnalysis = inventory
            let coverage = inventory.moduleCoverage
            replacementStatus = ScanModuleStatus(
                module: module,
                state: coverage.isLimited ? .limited : .completed,
                startedAt: completedAt,
                completedAt: completedAt,
                message: coverage.isLimited ? coverage.summary : nil,
                limitations: coverage.limitations
            )
        case let .largeFiles(tree, candidates): diskTree = tree; largeCandidates = candidates
        case let .agentEnvironment(inventory):
            agents = inventory.assets
            skills = inventory.skills
            mcpConfigurations = inventory.mcpConfigurations
            agentCoverage = inventory.providerCoverage
            scanCoverage = inventory.coverage
            skillDuplicatesCollapsedCount = inventory.skillDuplicatesCollapsedCount
            replacementStatus = ScanModuleStatus(module: module, state: inventory.isComplete ? .completed : .limited,
                startedAt: completedAt, completedAt: completedAt,
                message: inventory.isComplete ? nil : "部分 Agent 路径未完整检查", limitations: inventory.limitations)
        }
        nextModules[module] = replacementStatus
        return SystemScanReport(
            metadata: ScanGenerationMetadata(
                generationID: generationID,
                startedAt: startedAt,
                completedAt: completedAt,
                rulesetVersion: rulesetVersion
            ),
            modules: nextModules,
            generalCandidates: general,
            applicationInventory: applicationAnalysis.applicationInventory,
            applicationUninstallInventory: applicationAnalysis,
            diskUsageTree: diskTree,
            largeFileCandidates: largeCandidates,
            agentAssets: agents,
            agentSkills: skills,
            agentMCPConfigurations: mcpConfigurations,
            agentProviderCoverage: agentCoverage,
            agentSkillDuplicatesCollapsedCount: skillDuplicatesCollapsedCount,
            agentScanCoverage: scanCoverage
        )
    }

    public func replacing(moduleResult result: SystemScanModuleResult) -> SystemScanReport {
        var nextModules = modules
        var general = generalCandidates
        var applicationAnalysis = applicationUninstallInventory
        var diskTree = diskUsageTree
        var largeCandidates = largeFileCandidates
        var agents = agentAssets
        var skills = agentSkills
        var mcpConfigurations = agentMCPConfigurations
        var agentCoverage = agentProviderCoverage
        var scanCoverage = agentScanCoverage
        var skillDuplicatesCollapsedCount = agentSkillDuplicatesCollapsedCount

        switch result.payload {
        case let .general(report):
            general = report.candidates
        case let .applications(inventory):
            applicationAnalysis = inventory
        case let .largeFiles(tree, candidates):
            diskTree = tree
            largeCandidates = candidates
        case let .agentEnvironment(inventory):
            agents = inventory.assets
            skills = inventory.skills
            mcpConfigurations = inventory.mcpConfigurations
            agentCoverage = inventory.providerCoverage
            scanCoverage = inventory.coverage
            skillDuplicatesCollapsedCount = inventory.skillDuplicatesCollapsedCount
        }
        nextModules[result.module] = result.status

        let resultStartedAt = result.status.startedAt ?? result.status.completedAt ?? Date()
        let generationStartedAt = generationID == result.generationID
            ? min(startedAt, resultStartedAt)
            : resultStartedAt
        return SystemScanReport(
            metadata: ScanGenerationMetadata(
                generationID: result.generationID,
                startedAt: generationStartedAt,
                completedAt: result.status.completedAt ?? completedAt,
                rulesetVersion: rulesetVersion
            ),
            modules: nextModules,
            generalCandidates: general,
            applicationInventory: applicationAnalysis.applicationInventory,
            applicationUninstallInventory: applicationAnalysis,
            diskUsageTree: diskTree,
            largeFileCandidates: largeCandidates,
            agentAssets: agents,
            agentSkills: skills,
            agentMCPConfigurations: mcpConfigurations,
            agentProviderCoverage: agentCoverage,
            agentSkillDuplicatesCollapsedCount: skillDuplicatesCollapsedCount,
            agentScanCoverage: scanCoverage
        )
    }

    private static func combinedCoverage(_ values: CoverageSummary...) -> CoverageSummary {
        CoverageSummary(
            scannedRoots: values.flatMap(\.scannedRoots),
            unavailableRoots: values.flatMap(\.unavailableRoots),
            budgetLimitedModules: values.reduce(into: Set<ScanModuleID>()) { $0.formUnion($1.budgetLimitedModules) }
        )
    }
}
