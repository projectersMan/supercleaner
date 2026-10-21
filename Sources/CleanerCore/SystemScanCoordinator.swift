import Foundation

public struct SystemScanProgressEvent: Sendable, Equatable {
    public let generationID: UUID
    public let module: ScanModuleID
    public let state: ScanModuleState
    public let completedModules: Int
    public let totalModules: Int
    public let message: String?
    public let limitations: [ScanLimitation]

    public init(
        generationID: UUID,
        module: ScanModuleID,
        state: ScanModuleState,
        completedModules: Int,
        totalModules: Int,
        message: String? = nil,
        limitations: [ScanLimitation] = []
    ) {
        self.generationID = generationID
        self.module = module
        self.state = state
        self.completedModules = completedModules
        self.totalModules = totalModules
        self.message = message
        self.limitations = limitations
    }
}

public struct SystemScanModuleResult: Sendable {
    public let generationID: UUID
    public let status: ScanModuleStatus
    public let payload: SystemScanModulePayload

    public var module: ScanModuleID { status.module }

    public init(
        generationID: UUID,
        status: ScanModuleStatus,
        payload: SystemScanModulePayload
    ) {
        self.generationID = generationID
        self.status = status
        self.payload = payload
    }
}

private actor SystemScanProgressTracker {
    let generationID: UUID
    var terminalModules = Set<ScanModuleID>()

    init(generationID: UUID) { self.generationID = generationID }

    func event(
        module: ScanModuleID,
        state: ScanModuleState,
        message: String? = nil,
        limitations: [ScanLimitation] = []
    ) -> SystemScanProgressEvent {
        if state.isTerminal { terminalModules.insert(module) }
        return SystemScanProgressEvent(
            generationID: generationID,
            module: module,
            state: state,
            completedModules: terminalModules.count,
            totalModules: ScanModuleID.allCases.count,
            message: message,
            limitations: limitations
        )
    }
}

private enum SystemScanOutcome: Sendable {
    case general(ScanReport, ScanModuleStatus)
    case applications(ApplicationUninstallInventory, ScanModuleStatus)
    case largeFiles(DiskUsageTree, [CleanupCandidate], ScanModuleStatus)
    case agentEnvironment(AgentAssetInventory, ScanModuleStatus)

    func moduleResult(generationID: UUID) -> SystemScanModuleResult {
        switch self {
        case let .general(report, status):
            return SystemScanModuleResult(generationID: generationID, status: status, payload: .general(report))
        case let .applications(inventory, status):
            return SystemScanModuleResult(generationID: generationID, status: status, payload: .applications(inventory))
        case let .largeFiles(tree, candidates, status):
            return SystemScanModuleResult(generationID: generationID, status: status, payload: .largeFiles(tree, candidates))
        case let .agentEnvironment(inventory, status):
            return SystemScanModuleResult(generationID: generationID, status: status, payload: .agentEnvironment(inventory))
        }
    }
}

public struct SystemScanCoordinator: Sendable {
    private let generalCoordinator: ScanCoordinator
    private let applicationScanner: ApplicationScanner
    private let applicationAnalyzer: ApplicationUninstallAnalyzer
    private let diskUsageScanner: DiskUsageScanner
    private let largeFileIndex: any LargeFileMetadataIndexing
    private let agentScanner: AgentWorkspaceScanner
    private let rulesetVersion: String
    private let rulePack: RulePack?

    public init(
        generalCoordinator: ScanCoordinator = ScanCoordinator(maxConcurrentScanners: 3),
        applicationScanner: ApplicationScanner = ApplicationScanner(),
        diskUsageScanner: DiskUsageScanner = DiskUsageScanner(
            maximumDepth: 8,
            maximumEntries: 50_000
        ),
        largeFileIndex: any LargeFileMetadataIndexing = SpotlightLargeFileMetadataIndex(),
        agentScanner: AgentWorkspaceScanner = AgentWorkspaceScanner(
            maximumDepth: 8,
            maximumAssets: 20_000
        ),
        rulesetVersion: String = "bundled-1",
        rulePack: RulePack? = nil
    ) {
        self.generalCoordinator = generalCoordinator
        self.applicationScanner = applicationScanner
        applicationAnalyzer = ApplicationUninstallAnalyzer(scanner: applicationScanner)
        self.diskUsageScanner = diskUsageScanner
        self.largeFileIndex = largeFileIndex
        self.agentScanner = agentScanner
        self.rulePack = rulePack
        self.rulesetVersion = rulePack?.executionVersion ?? rulesetVersion
    }

    public func scan(
        context: ScanContext,
        runningBundleIdentifiers: Set<String> = [],
        moduleResult: @escaping @Sendable (SystemScanModuleResult) async -> Void = { _ in },
        progress: @escaping @Sendable (SystemScanProgressEvent) async -> Void = { _ in }
    ) async -> SystemScanReport? {
        let generationID = UUID()
        let startedAt = Date()
        let tracker = SystemScanProgressTracker(generationID: generationID)
        var outcomes: [SystemScanOutcome] = []

        await withTaskGroup(of: SystemScanOutcome.self) { group in
            group.addTask {
                await progress(await tracker.event(module: .general, state: .scanning))
                let scanned = await generalCoordinator.scan(
                    using: rulePack.map { CleanupRuleEngine(pack: $0).scanners + [InstallerScanner(), IncompleteDownloadScanner()] } ?? [
                        UserCacheScanner(),
                        LogScanner(),
                        InstallerScanner(),
                        IncompleteDownloadScanner(),
                        DeveloperArtifactScanner(),
                        CachedFirmwareScanner(),
                    ],
                    context: context
                )
                let consolidated = rulePack.map { CleanupRuleEngine(pack: $0).consolidate(scanned.candidates, home: context.homeDirectory) } ?? scanned.candidates
                let historicalResidues = await HistoricalResidueScanner().scan(context: context)
                let report = ScanReport(
                    candidates: consolidated + historicalResidues,
                    failures: scanned.failures, startedAt: scanned.startedAt, completedAt: scanned.completedAt
                )
                let state: ScanModuleState = report.failures.isEmpty ? .completed : .limited
                let message = report.failures.isEmpty ? nil : L10n.text("{0} 个区域受限", String(describing: report.failures.count))
                let status = ScanModuleStatus(module: .general, state: state, startedAt: report.startedAt, completedAt: report.completedAt, message: message)
                let outcome = SystemScanOutcome.general(report, status)
                await moduleResult(outcome.moduleResult(generationID: generationID))
                await progress(await tracker.event(module: .general, state: state, message: message))
                return outcome
            }
            group.addTask {
                let module = ScanModuleID.applications
                let moduleStartedAt = Date()
                await progress(await tracker.event(module: module, state: .scanning))
                let inventory = await applicationScanner.installedApplications(
                    context: context,
                    runningBundleIdentifiers: runningBundleIdentifiers,
                    maximumDepth: 12, maximumEntries: 30_000
                )
                let analyzedInventory = await applicationAnalyzer.analyze(inventory: inventory, context: context)
                let coverage = analyzedInventory.moduleCoverage
                let state: ScanModuleState = coverage.isLimited ? .limited : .completed
                let message = coverage.isLimited ? coverage.summary : nil
                let completedAt = Date()
                let status = ScanModuleStatus(
                    module: module,
                    state: state,
                    startedAt: moduleStartedAt,
                    completedAt: completedAt,
                    message: message,
                    limitations: coverage.limitations
                )
                let outcome = SystemScanOutcome.applications(analyzedInventory, status)
                await moduleResult(outcome.moduleResult(generationID: generationID))
                await progress(await tracker.event(
                    module: module,
                    state: state,
                    message: message,
                    limitations: coverage.limitations
                ))
                return outcome
            }
            group.addTask {
                let module = ScanModuleID.largeFiles
                let moduleStartedAt = Date()
                await progress(await tracker.event(module: module, state: .scanning))
                let indexedTree = try? await IndexedLargeFileScanner(
                    minimumBytes: diskUsageScanner.minimumFileBytes,
                    index: largeFileIndex
                ).scan(context: context)
                if let indexedTree,
                   let indexedCandidates = try? await LargeFileScanner(
                       minimumBytes: diskUsageScanner.minimumFileBytes
                   ).candidates(from: indexedTree, context: context) {
                    let status = ScanModuleStatus(
                        module: module,
                        state: .completed,
                        startedAt: moduleStartedAt,
                        completedAt: indexedTree.scannedAt,
                        message: L10n.text("使用 Spotlight 索引完成大文件扫描")
                    )
                    let outcome = SystemScanOutcome.largeFiles(indexedTree, indexedCandidates, status)
                    await moduleResult(outcome.moduleResult(generationID: generationID))
                    await progress(await tracker.event(
                        module: module,
                        state: .completed,
                        message: status.message
                    ))
                    return outcome
                }
                do {
                    try Task.checkCancellation()
                    let tree = try await diskUsageScanner.scan(context: context)
                    let candidates = try await LargeFileScanner(
                        minimumBytes: diskUsageScanner.minimumFileBytes,
                        maximumDepth: diskUsageScanner.maximumDepth,
                        maximumEntries: diskUsageScanner.maximumEntries
                    ).candidates(from: tree, context: context)
                    let limited = !tree.coverage.unavailableRoots.isEmpty || tree.coverage.budgetLimitedModules.contains(module)
                    let state: ScanModuleState = limited ? .limited : .completed
                    let message = limited ? L10n.text("部分目录不可访问或达到扫描预算") : nil
                    let status = ScanModuleStatus(module: module, state: state, startedAt: moduleStartedAt, completedAt: tree.scannedAt, message: message)
                    let outcome = SystemScanOutcome.largeFiles(tree, candidates, status)
                    await moduleResult(outcome.moduleResult(generationID: generationID))
                    await progress(await tracker.event(module: module, state: state, message: message))
                    return outcome
                } catch {
                    let completedAt = Date()
                    if let indexedTree {
                        let indexedCandidates = (try? await LargeFileScanner(
                            minimumBytes: diskUsageScanner.minimumFileBytes
                        ).candidates(from: indexedTree, context: context)) ?? []
                        let message = L10n.text("Spotlight 索引仅提供候选预览；精确目录扫描未完成")
                        let status = ScanModuleStatus(
                            module: module,
                            state: .limited,
                            startedAt: moduleStartedAt,
                            completedAt: completedAt,
                            message: message
                        )
                        let outcome = SystemScanOutcome.largeFiles(
                            indexedTree,
                            indexedCandidates,
                            status
                        )
                        await moduleResult(outcome.moduleResult(generationID: generationID))
                        await progress(await tracker.event(
                            module: module,
                            state: .limited,
                            message: message
                        ))
                        return outcome
                    }
                    let message = String(describing: error)
                    let status = ScanModuleStatus(module: module, state: .failed, startedAt: moduleStartedAt, completedAt: completedAt, message: message)
                    let outcome = SystemScanOutcome.largeFiles(
                        DiskUsageTree(roots: [], largeFiles: [], coverage: CoverageSummary(), scannedAt: completedAt),
                        [], status
                    )
                    await moduleResult(outcome.moduleResult(generationID: generationID))
                    await progress(await tracker.event(module: module, state: .failed, message: message))
                    return outcome
                }
            }
            group.addTask {
                let module = ScanModuleID.agentEnvironment
                let moduleStartedAt = Date()
                await progress(await tracker.event(module: module, state: .scanning))
                do {
                    let inventory = try await agentScanner.scanAssetInventory(context: context)
                    let completedAt = Date()
                    let state: ScanModuleState = inventory.isComplete ? .completed : .limited
                    let message = inventory.isComplete ? nil : L10n.text("部分 Agent 路径未完整检查")
                    let status = ScanModuleStatus(module: module, state: state, startedAt: moduleStartedAt, completedAt: completedAt, message: message, limitations: inventory.limitations)
                    let outcome = SystemScanOutcome.agentEnvironment(inventory, status)
                    await moduleResult(outcome.moduleResult(generationID: generationID))
                    await progress(await tracker.event(module: module, state: state, message: message, limitations: inventory.limitations))
                    return outcome
                } catch {
                    let completedAt = Date()
                    let message = String(describing: error)
                    let status = ScanModuleStatus(module: module, state: .failed, startedAt: moduleStartedAt, completedAt: completedAt, message: message)
                    let outcome = SystemScanOutcome.agentEnvironment(
                        AgentAssetInventory(assets: [], skills: [], reachedBudget: false), status
                    )
                    await moduleResult(outcome.moduleResult(generationID: generationID))
                    await progress(await tracker.event(module: module, state: .failed, message: message))
                    return outcome
                }
            }

            for await outcome in group {
                outcomes.append(outcome)
            }
        }

        guard !Task.isCancelled else { return nil }
        var modules: [ScanModuleID: ScanModuleStatus] = [:]
        var generalCandidates: [CleanupCandidate] = []
        var inventory = ApplicationInventory(applications: [], coverage: CoverageSummary(), scannedAt: startedAt)
        var applicationAnalysis: ApplicationUninstallInventory?
        var diskTree = DiskUsageTree(roots: [], largeFiles: [], coverage: CoverageSummary(), scannedAt: startedAt)
        var largeCandidates: [CleanupCandidate] = []
        var agentAssets: [AgentAssetRecord] = []
        var agentSkills: [SkillCatalogEntry] = []
        var agentMCPConfigurations: [MCPConfigurationRecord] = []
        var agentProviderCoverage: [AgentProvider: AgentProviderCoverage] = [:]
        var agentScanCoverage = CoverageSummary()
        var agentSkillDuplicatesCollapsedCount = 0
        for outcome in outcomes {
            switch outcome {
            case let .general(report, status): generalCandidates = report.candidates; modules[.general] = status
            case let .applications(value, status):
                applicationAnalysis = value
                inventory = value.applicationInventory
                modules[.applications] = status
            case let .largeFiles(tree, candidates, status): diskTree = tree; largeCandidates = candidates; modules[.largeFiles] = status
            case let .agentEnvironment(agentInventory, status):
                agentAssets = agentInventory.assets
                agentSkills = agentInventory.skills
                agentMCPConfigurations = agentInventory.mcpConfigurations
                agentProviderCoverage = agentInventory.providerCoverage
                agentScanCoverage = agentInventory.coverage
                agentSkillDuplicatesCollapsedCount = agentInventory.skillDuplicatesCollapsedCount
                modules[.agentEnvironment] = status
            }
        }
        let completedAt = modules.values.compactMap(\.completedAt).max() ?? Date()
        let report = SystemScanReport(
            metadata: ScanGenerationMetadata(
                generationID: generationID,
                startedAt: startedAt,
                completedAt: completedAt,
                rulesetVersion: rulesetVersion
            ),
            modules: modules,
            generalCandidates: generalCandidates,
            applicationInventory: inventory,
            applicationUninstallInventory: applicationAnalysis,
            diskUsageTree: diskTree,
            largeFileCandidates: largeCandidates,
            agentAssets: agentAssets,
            agentSkills: agentSkills,
            agentMCPConfigurations: agentMCPConfigurations,
            agentProviderCoverage: agentProviderCoverage,
            agentSkillDuplicatesCollapsedCount: agentSkillDuplicatesCollapsedCount,
            agentScanCoverage: agentScanCoverage
        )
        return report.isCommitEligible ? report : nil
    }
}
