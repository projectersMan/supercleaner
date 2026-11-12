import CleanerCore
import Foundation
import AppKit
import SwiftUI
import AgentOverlapAI

typealias SidebarDestination = AppDestination

typealias OneClickCleanupResult = DefaultCleanupModuleResult

private struct ModuleScanSession: Sendable {
    let coordinator: SystemScanCoordinator
    let context: ScanContext
    let runningBundleIdentifiers: Set<String>
    let generationID: UUID
    let startedAt: Date
}

@MainActor final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, reviewing, executing, completed, cancelled, failed(String) }
    enum RecoveryActionKind: Equatable { case restore, purge }
    @Published private(set) var phase: Phase = .idle {
        didSet { if oldValue == .executing && phase != .executing { resumeDeferredAgentAnalysis() } }
    }
    @Published private(set) var isScanRunning = false
    @Published private(set) var fullScanStartedAt: Date?
    @Published private(set) var fullScanStoppedAt: Date?
    private var isFullScanTimingSession = false
    @Published private(set) var systemReport: SystemScanReport? {
        didSet {
            invalidateCandidatePresentationCaches()
            cachedScanDiscoverySummary = nil
            if systemReport != nil && (systemReport?.generationID != oldValue?.generationID || systemReport?.agentSkills != oldValue?.agentSkills || systemReport?.agentMCPConfigurations != oldValue?.agentMCPConfigurations || systemReport?.agentAssets != oldValue?.agentAssets) {
                invalidateAgentEnvironmentCaches()
                prepareAgentSkillPresentation()
                refreshAgentOverlapPresentation()
                if isScanRunning { agentOverlapNeedsScanAnalysis = true }
                else { scheduleAgentOverlapAnalysis() }
            }
        }
    }
    @Published private(set) var agentOverlapMatches: [AgentOverlapMatch] = []
    @Published private(set) var agentOverlapMatchBySourceID: [String: AgentOverlapMatch] = [:] {
        didSet { invalidateAgentVisibleLists() }
    }
    @Published private(set) var agentOverlapStatus = AgentEmbeddingModelManager.isSupportedPlatform
        ? L10n.text("尚未分析") : L10n.text("Agent 能力分析需要 macOS 14 或更高版本及 Apple Silicon；其他功能可正常使用。")
    @Published private(set) var agentOverlapModelDownloadInProgress = false
    @Published private(set) var agentOverlapModelDownloadProgress: Double?
    @Published private(set) var agentOverlapModelInstalled = AgentEmbeddingModelManager.isSupportedPlatform && AgentEmbeddingModelManager.hasBundledModel
    let agentOverlapSupportedPlatform = AgentEmbeddingModelManager.isSupportedPlatform
    @Published private(set) var agentOverlapModelCanRemove = false
    @Published private(set) var agentOverlapThreshold: Double
    @Published private(set) var agentOverlapAnalysisIsRunning = false
    @Published private(set) var preparingAgentSkillPresentation = false
    @Published private(set) var scanProgressByModule: [ScanModuleID: ScanModuleStatus] = [:]
    @Published private(set) var receipts: [OperationReceipt] = []
    @Published private(set) var quarantineSchedules: [UUID: QuarantineSchedule] = [:]
    @Published private(set) var defaultQuarantineRetentionPolicy: QuarantineRetentionPolicy
    @Published private(set) var largeFileThreshold: LargeFileThreshold
    @Published private(set) var preselectLargeFileInstallers: Bool
    @Published private(set) var permissionSnapshot: PermissionSnapshot?
    @Published var showsScanPermissionPreparation = false
    @Published private(set) var packageReceiptSelection = PackageReceiptCleanupSelection()
    @Published private(set) var checkingScanPermissions = false
    @Published private(set) var preparingScanPermissions = false
    @Published private(set) var scanDeniedPaths: [ScanModuleID: Set<URL>] = [:]
    private var scanPresentedStatuses: [ScanModuleID: ScanModuleStatus] = [:]
    @Published private(set) var executionProgress = ExecutionProgress(completed: 0, total: 0, currentURL: nil)
    @Published var selectedIDs = Set<UUID>() {
        didSet {
            cachedSelectedCandidates.removeAll()
            cachedHiddenSelectedCounts.removeAll()
            invalidateAgentVisibleLists()
        }
    }
    @Published private(set) var excludedBaseIDs = Set<UUID>()
    @Published var selection: SidebarDestination = .cleanupCenter {
        didSet {
            if selection != oldValue, !isScanRunning, phase != .executing {
                statusMessage = nil
            }
        }
    }
    @Published var reviewQuery = "" { didSet { cachedHiddenSelectedCounts.removeAll(); reconcileFocus() } }
    @Published var reviewDispositionFilter: ReviewDispositionFilter = .all { didSet { cachedHiddenSelectedCounts.removeAll(); reconcileFocus() } }
    @Published var showsSelectedOnly = false { didSet { cachedHiddenSelectedCounts.removeAll(); reconcileFocus() } }
    @Published private(set) var cleanupMode: CleanupMode = .defaultMode
    @Published private(set) var focusState = ReviewFocusState()
    @Published var deletionResult: OperationReceipt?
    @Published var deletionResultWarning: String?
    @Published private(set) var isStoppingDeletion = false
    @Published var selectedApplicationID: URL?
    @Published var selectedDiskNodeURL: URL?
    @Published var largeFileSortOrder: LargeFileSortOrder = .selection
    @Published var showsDuplicateLargeFilesOnly = false {
        didSet { cachedSelectedCandidates.removeValue(forKey: .largeFiles); cachedHiddenSelectedCounts.removeValue(forKey: .largeFiles) }
    }
    @Published var applicationSortOrder: ApplicationSortOrder = .name {
        didSet { reconcileApplicationSelection() }
    }
    @Published var applicationQuery = "" { didSet { reconcileApplicationSelection() } }
    @Published var applicationScope: ApplicationListScope = .uninstallable { didSet { reconcileApplicationSelection() } }
    @Published private var runningApplicationIDs: Set<String>?
    private var isPreparingStoppedAppPlans = false
    @Published private(set) var isLoadingApplications = false
    @Published private(set) var deepScanningApplicationID: URL?
    @Published private(set) var deepScanMessages: [URL: String] = [:]
    private var deepScanTask: Task<Void, Never>?
    @Published private(set) var quittingApplicationIDs = Set<URL>()
    @Published private(set) var quitSelectedApplicationIDs = Set<URL>()
    @Published private(set) var applicationQuitMessages: [URL: String] = [:]

    @Published var agentCleanupPresentation: AgentCleanupPresentation? {
        didSet { cachedHiddenSelectedCounts.removeValue(forKey: .agentEnvironment) }
    }
    var agentCleanupGenerationID: UUID?
    @Published var agentProviderFilter: AgentProvider? {
        didSet { invalidateAgentVisibleLists() }
    }
    @Published var agentItemsSelectionFilter: AgentItemsSelectionFilter = .selected {
        didSet { invalidateAgentVisibleLists() }
    }
    @Published var agentEnvironmentSection: AgentEnvironmentSection = .skills {
        didSet { cachedHiddenSelectedCounts.removeValue(forKey: .agentEnvironment) }
    }
    @Published var uninstallSelectedIDs = Set<UUID>()
    @Published var statusMessage: String?
    @Published private(set) var recoveryActionReceiptID: UUID?
    @Published private(set) var recoveryActionKind: RecoveryActionKind?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var recoveryMessageIsError = false
    @Published var restoreConfirmationReceipt: OperationReceipt?
    @Published var purgeConfirmationReceipt: OperationReceipt?
    @Published private(set) var oneClickCleanupIsRunning = false { didSet { if !oneClickCleanupIsRunning { resumeDeferredAgentAnalysis() } } }
    @Published private(set) var oneClickActiveModules = Set<ScanModuleID>()
    @Published private(set) var activeCleanupModules = Set<ScanModuleID>()
    @Published private(set) var cleanedModules = Set<ScanModuleID>()
    @Published private(set) var oneClickCompletedByModule: [ScanModuleID: OneClickCleanupResult] = [:]
    @Published private(set) var sessionCleanupSummary = CleanupSessionSummary()
    @Published private(set) var cleanupFailures: [DefaultCleanupFailure] = [] {
        didSet { cachedDefaultCleanupSelection = nil }
    }
    @Published private(set) var protectionPolicy: ProtectionPolicy {
        didSet { invalidateCandidatePresentationCaches() }
    }
    @Published private(set) var rulesetVersion = "loading"
    @Published private(set) var configurationMessage: String?
    @Published private(set) var updateInProgress = false
    @Published private(set) var bootstrapInProgress = true
    @Published private(set) var maintenanceInProgress = false
    let helper: HelperSettingsModel
    private let overlapModelManager: AgentEmbeddingModelManager
    private let overlapStore: AgentOverlapStore
    private var overlapAnalysisTask: Task<Void, Error>?
    private var overlapAnalysisToken: UUID?
    private var modelDownloadTask: Task<Void, Error>?
    private var overlapIndex = AgentOverlapIndex()
    private var overlapPresentationRevision: String?
    private var overlapPresentationIDs = Set<String>()
    private struct AgentPreselectionKey: Equatable {
        let revision: String?
        let hasMatches: Bool
        let active, eligible, cache, manual, retained: Set<String>
        let threshold: Double
    }
    private var agentPreselectionKey: AgentPreselectionKey?
    private var agentPreselectedObjectIDs = Set<String>()
    private var agentPreselectionCalculationTask: Task<Set<String>?, Never>?
    private var agentPreselectionToken: UUID?
    private var agentOverlapFullRecalculationRequested = false
    private var autoSelectedAgentCandidateIDs = Set<UUID>()
    private var agentOverlapNeedsScanAnalysis = false
    private var currentAgentOverlapObjectIDs: Set<String> {
        Set(agentSkills.map { "skill|\($0.id)" }).union(agentMCPConfigurations.map { "mcp|\($0.id)" })
    }

    private let home: URL
    private let largeFilePreferences: UserDefaults
    private let fileSystem: any FileSystemAccess
    private let runtime: CleanupRuntime
    private var planBuilder: PlanBuilder {
        PlanBuilder(engineVersion: "1.1.0", ruleVersion: rulesetVersion, protectionPolicy: protectionPolicy)
    }
    private let recommendationPolicy = CleanupRecommendationPolicy()
    private let scopePolicy = CleanupScopePolicy()
    private let defaultCleanupPolicy = DefaultCleanupPolicy()
    private var largeFileCandidatesByPath: [String: CleanupCandidate] = [:]
    private let navigationPolicy = AppNavigationPolicy()
    private let cleanupExecutionCoordinator: CleanupExecutionCoordinator
    private var canStartUpdate: Bool {
        !updateInProgress && deepScanningApplicationID == nil && !bootstrapInProgress && !maintenanceInProgress && !helper.isChanging && !isLoadingApplications
            && !isScanRunning && phase != .executing && !oneClickCleanupIsRunning && recoveryActionReceiptID == nil
            && !receipts.contains { $0.results.contains { $0.verificationNotBefore != nil } }
    }
    lazy var applicationUpdates = ApplicationUpdateModel(
        canStart: { [weak self] in self?.canStartUpdate ?? false },
        activityChanged: { [weak self] in self?.updateInProgress = $0 },
        prepareHelper: { [weak self] in
            guard let self else { throw ApplicationUpdateError.busy }
            try await helper.prepareForApplicationUpdate()
        }, helperIsStopped: { [weak self] in
            self?.helper.isStopped ?? false
        })
    lazy var updates = UpdateSettingsModel(runtime: runtime,
        canStart: { [weak self] in self?.canStartUpdate ?? false }, activityChanged: { [weak self] in self?.updateInProgress = $0 },
        activated: { [weak self] pack in self?.rulesDidChange(pack) })
    private var scanTask: Task<Void, Never>?
    private var moduleScanTasks: [ScanModuleID: Task<Void, Never>] = [:]
    private var moduleScanTokens: [ScanModuleID: UUID] = [:]
    private var moduleScanSession: ModuleScanSession?
    private var readyScanModules = Set<ScanModuleID>()
    private var activeScanToken: UUID?
    private var activeScanGenerationID: UUID?
    private var scanCleanupReconciliation: ScanCleanupReconciliation?
    private var executionTask: Task<Void, Never>?
    private var executionProgressToken: UUID?
    private var pendingExecutionResults: [OperationResult] = []
    private var executionResultsTask: Task<Void, Never>?
    private var oneClickExecutionTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var oneClickCleanedCandidateIDs = Set<UUID>() {
        didSet {
            let agentChanged = (systemReport?.agentAssets ?? []).contains {
                oldValue.contains($0.id) != oneClickCleanedCandidateIDs.contains($0.id)
            }
            invalidateCandidatePresentationCaches(includingAgent: agentChanged)
            if agentChanged {
                invalidateAgentEnvironmentCaches()
                prepareAgentSkillPresentation()
            }
        }
    }
    private var cachedAllCandidates: [CleanupCandidate]?
    private var cachedCandidatesByDestination: [SidebarDestination: [CleanupCandidate]] = [:]
    private var cachedAgentAssets: [AgentAssetRecord]?
    private var cachedSelectedCandidates: [SidebarDestination: [CleanupCandidate]] = [:]
    private var cachedHiddenSelectedCounts: [SidebarDestination: Int] = [:]
    private var cachedDefaultCleanupSelection: DefaultCleanupSelection?
    private var cachedRecommendationBreakdowns: [SidebarDestination: CleanupRecommendationBreakdown] = [:]
    private var cachedApplicationUninstallPlans: [UninstallPlan]?
    private var cachedAgentSkillPresentation: AgentSkillCatalogPresentation?
    private var agentSkillPresentationTask: Task<Void, Never>?
    private var agentSkillPresentationToken: UUID?
    private var cachedScanDiscoverySummary: ScanDiscoverySummary?
    private var cachedAgentSkillPresentationSelectedIDs = Set<UUID>()
    private var cachedAgentCandidateByPath: [String: CleanupCandidate]?
    private var cachedVisibleAgentSkills: [AgentSkillCatalogSection]?
    private var cachedVisibleAgentMCPs: [MCPConfigurationRecord]?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, largeFilePreferences: UserDefaults = .standard) {
        self.home = home
        self.largeFilePreferences = largeFilePreferences
        protectionPolicy = ProtectionPolicy(homeDirectory: home)
        defaultQuarantineRetentionPolicy = QuarantineRetentionPolicy(storedValue: UserDefaults.standard.string(
            forKey: Self.quarantineRetentionDefaultsKey
        ))
        let storedLargeFileBytes = (largeFilePreferences.object(
            forKey: Self.largeFileThresholdDefaultsKey
        ) as? NSNumber)?.uint64Value
        largeFileThreshold = LargeFileThreshold(storedBytes: storedLargeFileBytes)
        preselectLargeFileInstallers = largeFilePreferences.object(forKey: Self.largeFileInstallerPreselectionDefaultsKey) as? Bool ?? true
        let storedOverlapThreshold = UserDefaults.standard.object(forKey: Self.agentOverlapThresholdDefaultsKey) as? NSNumber
        agentOverlapThreshold = min(1, max(0.5, storedOverlapThreshold?.doubleValue ?? 0.85))
        let infrastructure = AppInfrastructure.live(home: home)
        fileSystem = infrastructure.fileSystem
        helper = infrastructure.helper
        runtime = infrastructure.runtime
        cleanupExecutionCoordinator = infrastructure.cleanupCoordinator
        overlapModelManager = infrastructure.overlapModelManager
        overlapStore = infrastructure.overlapStore
        helper.configureAvailability { [weak self] in
            guard let self else { return false }
            return !updateInProgress && phase != .executing && !isScanRunning
        }
        Task {
            let state = await overlapModelManager.state()
            agentOverlapModelInstalled = state == .ready
            agentOverlapModelCanRemove = await overlapModelManager.canRemoveLocalModel()
        }
    }

    private static let quarantineRetentionDefaultsKey = "quarantine.retentionPolicy"
    private static let largeFileThresholdDefaultsKey = "largeFiles.minimumBytes"
    private static let largeFileInstallerPreselectionDefaultsKey = "largeFiles.preselectInstallers"
    private static let appManagementObservationDefaultsKey = "permissions.appManagementObservation"
    private static let pendingPermissionScanDefaultsKey = "permissions.pendingFullScan"
    private static let agentOverlapThresholdDefaultsKey = "agentOverlap.coverageThreshold"
    private static let agentOverlapRetainedDefaultsKey = "agentOverlap.retainedObjects.v3"

    func updateAgentOverlapThreshold(_ value: Double) {
        agentOverlapThreshold = min(1, max(0.5, value))
        UserDefaults.standard.set(agentOverlapThreshold, forKey: Self.agentOverlapThresholdDefaultsKey)
        refreshAgentOverlapPresentation()
        applyAgentAutoPreselection(from: agentOverlapMatches)
        if !isScanRunning, !agentOverlapAnalysisIsRunning, phase != .executing {
            agentOverlapStatus = L10n.text("已按 {0}% 阈值更新预选，复用已有包含关系", String(Int((agentOverlapThreshold * 100).rounded())))
        }
    }

    func downloadAgentOverlapModel() -> Task<Void, Error> {
        let task = Task {
            agentOverlapModelDownloadInProgress = true
            agentOverlapModelDownloadProgress = 0
            defer { agentOverlapModelDownloadInProgress = false }
            agentOverlapStatus = L10n.text("正在下载 EmbeddingGemma 2…")
            try await overlapModelManager.downloadModel { receivedBytes, expectedBytes in
                Task { @MainActor in
                    self.agentOverlapModelDownloadProgress = min(1, Double(receivedBytes) / Double(expectedBytes))
                }
            }
            agentOverlapModelDownloadProgress = nil
            agentOverlapModelInstalled = true
            agentOverlapModelCanRemove = true
            agentOverlapStatus = L10n.text("模型已安装")
            if isScanRunning { agentOverlapNeedsScanAnalysis = true }
            else { try await analyzeAgentOverlaps() }
        }
        modelDownloadTask = task
        return task
    }

    func startAgentOverlapModelDownload() {
        let task = downloadAgentOverlapModel()
        Task { finishAgentOverlapTask(await task.result) }
    }

    func finishAgentOverlapTask(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            break
        case .failure(let error):
            agentOverlapModelDownloadProgress = nil
            agentOverlapStatus = error is CancellationError || (error as? URLError)?.code == .cancelled
                ? L10n.text("模型下载已取消")
                : L10n.text("Agent 分析失败：{0}", String(describing: error.localizedDescription))
        }
    }

    private func finishAgentOverlapAnalysis(_ result: Result<Void, Error>, token: UUID) {
        guard overlapAnalysisToken == token else { return }
        defer { finishFullScanTimingIfIdle() }
        overlapAnalysisToken = nil
        overlapAnalysisTask = nil
        agentOverlapAnalysisIsRunning = false
        if case .failure(let error) = result {
            if case AgentOverlapError.requiresFullRecalculation = error {
                agentOverlapMatches = []
                agentOverlapMatchBySourceID = [:]
                selectedIDs.subtract(autoSelectedAgentCandidateIDs)
                autoSelectedAgentCandidateIDs.removeAll()
                applyAgentAutoPreselection(from: [])
                agentOverlapStatus = L10n.text("分析规则已更新，旧索引不能使用。请在设置中重新计算全部包含关系；完成后自动显示覆盖排名并勾选符合阈值的项目。")
                return
            }
            agentOverlapStatus = error is CancellationError
                ? L10n.text("Agent 分析已取消")
                : L10n.text("Agent 分析失败：{0}", error.localizedDescription)
        }
    }

    private var agentAnalysisDeferredForCleanup = false

    private func resumeDeferredAgentAnalysis() {
        guard agentAnalysisDeferredForCleanup, !isDeletionInProgress else { return }
        agentAnalysisDeferredForCleanup = false
        scheduleAgentOverlapAnalysis()
    }

    private func scheduleAgentOverlapAnalysis() {
        guard !isDeletionInProgress else { agentAnalysisDeferredForCleanup = true; return }
        overlapAnalysisTask?.cancel()
        let token = UUID()
        overlapAnalysisToken = token
        agentOverlapAnalysisIsRunning = true
        let task = Task { try await analyzeAgentOverlaps() }
        overlapAnalysisTask = task
        Task { finishAgentOverlapAnalysis(await task.result, token: token) }
    }

    private func analyzeAgentOverlapsDuringScan() async {
        guard isScanRunning else { return }
        guard !isDeletionInProgress else { agentAnalysisDeferredForCleanup = true; return }
        agentOverlapNeedsScanAnalysis = false
        overlapAnalysisTask?.cancel()
        let token = UUID()
        overlapAnalysisToken = token
        agentOverlapAnalysisIsRunning = true
        let task = Task { try await analyzeAgentOverlaps() }
        overlapAnalysisTask = task
        finishAgentOverlapAnalysis(await task.result, token: token)
    }

    func cancelAgentOverlapModelDownload() {
        modelDownloadTask?.cancel()
        agentOverlapStatus = L10n.text("模型下载已取消")
    }

    func removeAgentOverlapModel() -> Task<Void, Error> {
        Task {
            try await overlapModelManager.removeModel()
            agentOverlapModelInstalled = await overlapModelManager.state() == .ready
            agentOverlapModelCanRemove = await overlapModelManager.canRemoveLocalModel()
            agentOverlapStatus = L10n.text("已移除本机下载副本；App 内置模型仍可用")
        }
    }

    var canRecalculateAgentContainment: Bool {
        hasScanResult(for: .agentEnvironment) && agentOverlapModelInstalled && !isScanRunning
            && !agentOverlapAnalysisIsRunning && phase != .executing && !oneClickCleanupIsRunning
            && !updateInProgress && deepScanningApplicationID == nil
    }

    func recalculateAllAgentContainment() {
        guard canRecalculateAgentContainment else { return }
        agentOverlapFullRecalculationRequested = true
        agentOverlapNeedsScanAnalysis = true
        refreshModule(.agentEnvironment)
    }

    func analyzeAgentOverlaps() async throws {
        guard agentOverlapSupportedPlatform else { return }
        let generationID = systemReport?.generationID
        let policy = try AgentOverlapPolicy.load()
        let reset = agentOverlapFullRecalculationRequested
        agentOverlapFullRecalculationRequested = false
        agentOverlapStatus = L10n.text("正在读取本机能力索引…")
        let loaded = try await overlapStore.load(resetAnalysis: reset)
        try Task.checkCancellation()
        if !loaded.entries.isEmpty {
            guard loaded.modelVersion == GemmaTextEmbedder.modelVersion, loaded.analysisVersion == policy.fingerprint else {
                throw AgentOverlapError.requiresFullRecalculation
            }
        }
        guard systemReport?.generationID == generationID else { throw CancellationError() }
        var workingIndex = loaded
        var inputs = [AgentOverlapInput]()
        for skill in agentSkills {
            inputs.append(AgentOverlapInput(
                id: "skill|\(skill.id)", kind: .skill, title: skill.displayName,
                description: skill.summary ?? "", features: skill.functionalSections,
                contentVersion: String(data: try JSONEncoder().encode([skill.tags, skill.triggers, skill.tools,
                    [skill.pluginVersion ?? "", skill.parseStatus.rawValue]]), encoding: .utf8), platform: skill.provider
            ))
        }
        for configuration in agentMCPConfigurations {
            var features = [String]()
            for server in configuration.servers {
                let description = workingIndex.localMetadata["mcp|\(configuration.fileURL.path)|\(server.id)"]?.description ?? ""
                features.append(description.isEmpty ? server.name : description)
            }
            inputs.append(AgentOverlapInput(
                id: "mcp|\(configuration.id)", kind: .mcp,
                title: configuration.sourceLabel + " · " + configuration.fileURL.lastPathComponent,
                description: features.joined(separator: "; "), features: features, contentVersion: configuration.contentFingerprint,
                platform: configuration.provider
            ))
        }
        var metadataChanged = AgentOverlapAnalyzer.refreshMetadata(inputs: inputs, index: &workingIndex, policy: policy)
        if AgentOverlapAnalyzer.canReuse(inputs: inputs, index: workingIndex) {
            if workingIndex.completeIDs == nil || reset {
                workingIndex.completeIDs = Set(inputs.map(\.id))
                workingIndex.modelVersion = GemmaTextEmbedder.modelVersion
                workingIndex.analysisVersion = policy.fingerprint
                metadataChanged = true
            }
            if metadataChanged {
                try Task.checkCancellation()
                guard systemReport?.generationID == generationID else { throw CancellationError() }
                try await overlapStore.save(workingIndex)
                workingIndex = try await overlapStore.load(resetAnalysis: false)
            }
            try Task.checkCancellation()
            guard systemReport?.generationID == generationID else { throw CancellationError() }
            overlapIndex = workingIndex
            refreshAgentOverlapPresentation()
            agentOverlapStatus = L10n.text("复用 {0} 项已知数据；内容未变化，未重新分析", String(inputs.count))
            applyAgentAutoPreselection(from: agentOverlapMatches)
            return
        }
        guard await overlapModelManager.state() == .ready else {
            try Task.checkCancellation()
            // Never present stale coverage as current after a content change.
            agentOverlapMatches = []; agentOverlapMatchBySourceID = [:]; overlapPresentationRevision = nil
            agentOverlapStatus = L10n.text("尚未安装模型；扫描仍可正常使用")
            return
        }
        let provider = try await overlapModelManager.loadProvider()
        try Task.checkCancellation()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: GemmaTextEmbedder.modelVersion, policy: policy)
        let dirtyKinds = Set(inputs.filter { workingIndex.entries[$0.id]?.inputFingerprint != $0.fingerprint }.map { $0.kind.rawValue })
        let unchangedIDs = Set(inputs.filter { workingIndex.entries[$0.id]?.inputFingerprint == $0.fingerprint }.map(\.id))
        let needsRepair = !AgentOverlapAnalyzer.hasCompleteRelationships(in: workingIndex, activeIDs: unchangedIDs)
        let vectorIDs = Set(inputs.filter {
            unchangedIDs.contains($0.id) && (needsRepair || dirtyKinds.contains($0.kind.rawValue))
        }.map(\.id))
        let hydrated = try await overlapStore.hydrating(workingIndex, ids: vectorIDs)
        agentOverlapStatus = L10n.text("正在分析新增或已修改对象的能力包含关系…")
        let result = try await analyzer.analyze(inputs: inputs, index: hydrated)
        try Task.checkCancellation()
        guard systemReport?.generationID == generationID else { throw CancellationError() }
        try await overlapStore.save(result.index)
        try Task.checkCancellation()
        workingIndex = try await overlapStore.load(resetAnalysis: false)
        try Task.checkCancellation()
        guard systemReport?.generationID == generationID else { throw CancellationError() }
        overlapIndex = workingIndex
        refreshAgentOverlapPresentation()
        let qualified = agentOverlapMatches.filter { $0.coverage >= agentOverlapThreshold }.count
        agentOverlapStatus = L10n.text(
            "新增或更新 {0} 项，复用 {1} 项；计算 {2} 对关系，{3} 项联合包含达到阈值",
            String(result.addedIDs.count + result.changedIDs.count), String(inputs.count - result.addedIDs.count - result.changedIDs.count),
            String(result.calculatedPairCount), String(qualified)
        )
        applyAgentAutoPreselection(from: agentOverlapMatches)
    }

    private func refreshAgentOverlapPresentation() {
        let ids = currentAgentOverlapObjectIDs
        if let revision = overlapIndex.revision, revision == overlapPresentationRevision,
           ids == overlapPresentationIDs { return }
        overlapPresentationRevision = overlapIndex.revision
        overlapPresentationIDs = ids
        agentOverlapMatches = AgentOverlapAnalyzer.recommendations(in: overlapIndex, activeIDs: currentAgentOverlapObjectIDs)
        agentOverlapMatchBySourceID = Dictionary(uniqueKeysWithValues: agentOverlapMatches.map { ($0.sourceID, $0) })
    }

    private var agentContainmentCandidateIDs: [String: Set<UUID>] {
        var result = agentSkillCatalogPresentation.bindingsByID.reduce(into: [String: Set<UUID>]()) { mapping, element in
            mapping["skill|\(element.key)"] = element.value.selectableCandidateIDs
        }
        for configuration in agentMCPConfigurations {
            if let candidate = agentMCPCandidate(for: configuration) { result["mcp|\(configuration.id)"] = [candidate.id] }
        }
        return result
    }

    private func rememberAgentObjectDecision(_ objectID: String, selected: Bool) {
        var retained = Set(UserDefaults.standard.stringArray(forKey: Self.agentOverlapRetainedDefaultsKey) ?? [])
        if selected { retained.remove(objectID) }
        else { retained.insert(objectID) }
        UserDefaults.standard.set(retained.sorted(), forKey: Self.agentOverlapRetainedDefaultsKey)
    }

    private func applyAgentAutoPreselection(from matches: [AgentOverlapMatch]) {
        guard !isScanRunning, phase != .executing, !preparingAgentSkillPresentation else { return }
        let cacheIDs = agentObjectIDs(under: ".cache")
        let globalIDs = Set(agentSkills.filter { $0.scope != .project }.map { "skill|\($0.id)" })
            .union(agentMCPConfigurations.filter { $0.scope != .project }.map { "mcp|\($0.id)" })
            .subtracting(cacheIDs)
        let retained = Set(UserDefaults.standard.stringArray(forKey: Self.agentOverlapRetainedDefaultsKey) ?? [])
            .union(globalIDs)
        let units = agentContainmentCandidateIDs
        var eligible = Set(agentSkillCatalogPresentation.bindingsByID.values.filter(\.isDeletionAvailable).map { "skill|\($0.id)" })
        for configuration in agentMCPConfigurations {
            if agentMCPCandidate(for: configuration)?.risk.isSelectable == true { eligible.insert("mcp|\(configuration.id)") }
        }
        let manual = selectedIDs.subtracting(autoSelectedAgentCandidateIDs)
        let manuallySelectedObjects = Set(units.filter { !$0.value.isDisjoint(with: manual) }.map(\.key))
        let active = Set(units.keys)
        let key = AgentPreselectionKey(revision: overlapIndex.revision, hasMatches: !matches.isEmpty,
            active: active, eligible: eligible, cache: cacheIDs, manual: manuallySelectedObjects,
            retained: retained, threshold: agentOverlapThreshold)
        if agentPreselectionKey == key, overlapIndex.revision != nil {
            installAgentPreselection(agentPreselectedObjectIDs, units: units)
            return
        }
        agentPreselectionCalculationTask?.cancel()
        let token = UUID()
        agentPreselectionToken = token
        let index = matches.isEmpty ? AgentOverlapIndex() : overlapIndex
        let cachedRecommendations = active == currentAgentOverlapObjectIDs ? matches : nil
        let calculation = Task.detached(priority: .userInitiated) { () -> Set<String>? in
            guard !Task.isCancelled else { return nil }
            let sources = AgentOverlapAnalyzer.preselectedSourceIDs(
                index: index, activeIDs: active, eligibleIDs: eligible,
                cacheIDs: cacheIDs, manuallySelectedIDs: manuallySelectedObjects, retainedIDs: retained,
                threshold: key.threshold, cachedRecommendations: cachedRecommendations, globalIDs: globalIDs)
            return Task.isCancelled ? nil : sources
        }
        agentPreselectionCalculationTask = calculation
        Task { [weak self] in
            guard let sources = await calculation.value, !Task.isCancelled,
                  let self, agentPreselectionToken == token else { return }
            agentPreselectionCalculationTask = nil
            agentPreselectionKey = key
            agentPreselectedObjectIDs = sources
            installAgentPreselection(sources, units: units)
            finishFullScanTimingIfIdle()
        }
    }

    private func installAgentPreselection(_ sources: Set<String>, units: [String: Set<UUID>]) {
        let desired = Set(sources.flatMap { units[$0] ?? [] })
        selectedIDs.subtract(autoSelectedAgentCandidateIDs)
        selectedIDs.formUnion(desired)
        autoSelectedAgentCandidateIDs = desired
    }

    private func agentObjectIDs(under relativePath: String) -> Set<String> {
        let prefix = home.appendingPathComponent(relativePath).standardizedFileURL.path + "/"
        var result = Set(agentSkills.filter { $0.skillRootURL.path.hasPrefix(prefix) }.map { "skill|\($0.id)" })
        result.formUnion(agentMCPConfigurations.filter { $0.fileURL.path.hasPrefix(prefix) }.map { "mcp|\($0.id)" })
        return result
    }

    var hasCompletedScan: Bool { systemReport?.isCommitEligible == true }

    var isDeletionInProgress: Bool { phase == .executing || oneClickCleanupIsRunning }
    var showsDeletionSheet: Bool { isDeletionInProgress || deletionResult?.results.contains(where: { DeletionResultPresentation.outcome(for: $0) == .deleted }) == true }

    func dismissDeletionSheet() {
        guard !isDeletionInProgress else { return }
        deletionResult = nil
        deletionResultWarning = nil
    }

    func hasScanResult(for module: ScanModuleID) -> Bool {
        scanResultDestination(for: module) != nil
    }

    func hasDiscoveredContent(for module: ScanModuleID) -> Bool {
        guard let systemReport else { return false }
        return switch module {
        case .general: !systemReport.generalCandidates.isEmpty
        case .applications: !systemReport.applicationInventory.applications.isEmpty
        case .largeFiles: !systemReport.largeFileCandidates.isEmpty
        case .agentEnvironment: !systemReport.agentAssets.isEmpty
        }
    }

    func showsScanningPlaceholder(for destination: SidebarDestination) -> Bool {
        let availableModules = Set(ScanModuleID.allCases.filter { hasScanResult(for: $0) })
        return navigationPolicy.showsScanningPlaceholder(
            for: destination,
            globalScanIsRunning: isScanRunning,
            availableModules: availableModules
        )
    }

    func openScanResult(_ module: ScanModuleID) {
        let destination: AppDestination = switch module {
        case .general: .systemCleanup
        case .applications: .applications
        case .largeFiles: .largeFiles
        case .agentEnvironment: .agentEnvironment
        }
        if destination == .systemCleanup {
            openCleanupCenter()
        } else {
            selection = destination
        }
    }
    var candidates: [CleanupCandidate] {
        if let cachedAllCandidates { return cachedAllCandidates }
        let result = CleanupCandidateVisibility.remaining(
            candidates: systemReport?.candidates ?? [],
            cleanedCandidateIDs: oneClickCleanedCandidateIDs
        ).map(protectionPolicy.applying)
        cachedAllCandidates = result
        return result
    }
    var applications: [InstalledApplication] {
        let scanned = systemReport?.applicationInventory.applications ?? []
        guard let runningApplicationIDs else { return scanned }
        return scanned.map { $0.withRunningState(runningApplicationIDs.contains($0.bundleIdentifier)) }
    }
    var diskUsageTree: DiskUsageTree? { systemReport?.diskUsageTree }
    var largeFileThresholdNeedsRefresh: Bool {
        guard let diskUsageTree else { return false }
        return diskUsageTree.minimumFileBytes != largeFileThreshold.bytes
    }
    var agentAssets: [AgentAssetRecord] {
        if let cachedAgentAssets { return cachedAgentAssets }
        let cleanedIDs = oneClickCleanedCandidateIDs
        let assets = (systemReport?.agentAssets ?? []).filter { !cleanedIDs.contains($0.id) }
        cachedAgentAssets = assets
        return assets
    }
    var detectedAgentProviders: [AgentProvider] {
        guard let report = systemReport else { return [] }
        var detected = Set(report.agentProviderCoverage.values
            .filter { $0.detectedRootCount > 0 }
            .map(\.provider))
        detected.formUnion(report.agentAssets.map(\.provider))
        detected.formUnion(report.agentSkills.map(\.provider))
        detected.formUnion(report.agentMCPConfigurations.map(\.provider))
        return AgentProvider.allCases.filter { detected.contains($0) }
    }
    var agentSkills: [SkillCatalogEntry] { systemReport?.agentSkills ?? [] }
    var agentMCPConfigurations: [MCPConfigurationRecord] { systemReport?.agentMCPConfigurations ?? [] }
    var agentSkillDuplicatesCollapsedCount: Int {
        systemReport?.agentSkillDuplicatesCollapsedCount ?? 0
    }
    var agentEnvironmentProgressMessage: String? {
        if isScanRunning {
            switch scanProgressByModule[.agentEnvironment]?.state {
            case .waiting: return L10n.text("正在等待扫描 Agent 环境…")
            case .scanning: return L10n.text("正在扫描 Agent 环境，发现 Skill 与 MCP 配置…")
            default: break
            }
        }
        if preparingAgentSkillPresentation { return L10n.text("正在准备 Agent 列表…") }
        if agentOverlapAnalysisIsRunning { return L10n.text("正在分析 Skill 与 MCP 的能力覆盖关系…") }
        if agentPreselectionCalculationTask != nil { return L10n.text("正在生成 Agent 预选建议…") }
        return nil
    }
    var agentSkillCatalogPresentation: AgentSkillCatalogPresentation {
        if let cachedAgentSkillPresentation {
            guard cachedAgentSkillPresentationSelectedIDs != selectedIDs else { return cachedAgentSkillPresentation }
            let updated = cachedAgentSkillPresentation.selecting(selectedIDs)
            self.cachedAgentSkillPresentation = updated
            cachedAgentSkillPresentationSelectedIDs = selectedIDs
            return updated
        }
        let presentation = AgentSkillCatalogPresentation(
            skills: agentSkills,
            assets: agentAssets,
            selectedIDs: selectedIDs
        )
        cachedAgentSkillPresentation = presentation
        cachedAgentSkillPresentationSelectedIDs = selectedIDs
        return presentation
    }
    var visibleAgentSkillSections: [AgentSkillCatalogSection] {
        if let cachedVisibleAgentSkills { return cachedVisibleAgentSkills }
        let sections = agentSkillCatalogPresentation.filteredSections(
            query: "",
            scope: nil,
            provider: agentProviderFilter,
            deletableOnly: false
        ).compactMap { section in
            let skills = section.skills.filter { binding in
                agentItemsSelectionFilter == .all || binding.decision == .plannedForDeletion
            }.sorted(by: compareSkillContainment)
            guard !skills.isEmpty else { return nil }
            return AgentSkillCatalogSection(group: section.group, skills: skills)
        }.sorted(by: compareSkillSections)
        cachedVisibleAgentSkills = sections
        return sections
    }
    var visibleAgentSkillBindings: [AgentSkillCleanupBinding] {
        visibleAgentSkillSections.flatMap(\.skills)
    }
    var visibleAgentMCPConfigurations: [MCPConfigurationRecord] {
        if let cachedVisibleAgentMCPs { return cachedVisibleAgentMCPs }
        let configurations = agentMCPConfigurations.filter { configuration in
            let providerMatches = agentProviderFilter == nil || configuration.provider == agentProviderFilter
            guard providerMatches else { return false }
            guard agentItemsSelectionFilter == .selected else { return true }
            guard let candidate = agentMCPCandidate(for: configuration) else { return false }
            return selectedIDs.contains(candidate.id)
        }.sorted(by: compareMCPContainment)
        cachedVisibleAgentMCPs = configurations
        return configurations
    }

    private func compareSkillContainment(_ lhs: AgentSkillCleanupBinding, _ rhs: AgentSkillCleanupBinding) -> Bool {
        let left = agentOverlapMatchBySourceID["skill|\(lhs.id)"]?.maximumSingleCoverage ?? 0
        let right = agentOverlapMatchBySourceID["skill|\(rhs.id)"]?.maximumSingleCoverage ?? 0
        if left != right { return left > right }
        if lhs.reclaimableBytes != rhs.reclaimableBytes { return lhs.reclaimableBytes > rhs.reclaimableBytes }
        return lhs.id < rhs.id
    }

    private func compareSkillSections(_ lhs: AgentSkillCatalogSection, _ rhs: AgentSkillCatalogSection) -> Bool {
        let left = lhs.skills.first.flatMap { agentOverlapMatchBySourceID["skill|\($0.id)"]?.maximumSingleCoverage } ?? 0
        let right = rhs.skills.first.flatMap { agentOverlapMatchBySourceID["skill|\($0.id)"]?.maximumSingleCoverage } ?? 0
        if left != right { return left > right }
        return lhs.group.sortOrder != rhs.group.sortOrder ? lhs.group.sortOrder < rhs.group.sortOrder : lhs.group.id < rhs.group.id
    }

    private func compareMCPContainment(_ lhs: MCPConfigurationRecord, _ rhs: MCPConfigurationRecord) -> Bool {
        let left = agentOverlapMatchBySourceID["mcp|\(lhs.id)"]?.maximumSingleCoverage ?? 0
        let right = agentOverlapMatchBySourceID["mcp|\(rhs.id)"]?.maximumSingleCoverage ?? 0
        return left != right ? left > right : lhs.id < rhs.id
    }

    func agentMCPCandidate(for configuration: MCPConfigurationRecord) -> CleanupCandidate? {
        if let cachedAgentCandidateByPath {
            return cachedAgentCandidateByPath[configuration.fileURL.path]
        }
        let candidatesByPath = agentAssets.reduce(into: [String: CleanupCandidate]()) { result, asset in
            result[asset.candidate.url.standardizedFileURL.path] = asset.candidate
        }
        cachedAgentCandidateByPath = candidatesByPath
        return candidatesByPath[configuration.fileURL.path]
    }
    var currentAgentCleanupPresentation: AgentCleanupPresentation? {
        guard agentCleanupGenerationID == systemReport?.generationID,
              agentCleanupPresentation?.provider == agentProviderFilter else { return nil }
        return agentCleanupPresentation
    }
    private var currentScanModule: ScanModuleID? {
        switch selection {
        case .systemCleanup: .general
        case .applications: .applications
        case .largeFiles: .largeFiles
        case .agentEnvironment: .agentEnvironment
        default: nil
        }
    }

    var isCurrentModuleScanning: Bool {
        navigationPolicy.showsModuleScanControls(
            for: selection,
            globalScanIsRunning: isScanRunning,
            moduleState: currentScanModule.flatMap { scanProgressByModule[$0]?.state }
        )
    }

    var selectedCandidates: [CleanupCandidate] {
        if let cached = cachedSelectedCandidates[selection] { return cached }
        let scoped = selection == .largeFiles && showsDuplicateLargeFilesOnly
            ? duplicateLargeFiles : candidates(for: selection)
        let selected = scoped.filter { selectedIDs.contains($0.id) }
        cachedSelectedCandidates[selection] = selected
        return selected
    }

    var duplicateLargeFiles: [CleanupCandidate] {
        candidates(for: .largeFiles).filter { $0.largeFileProof != nil && $0.largeFileRecommendation != nil }
    }
    var selectedBytes: UInt64 { selectedCandidates.reduce(0) { $0 + $1.bytes } }
    var focusedCandidateID: UUID? { focusState.focusedCandidateID }
    var inspectedCandidate: CleanupCandidate? {
        guard let focusedCandidateID else { return nil }
        return visibleCandidates(for: selection).first { $0.id == focusedCandidateID }
    }
    var hiddenSelectedCount: Int {
        if let cached = cachedHiddenSelectedCounts[selection] { return cached }
        let visible = Set(visibleCandidates(for: selection).map(\.id))
        let count = Set(selectedCandidates.map(\.id)).subtracting(visible).count
        cachedHiddenSelectedCounts[selection] = count
        return count
    }
    var isCleanupStrategyAdjusted: Bool { !excludedBaseIDs.isEmpty }

    var scanDiscoverySummary: ScanDiscoverySummary? {
        if let cachedScanDiscoverySummary { return cachedScanDiscoverySummary }
        guard let systemReport else { return nil }
        let summary = ScanDiscoverySummary(report: systemReport)
        cachedScanDiscoverySummary = summary
        return summary
    }
    var defaultCleanupSelection: DefaultCleanupSelection? {
        guard let report = systemReport else { return nil }
        let defaults: DefaultCleanupSelection
        if let cachedDefaultCleanupSelection {
            defaults = cachedDefaultCleanupSelection
        } else {
            let proposed = defaultCleanupPolicy.selection(for: report)
            let excludedIDs = oneClickCleanedCandidateIDs.union(cleanupFailures.map(\.candidate.id))
            defaults = DefaultCleanupSelection(
                systemCleanup: proposed.systemCleanup.filter { !excludedIDs.contains($0.id) && (try? protectionPolicy.validate($0.url)) != nil },
                applicationUninstall: [],
                largeFiles: proposed.largeFiles.filter { !excludedIDs.contains($0.id) && (try? protectionPolicy.validate($0.url)) != nil },
                agentEnvironment: [])
            cachedDefaultCleanupSelection = defaults
        }
        return DefaultCleanupSelection(
            systemCleanup: hasScanResult(for: .general) ? defaults.systemCleanup : [],
            applicationUninstall: [],
            largeFiles: hasScanResult(for: .largeFiles) ? defaults.largeFiles : [],
            agentEnvironment: []
        )
    }
    var canRunOneClickCleanup: Bool {
        canExecuteCleanup(in: .general, hasSelection: !(defaultCleanupSelection?.systemCleanup.isEmpty ?? true))
    }

    func oneClickStatus(for module: ScanModuleID) -> String? {
        if oneClickActiveModules.contains(module) { return L10n.text("正在清理默认项…") }
        if let result = oneClickCompletedByModule[module] {
            return result.itemCount > 0
                ? L10n.text("已清理 {0} 项 · {1}", String(describing: result.itemCount), String(describing: ByteCountFormatter.cleanerString(bytes: result.bytes)))
                : L10n.text("无需清理")
        }
        guard hasScanResult(for: module) else { return nil }
        if module == .applications { return L10n.text("请手动选择要卸载的项目") }
        let count = defaultCleanupCount(for: module)
        if module == .general,
           defaultCleanupSelection?.systemCleanup.contains(where: { candidate in
               candidate.evidence.contains { $0.code == "active-cleanup" }
           }) == true {
            return L10n.text("已默认勾选 {0} 项；运行中缓存可能重新生成", String(describing: count))
        }
        if count > 0 { return L10n.text("已默认勾选 {0} 项", String(describing: count)) }
        return module == .largeFiles
            ? L10n.text("无安全默认项 · 可手动选择")
            : L10n.text("无需默认清理")
    }

    func failedCleanupResult(for module: ScanModuleID) -> OneClickCleanupResult {
        let pending = cleanupFailures.map(\.candidate).filter { oneClickModule(for: $0) == module }
        return OneClickCleanupResult(
            itemCount: pending.count,
            bytes: pending.reduce(0) { $0 + $1.bytes }
        )
    }

    func hasCleanupFailures(for module: ScanModuleID) -> Bool {
        failedCleanupResult(for: module).itemCount > 0
    }

    private func defaultCleanupCount(for module: ScanModuleID) -> Int {
        guard let defaults = defaultCleanupSelection else { return 0 }
        switch module {
        case .general: return defaults.systemCleanup.count
        case .applications: return defaults.applicationUninstall.count
        case .largeFiles: return defaults.largeFiles.count
        case .agentEnvironment: return defaults.agentEnvironment.count
        }
    }
    var visibleApplications: [InstalledApplication] {
        let filtered = ApplicationListFilter(query: applicationQuery, scope: applicationScope)
            .apply(to: accessibleApplications)
        let selectedApplicationURLs = applicationSortOrder == .selection
            ? Set(applicationUninstallPlans.compactMap { plan in
                plan.items.contains(where: { uninstallSelectedIDs.contains($0.id) })
                    ? plan.application.bundleURL.standardizedFileURL
                    : nil
            }).union(quitSelectedApplicationIDs)
            : []
        return applicationSortOrder.sorted(filtered, selectedApplicationURLs: selectedApplicationURLs)
    }
    var applicationFilterSummary: ApplicationFilterSummary {
        ApplicationFilterSummary(visibleCount: visibleApplications.count, totalCount: accessibleApplications.count,
            canClear: applicationScope != .all || !applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var applicationScanPresentation: ScanAccessPresentation {
        ScanAccessPresentation(deniedPaths: scanDeniedPaths[.applications] ?? [])
    }
    private var accessibleApplications: [InstalledApplication] {
        applications.filter { !applicationScanPresentation.skips($0.bundleURL) }
    }
    private var applicationIDsAwaitingQuitAnalysis: Set<URL> {
        guard let runningApplicationIDs, let inventory = systemReport?.applicationUninstallInventory else { return [] }
        return Set(inventory.analyses.compactMap { analysis in
            let app = analysis.application
            return app.isRunning && !app.isSystem && analysis.preparedPlan == nil
                && !runningApplicationIDs.contains(app.bundleIdentifier) ? app.id : nil
        })
    }
    var applicationUninstallPlans: [UninstallPlan] {
        if let cachedApplicationUninstallPlans { return cachedApplicationUninstallPlans }
        let available = systemReport?.applicationUninstallInventory.analyses.compactMap { analysis in
            analysis.withRunningState(runningApplicationIDs?.contains(analysis.application.bundleIdentifier)
                ?? analysis.application.isRunning).plan
        } ?? []
        let plans = available.filter {
            runningApplicationIDs?.contains($0.application.bundleIdentifier) != true
        }.map { plan in
            UninstallPlan(id: plan.id, application: plan.application, items: plan.items.map {
                UninstallItem(candidate: protectionPolicy.applying(to: $0.candidate), containsUserData: $0.containsUserData, isShared: $0.isShared)
            })
        }
        cachedApplicationUninstallPlans = plans
        return plans
    }
    var uninstallBatchSummary: UninstallBatchSummary {
        uninstallSelectionState.summary(plans: applicationUninstallPlans)
    }
    private func canExecuteCleanup(in module: ScanModuleID, hasSelection: Bool) -> Bool {
        hasScanResult(for: module) && hasSelection
            && !updateInProgress && deepScanningApplicationID == nil
            && !isLoadingApplications && phase != .executing && !oneClickCleanupIsRunning
    }

    var canExecuteSelection: Bool {
        guard let module = currentScanModule else { return false }
        if module == .largeFiles, isCurrentModuleScanning || largeFileThresholdNeedsRefresh { return false }
        return canExecuteCleanup(in: module, hasSelection: !selectedCandidates.isEmpty)
    }

    var canExecuteUninstallBatch: Bool {
        canExecuteCleanup(in: .applications, hasSelection: uninstallBatchSummary.itemCount > 0)
    }

    func uninstallAnalysis(for application: InstalledApplication) -> ApplicationUninstallAnalysis? {
        guard let analysis = systemReport?.applicationUninstallInventory.analysis(for: application.id) else { return nil }
        if application.isRunning && !application.isSystem {
            return ApplicationUninstallAnalysis(application: application, plan: nil, state: .protected,
                message: L10n.text("应用正在运行，因此暂时不能卸载。退出应用后会自动更新。"),
                ownership: analysis.ownership, runtimeObservation: analysis.runtimeObservation)
        }
        if analysis.application.isRunning && analysis.preparedState == nil && !application.isSystem { return nil }
        let available = analysis.withRunningState(application.isRunning)
        return ApplicationUninstallAnalysis(application: application,
            plan: applicationUninstallPlans.first { $0.application.id == application.id }, state: available.state,
            message: available.message, limitations: available.limitations, ownership: available.ownership, runtimeObservation: available.runtimeObservation)
    }

    func openOfficialUninstaller(for application: InstalledApplication, expectedURL: URL) {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard !isScanRunning, phase != .executing else { return }
        Task {
            do {
                let configuration = try await runtime.configuration()
                let current = await ApplicationScanner().associationIndex(for: applications, context: configuration.context)
                guard current.ownershipGraph?.application(at: application.id)?.installation.officialUninstaller == expectedURL else {
                    throw ApplicationExecutionRejection.ownershipChanged
                }
                try OfficialApplicationUninstaller.validate(expectedURL, for: application)
                _ = try await NSWorkspace.shared.openApplication(at: expectedURL, configuration: NSWorkspace.OpenConfiguration())
                configurationMessage = L10n.text("已打开官方卸载器；其操作不属于本应用的隔离恢复。完成后请刷新应用。")
            } catch { configurationMessage = L10n.text("未打开卸载器：{0}", String(describing: error.localizedDescription)) }
        }
    }

    func uninstallSelectionState(for plan: UninstallPlan) -> SelectionTriState {
        uninstallSelectionState.selectionState(for: plan)
    }

    func isUninstallItemSelected(_ item: UninstallItem) -> Bool {
        uninstallSelectedIDs.contains(item.id)
    }

    func disposition(for candidate: CleanupCandidate) -> CleanupDisposition {
        recommendationPolicy.disposition(for: candidate)
    }

    func candidates(for destination: SidebarDestination, disposition: CleanupDisposition) -> [CleanupCandidate] {
        candidates(for: destination).filter { recommendationPolicy.disposition(for: $0) == disposition }
    }

    func recommendationBreakdown(for destination: SidebarDestination) -> CleanupRecommendationBreakdown {
        if let cached = cachedRecommendationBreakdowns[destination] { return cached }
        let result = recommendationPolicy.breakdown(for: candidates(for: destination))
        cachedRecommendationBreakdowns[destination] = result
        return result
    }

    func candidates(for destination: SidebarDestination) -> [CleanupCandidate] {
        if let cached = cachedCandidatesByDestination[destination] { return cached }
        if destination == .agentEnvironment {
            let result = agentAssets.map(\.candidate)
            cachedCandidatesByDestination[destination] = result
            return result
        }
        let scoped = destination == .largeFiles ? (systemReport?.largeFileCandidates ?? [])
            : scopePolicy.candidates(for: destination, from: systemReport?.candidates ?? [])
        let access = ScanAccessPresentation(deniedPaths: Set(scanDeniedPaths.values.flatMap { $0 }))
        let result = CleanupCandidateVisibility.remaining(
            candidates: scoped.filter { !access.cannotInspectWholeItem($0.url) },
            cleanedCandidateIDs: oneClickCleanedCandidateIDs
        ).map(protectionPolicy.applying)
        cachedCandidatesByDestination[destination] = result
        return result
    }

    func visibleCandidates(for destination: SidebarDestination) -> [CleanupCandidate] {
        if destination == .agentEnvironment {
            let visibleIDs: Set<UUID>
            if agentEnvironmentSection == .skills {
                visibleIDs = Set(visibleAgentSkillBindings.flatMap { $0.linkedAssets.map(\.id) })
            } else {
                visibleIDs = Set(visibleAgentMCPConfigurations.compactMap { agentMCPCandidate(for: $0)?.id })
            }
            return candidates(for: destination).filter { visibleIDs.contains($0.id) }
        }
        let filter = ReviewCandidateFilter(
            query: reviewQuery,
            risks: Set(RiskLevel.allCases),
            selectedOnly: showsSelectedOnly
        )
        return candidates(for: destination).filter {
            let matchesDisposition = destination == .largeFiles
                || reviewDispositionFilter.dispositions.contains(recommendationPolicy.disposition(for: $0))
            return filter.includes($0, selectedIDs: selectedIDs) && matchesDisposition
        }
        .sorted { lhs, rhs in
            let lhsSelected = selectedIDs.contains(lhs.id)
            let rhsSelected = selectedIDs.contains(rhs.id)
            if lhsSelected != rhsSelected { return lhsSelected }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }

    func bootstrap() {
        helper.refresh()
        // Reopening a window must not restart initialization or maintenance.
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await bootstrapPersistentState()
            bootstrapInProgress = false
            await resumePendingPermissionScanIfPossible()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                helper.refresh()
                await recheckPendingExecutions()
                await runQuarantineMaintenance()
            }
        }
    }

    private func recheckPendingExecutions() async {
        guard !updateInProgress, !maintenanceInProgress, recoveryActionReceiptID == nil else { return }
        guard phase != .executing, !isScanRunning else { return }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        do {
            let recovered = try await cleanupExecutionCoordinator.recoverPendingExecutions()
            guard !recovered.isEmpty else { return }
            await reloadHistory()
            await reloadQuarantineSchedules()
            let pendingCount = recovered.flatMap(\.results).filter { $0.verificationNotBefore != nil }.count
            recoveryMessage = pendingCount > 0 ? L10n.text("{0} 项 Helper 结果仍待复验，日志和隔离路径保持保留", String(describing: pendingCount)) : L10n.text("已按文件身份复验未完成的清理记录")
            recoveryMessageIsError = pendingCount > 0
        } catch { recoveryMessage = L10n.text("未完成记录复验失败：{0}", String(describing: error.localizedDescription)); recoveryMessageIsError = true }
    }

    func updateDefaultQuarantineRetentionPolicy(_ policy: QuarantineRetentionPolicy) {
        defaultQuarantineRetentionPolicy = policy
        UserDefaults.standard.set(policy.rawValue, forKey: Self.quarantineRetentionDefaultsKey)
    }

    func chooseProtectedPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.text("保护所选路径")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { [weak self] in
            guard let self else { return }
            do {
                for url in urls { protectionPolicy = try await runtime.protections.protect(url) }
                reconcileProtectedSelections()
                configurationMessage = L10n.text("保护清单已保存；执行前会重新检查")
            } catch { configurationMessage = L10n.text("无法保存保护清单：{0}", String(describing: error.localizedDescription)) }
        }
    }

    func protect(_ candidate: CleanupCandidate) {
        Task { [weak self] in
            guard let self else { return }
            do {
                protectionPolicy = try await runtime.protections.protect(candidate.url)
                reconcileProtectedSelections()
                configurationMessage = L10n.text("已保护 {0}", String(describing: candidate.displayName))
            } catch { configurationMessage = L10n.text("无法保存保护清单：{0}", String(describing: error.localizedDescription)) }
        }
    }

    func removeProtection(_ entry: ProtectedPath) {
        Task { [weak self] in
            guard let self else { return }
            do {
                protectionPolicy = try await runtime.protections.remove(id: entry.id)
                configurationMessage = L10n.text("已取消保护；重新扫描后可重新选择")
            } catch { configurationMessage = L10n.text("无法更新保护清单：{0}", String(describing: error.localizedDescription)) }
        }
    }

    private func reconcileProtectedSelections() {
        let ids = Set(allKnownCleanupCandidates.filter { (try? protectionPolicy.validate($0.url)) == nil }.map(\.id))
        selectedIDs.subtract(ids)
        uninstallSelectedIDs.subtract(ids)
        excludedBaseIDs.formUnion(ids)
    }

    func updateLargeFileThreshold(_ threshold: LargeFileThreshold) {
        guard threshold != largeFileThreshold else { return }
        largeFileThreshold = threshold
        largeFilePreferences.set(NSNumber(value: threshold.bytes), forKey: Self.largeFileThresholdDefaultsKey)
        if hasCompletedScan {
            statusMessage = L10n.text("大文件标准已改为 ≥ {0}，刷新后应用", String(describing: threshold.shortTitle))
        }
    }

    func updateLargeFileInstallerPreselection(_ enabled: Bool) {
        guard enabled != preselectLargeFileInstallers else { return }
        preselectLargeFileInstallers = enabled
        largeFilePreferences.set(enabled, forKey: Self.largeFileInstallerPreselectionDefaultsKey)
    }

    func quarantineSchedule(for receiptID: UUID) -> QuarantineSchedule? {
        quarantineSchedules[receiptID]
    }

    func rescheduleQuarantine(_ receipt: OperationReceipt, policy: QuarantineRetentionPolicy) {
        guard recoveryActionReceiptID == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await cleanupExecutionCoordinator.reschedule(
                    receiptID: receipt.id,
                    policy: policy,
                    at: Date()
                )
                await reloadQuarantineSchedules()
                recoveryMessage = policy == .manual
                    ? L10n.text("已改为手动保留；已删除项目不会自动彻底删除")
                    : L10n.text("已更新自动彻底删除时间")
                recoveryMessageIsError = false
            } catch {
                recoveryMessage = L10n.text("无法更新自动删除时间：{0}", String(describing: error.localizedDescription))
                recoveryMessageIsError = true
            }
        }
    }

    func startFullScan() {
        guard !bootstrapInProgress, !updateInProgress, deepScanningApplicationID == nil else { return }
        guard !isScanRunning, phase != .executing, !oneClickCleanupIsRunning,
              !checkingScanPermissions, !preparingScanPermissions else { return }
        checkingScanPermissions = true
        Task { [weak self] in
            guard let self else { return }
            defer { checkingScanPermissions = false }
            await loadPermissions()
            if ScanPermissionPreparationPolicy.canProceed(
                diskAccess: permissionSnapshot?.fullDiskAccess.status ?? .unverified) {
                beginFullScan()
            } else { showsScanPermissionPreparation = true }
        }
    }

    func preparePermissionsAndScan() {
        guard !preparingScanPermissions, !isScanRunning else { return }
        preparingScanPermissions = true
        Task { [weak self] in
            guard let self else { return }
            defer { preparingScanPermissions = false }
            await loadPermissions()
            if permissionSnapshot?.fullDiskAccess.status != .granted {
                UserDefaults.standard.set(true, forKey: Self.pendingPermissionScanDefaultsKey)
                openFullDiskAccessSettings()
                return
            }
            continueScanWithCurrentPermissions()
        }
    }

    func continueScanWithCurrentPermissions() {
        UserDefaults.standard.removeObject(forKey: Self.pendingPermissionScanDefaultsKey)
        showsScanPermissionPreparation = false
        guard !updateInProgress, phase != .executing, !oneClickCleanupIsRunning, !isScanRunning else { return }
        beginFullScan()
    }

    func dismissScanPermissionPreparation() {
        UserDefaults.standard.removeObject(forKey: Self.pendingPermissionScanDefaultsKey)
        showsScanPermissionPreparation = false
    }

    private func resumePendingPermissionScanIfPossible() async {
        guard UserDefaults.standard.bool(forKey: Self.pendingPermissionScanDefaultsKey),
              !bootstrapInProgress, !isScanRunning, phase != .executing else { return }
        await loadPermissions()
        guard permissionSnapshot?.fullDiskAccess.status == .granted else {
            showsScanPermissionPreparation = true
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingPermissionScanDefaultsKey)
        showsScanPermissionPreparation = false
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
        beginFullScan()
    }

    private func beginFullScan() {
        guard !updateInProgress, phase != .executing, !oneClickCleanupIsRunning, !isScanRunning else { return }
        guard deepScanningApplicationID == nil, !isLoadingApplications else { return }
        scanTask?.cancel()
        for task in moduleScanTasks.values { task.cancel() }
        moduleScanTasks.removeAll()
        moduleScanTokens.removeAll()
        moduleScanSession = nil
        readyScanModules.removeAll()
        overlapAnalysisTask?.cancel()
        overlapAnalysisToken = nil
        agentOverlapAnalysisIsRunning = false
        let scanToken = UUID()
        activeScanToken = scanToken
        activeScanGenerationID = nil
        scanCleanupReconciliation = nil
        isFullScanTimingSession = true
        fullScanStartedAt = Date()
        fullScanStoppedAt = nil
        isScanRunning = true
        oneClickCleanedCandidateIDs.removeAll()
        activeCleanupModules.removeAll()
        cleanedModules.removeAll()
        oneClickCompletedByModule.removeAll()
        cleanupFailures.removeAll()
        phase = .scanning
        statusMessage = systemReport == nil
            ? L10n.text("正在扫描可访问位置；不会修改任何文件")
            : L10n.text("正在重新扫描可访问位置；完成前保留上一次结果")
        scanProgressByModule = Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
            ($0, ScanModuleStatus(module: $0, state: .waiting))
        })
        scanTask = Task { [weak self] in await self?.runScan(token: scanToken) }
    }

    func applicationDidBecomeActive() {
        if selection == .applications { refreshRunningApplications() }
        Task { [weak self] in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: Self.pendingPermissionScanDefaultsKey) {
                await resumePendingPermissionScanIfPossible()
            } else if selection == .settings || showsScanPermissionPreparation {
                await loadPermissions()
            }
            // The existing maintenance timer handles due work. Focusing a window
            // must not start another maintenance pass or invalidate every list.
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        for module in ScanModuleID.allCases where canCancelScan(module) {
            cancelModuleScan(module)
        }
        finishModuleScanSessionIfIdle()
        if moduleScanSession == nil {
            isScanRunning = false
            activeScanToken = nil
            activeScanGenerationID = nil
            if phase == .scanning { phase = .cancelled }
        }
        finishFullScanTimingIfIdle()
    }

    func canCancelScan(_ module: ScanModuleID) -> Bool {
        guard isScanRunning else { return false }
        return moduleScanTokens[module] != nil || scanProgressByModule[module]?.state == .waiting
    }

    func canResumeScan(_ module: ScanModuleID) -> Bool {
        scanProgressByModule[module]?.state == .cancelled
            && ((moduleScanSession != nil && scanTask == nil) || (moduleScanSession == nil && scanTask != nil))
            && !updateInProgress && phase != .executing && !oneClickCleanupIsRunning
            && deepScanningApplicationID == nil && moduleScanTokens[module] == nil
    }

    func cancelModuleScan(_ module: ScanModuleID) {
        guard canCancelScan(module) else { return }
        moduleScanTokens.removeValue(forKey: module)
        moduleScanTasks.removeValue(forKey: module)?.cancel()
        if module == .agentEnvironment {
            overlapAnalysisTask?.cancel()
            overlapAnalysisTask = nil
            overlapAnalysisToken = nil
            agentOverlapAnalysisIsRunning = false
            agentOverlapNeedsScanAnalysis = false
            agentOverlapFullRecalculationRequested = false
        }
        let previous = scanProgressByModule[module]
        scanProgressByModule[module] = ScanModuleStatus(
            module: module, state: .cancelled, startedAt: previous?.startedAt,
            completedAt: Date(), message: L10n.text("用户已取消"), limitations: previous?.limitations ?? []
        )
        if let report = systemReport, report.generationID == moduleScanSession?.generationID {
            systemReport = report.updatingModuleStatuses(scanProgressByModule)
        }
        finishModuleScanSessionIfIdle()
    }

    func resumeModuleScan(_ module: ScanModuleID) {
        guard canResumeScan(module) else { return }
        guard let session = moduleScanSession else {
            scanProgressByModule[module] = ScanModuleStatus(module: module, state: .waiting)
            return
        }
        activeScanGenerationID = session.generationID
        if activeScanToken == nil { activeScanToken = UUID() }
        if isFullScanTimingSession { fullScanStoppedAt = nil }
        isScanRunning = true
        if phase != .executing { phase = .scanning }
        startModuleScan(module, session: session)
    }

    func cancelCurrentModuleScan() {
        guard let module = currentScanModule else { return }
        cancelModuleScan(module)
    }

    func resumeCurrentModuleScan() {
        guard let module = currentScanModule else { return }
        resumeModuleScan(module)
    }

    var canResumeCurrentModuleScan: Bool {
        currentScanModule.map(canResumeScan) ?? false
    }

    func toggle(_ candidate: CleanupCandidate) {
        guard candidate.risk.isSelectable else { return }
        if selection == .agentEnvironment {
            let willSelect = !selectedIDs.contains(candidate.id)
            for (objectID, ids) in agentContainmentCandidateIDs where ids.contains(candidate.id) {
                rememberAgentObjectDecision(objectID, selected: willSelect)
            }
            autoSelectedAgentCandidateIDs.remove(candidate.id)
        }
        if selection == .systemCleanup, cleanupMode != .custom, let generationID = systemReport?.generationID {
            var state = CleanupStrategySelectionState(
                strategy: cleanupMode,
                generationID: generationID,
                selectedIDs: selectedIDs,
                excludedBaseIDs: excludedBaseIDs
            )
            state.toggle(candidate, baseEligibleIDs: cleanupBaseEligibleIDs)
            selectedIDs = state.selectedIDs
            excludedBaseIDs = state.excludedBaseIDs
        } else {
            if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) } else { selectedIDs.insert(candidate.id) }
            if selection == .systemCleanup { cleanupMode = .custom }
        }
        if selection == .agentEnvironment { applyAgentAutoPreselection(from: agentOverlapMatches) }
        reconcileFocus()
    }

    func setCleanupMode(_ mode: CleanupMode) {
        let resolvedMode = CleanupMode.userFacingCases.contains(mode) ? mode : .defaultMode
        guard resolvedMode != cleanupMode else { return }
        let scopedCandidates = candidates(for: .systemCleanup)
        let state = CleanupModeSelectionState(mode: cleanupMode, selectedIDs: selectedIDs)
            .applying(resolvedMode, to: scopedCandidates, policy: recommendationPolicy)
        cleanupMode = state.mode
        selectedIDs = state.selectedIDs
        excludedBaseIDs.removeAll()
        reconcileFocus()
        switch resolvedMode {
        case .smart:
            statusMessage = L10n.text("已默认勾选明确安全、非活跃且当前可执行的内容")
        case .deep:
            statusMessage = L10n.text("已加入低风险和可重建内容，可能需要重新下载或构建")
        case .custom:
            statusMessage = L10n.text("手动选择：勾选表示加入当前计划")
        }
    }

    func openCleanupCenter(mode: CleanupMode = .defaultMode) {
        setCleanupMode(mode)
        selection = .systemCleanup
    }

    func cleanupSelectionState(for candidates: [CleanupCandidate], includesManualOnly: Bool = false) -> SelectionTriState {
        guard let generationID = systemReport?.generationID else { return .none }
        return CleanupStrategySelectionState(
            strategy: cleanupMode,
            generationID: generationID,
            selectedIDs: selectedIDs,
            excludedBaseIDs: excludedBaseIDs
        ).selectionState(for: Set(candidates.filter {
            $0.risk.isSelectable && (includesManualOnly || $0.requiresExplicitSelection != true)
        }.map(\.id)))
    }

    func toggleCleanupCategory(_ candidates: [CleanupCandidate], includesManualOnly: Bool = false) {
        guard let generationID = systemReport?.generationID else { return }
        var state = CleanupStrategySelectionState(
            strategy: cleanupMode,
            generationID: generationID,
            selectedIDs: selectedIDs,
            excludedBaseIDs: excludedBaseIDs
        )
        state.toggleCategory(candidates: candidates, baseEligibleIDs: cleanupBaseEligibleIDs, includesManualOnly: includesManualOnly)
        selectedIDs = state.selectedIDs
        excludedBaseIDs = state.excludedBaseIDs
        reconcileFocus()
    }

    func focusDiskNode(_ node: DiskUsageNode) { selectedDiskNodeURL = node.url }

    func sortedDiskNodes(_ nodes: [DiskUsageNode]) -> [DiskUsageNode] {
        let selectedURLs = largeFileSortOrder == .selection
            ? DiskUsageSelectionState(
                candidates: systemReport?.largeFileCandidates ?? [],
                selectedIDs: selectedIDs
            ).selectedFileURLs
            : []
        return largeFileSortOrder.sorted(nodes, selectedFileURLs: selectedURLs)
    }

    func diskFileCandidate(for node: DiskUsageNode) -> CleanupCandidate? {
        guard node.kind == .file else { return nil }
        return largeFileCandidatesByPath[node.url.standardizedFileURL.path].map { protectionPolicy.applying(to: $0) }
    }

    func toggleDiskFile(_ node: DiskUsageNode) {
        guard let candidate = diskFileCandidate(for: node) else { return }
        toggle(protectionPolicy.applying(to: candidate))
    }

    func isDiskFileSelected(_ node: DiskUsageNode) -> Bool {
        guard let candidate = diskFileCandidate(for: node) else { return false }
        return selectedIDs.contains(candidate.id)
    }

    func selectAgentProvider(_ provider: AgentProvider?) {
        guard provider != agentProviderFilter else { return }
        agentCleanupPresentation = nil
        agentProviderFilter = provider
    }

    func openAgentSkillRoot(_ skill: SkillCatalogEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([skill.skillRootURL])
    }

    func openAgentSkillManifest(_ skill: SkillCatalogEntry) {
        guard let manifestURL = skill.manifestURL else { return }
        NSWorkspace.shared.open(manifestURL)
    }

    func openAgentMCPConfiguration(_ configuration: MCPConfigurationRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([configuration.fileURL])
    }

    func setAgentSkillDecision(_ decision: AgentSkillDecision, skillID: String) {
        guard let binding = agentSkillCatalogPresentation.bindingsByID[skillID] else { return }
        rememberAgentObjectDecision("skill|\(skillID)", selected: decision == .plannedForDeletion)
        autoSelectedAgentCandidateIDs.subtract(binding.selectableCandidateIDs)
        switch decision {
        case .retain, .deletionUnavailable:
            selectedIDs.subtract(binding.selectableCandidateIDs)
        case .plannedForDeletion:
            guard binding.isDeletionAvailable else { return }
            selectedIDs.formUnion(binding.selectableCandidateIDs)
        }
        applyAgentAutoPreselection(from: agentOverlapMatches)
    }

    func focus(_ candidateID: UUID?, for destination: SidebarDestination) {
        var next = focusState
        next.focus(candidateID, visibleIDs: visibleCandidates(for: destination).map(\.id))
        focusState = next
    }

    func reconcileFocus(for destination: SidebarDestination? = nil) {
        let target = destination ?? selection
        guard navigationPolicy.usesCandidateReviewFocus(for: target) else { return }
        var next = focusState
        next.reconcile(visibleIDs: visibleCandidates(for: target).map(\.id))
        focusState = next
    }

    func clearCurrentSelection() {
        let selected = selectedCandidates
        guard !selected.isEmpty else { return }
        if selection == .systemCleanup {
            toggleCleanupCategory(selected)
        } else {
            if selection == .agentEnvironment {
                let clearingIDs = Set(selected.map(\.id))
                for (objectID, candidateIDs) in agentContainmentCandidateIDs where !candidateIDs.isDisjoint(with: clearingIDs) {
                    rememberAgentObjectDecision(objectID, selected: false)
                }
                autoSelectedAgentCandidateIDs.subtract(selected.map(\.id))
            }
            selectedIDs.subtract(selected.map(\.id))
            reconcileFocus()
        }
    }

    func requestExecution() {
        guard canExecuteSelection else { return }
        let selected = Set(selectedCandidates.map(\.id))
        guard !selected.isEmpty else { return }
        do {
            let plan = try planBuilder.build(candidates: candidates(for: selection), selectedIDs: selected)
            executeSelection(plan: plan)
        } catch PlanBuilderError.retainedLargeFileSelected {
            let message = L10n.text("清理计划包含必须保留的文件或目录")
            statusMessage = message
            phase = .failed(message)
        } catch {
            statusMessage = L10n.text("无法删除：{0}", String(describing: error.localizedDescription))
            phase = .failed(statusMessage ?? L10n.text("无法删除"))
        }
    }

    func runOneClickCleanup() {
        guard canRunOneClickCleanup, let defaults = defaultCleanupSelection else { return }
        let systemCandidates = defaults.systemCleanup
        let checkedModules: Set<ScanModuleID> = [.general]
        let selected = Set(systemCandidates.map(\.id))
        do {
            let plan = try planBuilder.build(candidates: systemCandidates, selectedIDs: selected)
            deletionResult = nil
            deletionResultWarning = nil
            isStoppingDeletion = false
            oneClickActiveModules = [.general]
            oneClickCleanupIsRunning = true
            statusMessage = L10n.text("正在执行一键系统清理")
            let progress = executionProgressHandler(total: plan.selectedItems.count)
            oneClickExecutionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let receipt = try await cleanupExecutionCoordinator.execute(
                        plan: plan,
                        retentionPolicy: defaultQuarantineRetentionPolicy,
                        progress: progress
                    )
                    finishExecutionProgress(receipt)
                    let outcome = recordCleanupOutcome(
                        attemptedCandidates: systemCandidates,
                        receipt: receipt
                    )
                    recordDefaultCleanupProgress(
                        outcome: outcome,
                        attemptedCandidates: systemCandidates,
                        checkedModules: checkedModules
                    )
                    sessionCleanupSummary.record(receipt)
                    await reloadHistory()
                    await reloadQuarantineSchedules()
                    statusMessage = L10n.text("系统清理完成")
                    deletionResult = receipt
                } catch {
                    finishCleanupSilently(error)
                }
                oneClickActiveModules.removeAll()
                oneClickCleanupIsRunning = false
                oneClickExecutionTask = nil
            }
        } catch {
            oneClickActiveModules.removeAll()
            oneClickCleanupIsRunning = false
            statusMessage = L10n.text("无法开始一键系统清理：{0}", String(describing: error.localizedDescription))
        }
    }

    private func oneClickModule(for candidate: CleanupCandidate) -> ScanModuleID? {
        switch candidate.source {
        case .general, .historicalApplicationResidue: .general
        case .agentWorkspace: .agentEnvironment
        case .diskAnalysis: .largeFiles
        case .application: .applications
        case .projectArtifacts: nil
        }
    }

    func cleanupFailures(for module: ScanModuleID) -> [DefaultCleanupFailure] {
        cleanupFailures.filter { oneClickModule(for: $0.candidate) == module }
    }

    func canRetryCleanupFailures(_ failures: [DefaultCleanupFailure]) -> Bool {
        let candidates = failures.filter(\.isRetryable).map(\.candidate)
        return !candidates.isEmpty && candidates.allSatisfy {
            guard let module = oneClickModule(for: $0) else { return false }
            return canExecuteCleanup(in: module, hasSelection: true)
        }
    }

    func retryCleanupFailures(_ failures: [DefaultCleanupFailure]) {
        guard canRetryCleanupFailures(failures) else { return }
        let candidates = failures.filter(\.isRetryable).map(\.candidate)
        guard !candidates.isEmpty else { return }
        do {
            let selectedIDs = Set(candidates.map(\.id))
            let plan = try planBuilder.build(candidates: candidates, selectedIDs: selectedIDs)
            executeSelection(plan: plan, recordsDefaultCleanupProgress: true)
        } catch {
            statusMessage = L10n.text("无法创建安全重试计划：{0}", String(describing: error.localizedDescription))
            phase = .failed(statusMessage ?? L10n.text("无法创建安全重试计划"))
        }
    }

    private func executeSelection(
        plan: CleanupPlan,
        recordsDefaultCleanupProgress: Bool = false
    ) {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        let progress = prepareDeletion(plan: plan, modules: Set(plan.selectedItems.compactMap { oneClickModule(for: $0.candidate) }))
        statusMessage = L10n.text("正在检查并删除所选项目")
        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await cleanupExecutionCoordinator.execute(
                    plan: plan,
                    retentionPolicy: defaultQuarantineRetentionPolicy,
                    progress: progress
                )
                finishExecutionProgress(receipt)
                let attemptedCandidates = plan.selectedItems.map(\.candidate)
                let outcome = recordCompletedCleanup(
                    receipt,
                    attemptedCandidates: attemptedCandidates
                )
                if recordsDefaultCleanupProgress {
                    recordDefaultCleanupProgress(
                        outcome: outcome,
                        attemptedCandidates: attemptedCandidates
                    )
                }
                let attemptedIDs = Set(attemptedCandidates.map(\.id))
                selectedIDs = CleanupModeSelectionState(
                    mode: cleanupMode,
                    selectedIDs: selectedIDs
                ).removing(attemptedCandidates).selectedIDs
                excludedBaseIDs.subtract(attemptedIDs)
                await reloadHistory()
                await reloadQuarantineSchedules()
                phase = .completed
                deletionResult = receipt
            } catch {
                finishCleanupSilently(error)
            }
            activeCleanupModules.removeAll()
            executionTask = nil
        }
    }

    private func prepareDeletion(plan: CleanupPlan, modules: Set<ScanModuleID>) -> CleanupExecutor.ProgressHandler {
        deletionResult = nil
        deletionResultWarning = nil
        isStoppingDeletion = false
        activeCleanupModules = modules
        let progress = executionProgressHandler(total: plan.selectedItems.count)
        phase = .executing
        if agentOverlapAnalysisIsRunning {
            agentAnalysisDeferredForCleanup = true
            overlapAnalysisTask?.cancel()
            overlapAnalysisToken = nil
            overlapAnalysisTask = nil
            agentOverlapAnalysisIsRunning = false
        }
        return progress
    }

    func cancelExecution() {
        guard isDeletionInProgress, !isStoppingDeletion else { return }
        isStoppingDeletion = true
        executionTask?.cancel()
        oneClickExecutionTask?.cancel()
        statusMessage = L10n.text("正在完成当前原子移动，尚未开始的项目将停止")
    }

    private func executionProgressHandler(total: Int) -> CleanupExecutor.ProgressHandler {
        let token = UUID()
        executionProgressToken = token
        executionResultsTask?.cancel()
        executionResultsTask = nil
        pendingExecutionResults.removeAll()
        executionProgress = .init(completed: 0, total: total, currentURL: nil)
        return { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.executionProgressToken == token else { return }
                self.executionProgress = progress
                guard let result = progress.result else { return }
                self.recordScanCleanupEffects([result])
                self.pendingExecutionResults.append(result)
                // Keep progress cheap while the operation sheet covers the lists.
                // Reconcile the final receipt once, instead of rebuilding every module every 150 ms.
            }
        }
    }

    private func recordScanCleanupEffects(_ results: [OperationResult]) {
        guard let current = systemReport else { return }
        if scanCleanupReconciliation?.generationID != current.generationID {
            scanCleanupReconciliation = ScanCleanupReconciliation(generationID: current.generationID)
        }
        scanCleanupReconciliation?.record(results)
    }

    private func applyingScanCleanup(to report: SystemScanReport) -> SystemScanReport {
        scanCleanupReconciliation?.applying(to: report) ?? report
    }

    private func applyPendingExecutionResults() {
        executionResultsTask = nil
        let results = pendingExecutionResults
        pendingExecutionResults.removeAll()
        guard !results.isEmpty, let current = systemReport else { return }
        install(current.reconcilingCleanup(results))
            selectedIDs.formIntersection(Set(allKnownCleanupCandidates.map(\.id)))
        if let selectedDiskNodeURL, diskUsageTree?.node(at: selectedDiskNodeURL) == nil { self.selectedDiskNodeURL = nil }
    }

    private func finishExecutionProgress(_ receipt: OperationReceipt? = nil) {
        executionResultsTask?.cancel()
        executionProgressToken = nil
        if receipt == nil { applyPendingExecutionResults() }
        else { pendingExecutionResults.removeAll() }
        if let receipt {
            recordScanCleanupEffects(receipt.results)
            executionProgress = .init(completed: receipt.results.count, total: max(receipt.results.count, executionProgress.total),
                currentURL: nil, phase: .savingResults)
        }
    }

    private func finishCleanupSilently(_ error: Error) {
        finishExecutionProgress()
        FileHandle.standardError.write(Data("Cleanup retained its execution journal: \(error)\n".utf8))
        statusMessage = nil
        deletionResult = nil
        deletionResultWarning = nil
        phase = .completed
    }

    func requestRestore(_ receipt: OperationReceipt) {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard recoveryActionReceiptID == nil,
              receipt.results.contains(where: { $0.disposition == .quarantined })
        else { return }
        restoreConfirmationReceipt = receipt
    }

    func dismissRestoreConfirmation() { restoreConfirmationReceipt = nil }

    func confirmRestore() {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard let receipt = restoreConfirmationReceipt, recoveryActionReceiptID == nil else { return }
        restoreConfirmationReceipt = nil
        restore(receipt)
    }

    private func restore(_ receipt: OperationReceipt) {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard recoveryActionReceiptID == nil else { return }
        recoveryActionReceiptID = receipt.id
        recoveryActionKind = .restore
        recoveryMessage = L10n.text("正在恢复已删除项目…")
        recoveryMessageIsError = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let restored = try await cleanupExecutionCoordinator.restore(receipt: receipt)
                let successful = restored.results.filter { [.restored, .restoreConflict].contains($0.status) }
                let failures = restored.results.count - successful.count
                let conflicts = restored.results.filter { $0.status == .restoreConflict }.count
                await reloadHistory()
                await reloadQuarantineSchedules()
                if successful.isEmpty {
                    recoveryMessage = failures == 0 ? L10n.text("没有可恢复的已删除项目") : L10n.text("恢复失败：{0} 项仍保留在恢复记录中，可稍后重试", String(describing: failures))
                } else if conflicts == 0, failures == 0 {
                    recoveryMessage = L10n.text("已恢复 {0} 项到原路径", String(describing: successful.count))
                } else {
                    recoveryMessage = L10n.text("已恢复 {0} 项；{1} 项因路径冲突恢复到相邻位置，{2} 项失败", String(describing: successful.count), String(describing: conflicts), String(describing: failures))
                }
                recoveryMessageIsError = successful.isEmpty && failures > 0
                if let warnings = restored.integrationWarnings, !warnings.isEmpty {
                    recoveryMessage = (recoveryMessage ?? "") + "\n" + warnings.joined(separator: "\n")
                    recoveryMessageIsError = true
                }
            } catch {
                recoveryMessage = L10n.text("文件已处理，但恢复记录更新失败：{0}", String(describing: error.localizedDescription))
                recoveryMessageIsError = true
            }
            recoveryActionReceiptID = nil
            recoveryActionKind = nil
        }
    }

    func requestPermanentDeletion(_ receipt: OperationReceipt) {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard recoveryActionReceiptID == nil,
              receipt.results.contains(where: { $0.disposition == .quarantined })
        else { return }
        purgeConfirmationReceipt = receipt
    }

    func dismissPermanentDeletion() { purgeConfirmationReceipt = nil }

    func confirmPermanentDeletion() {
        guard !updateInProgress, deepScanningApplicationID == nil else { return }
        guard let receipt = purgeConfirmationReceipt, recoveryActionReceiptID == nil else { return }
        purgeConfirmationReceipt = nil
        recoveryActionReceiptID = receipt.id
        recoveryActionKind = .purge
        recoveryMessage = L10n.text("正在彻底删除…")
        recoveryMessageIsError = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let purged = try await cleanupExecutionCoordinator.purge(receipt: receipt)
                let deleted = purged.results.filter {
                    $0.disposition == .permanentlyDeleted && $0.status == .succeeded
                }
                let failures = purged.results.count - deleted.count
                await reloadHistory()
                await reloadQuarantineSchedules()
                let bytes = deleted.reduce(0) { $0 + $1.bytes }
                if deleted.isEmpty {
                    recoveryMessage = failures == 0 ? L10n.text("没有可彻底删除的已删除项目") : L10n.text("彻底删除失败：{0} 项仍保留在恢复记录中", String(describing: failures))
                } else {
                    recoveryMessage = L10n.text("已彻底删除 {0} 项，释放约 {1}", String(describing: deleted.count), String(describing: ByteCountFormatter.cleanerString(bytes: bytes)))
                    if failures > 0 { recoveryMessage? += L10n.text("；{0} 项失败并继续保留", String(describing: failures)) }
                }
                recoveryMessageIsError = deleted.isEmpty && failures > 0
            } catch {
                recoveryMessage = L10n.text("文件已处理，但恢复记录更新失败：{0}", String(describing: error.localizedDescription))
                recoveryMessageIsError = true
            }
            recoveryActionReceiptID = nil
            recoveryActionKind = nil
        }
    }

    var canStartApplicationDeepScan: Bool {
        quittingApplicationIDs.isEmpty && !updateInProgress && deepScanningApplicationID == nil && !isLoadingApplications
            && !maintenanceInProgress && recoveryActionReceiptID == nil && !bootstrapInProgress
            && !isScanRunning && phase != .executing && !oneClickCleanupIsRunning
    }

    private func installRuntimeObservations(_ observations: [URL: ApplicationRuntimeObservation]) {
        guard let current = systemReport else { return }
        install(current.replacing(module: .applications,
            payload: .applications(current.applicationUninstallInventory.observing(observations)), completedAt: Date()))
    }

    func cancelApplicationDeepScan() { deepScanTask?.cancel() }

    func startApplicationDeepScan(_ application: InstalledApplication, allowLaunch: Bool) {
        guard canStartApplicationDeepScan, !application.isSystem else { return }
        deepScanningApplicationID = application.id
        deepScanMessages[application.id] = L10n.text("正在准备观察；基础扫描结果已保留。")
        deepScanTask = Task { [weak self] in
            guard let self else { return }
            var launched: NSRunningApplication?
            do {
                let provider = BundleApplicationMetadataProvider()
                guard provider.metadata(for: application.id)?.bundleIdentifier == application.bundleIdentifier else {
                    throw ApplicationExecutionRejection.ownershipChanged
                }
                let before = NSWorkspace.shared.runningApplications
                let matching = before.filter { $0.bundleURL?.standardizedFileURL.path == application.id.standardizedFileURL.path }
                if matching.isEmpty {
                    // Do not launch another copy of an already-running identity.
                    guard allowLaunch, !before.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
                        throw ApplicationExecutionRejection.ownershipChanged
                    }
                    try Task.checkCancellation()
                    let start = Date()
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    configuration.hides = true
                    let opened = try await NSWorkspace.shared.openApplication(at: application.id, configuration: configuration)
                    // Only quit an instance demonstrably created during this operation.
                    if ApplicationObservationLifecycle.shouldRequestQuit(processID: opened.processIdentifier,
                        preexistingProcessIDs: Set(before.map(\.processIdentifier)), launchDate: opened.launchDate,
                        observationStartedAt: start) {
                        launched = opened
                    } else {
                        deepScanMessages[application.id] = L10n.text("应用实例可能已由其他操作启动；扫描结束后不会自动退出它。")
                    }
                }
                try Task.checkCancellation()
                deepScanMessages[application.id] = L10n.text("正在采样打开文件；结果会逐步补充，未观察到的访问仍可能存在。")
                let observed = await ApplicationRuntimeSampler(samples: 5).observe(applications: [application], home: home) { [weak self] partial in
                    await self?.installRuntimeObservations(partial)
                }
                installRuntimeObservations(observed)
                // The observation view owns the result summary. This channel
                // only carries lifecycle progress or errors.
                deepScanMessages[application.id] = nil
            } catch {
                deepScanMessages[application.id] = Task.isCancelled
                    ? L10n.text("观察已取消；基础扫描结果已保留。")
                    : L10n.text("无法开始观察：{0}", error.localizedDescription)
            }
            if let launched, !launched.isTerminated {
                _ = launched.terminate()
                // Graceful termination only. Never force-kill an app that may
                // be saving data or waiting for the user to answer a dialog.
                for _ in 0..<12 where !launched.isTerminated {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                if !launched.isTerminated {
                    deepScanMessages[application.id] = L10n.text("观察已结束，应用尚未退出。请手动退出，列表会自动更新。")
                }
            }
            // Rebuild running state and ownership after launch/quit, even on cancel.
            // A fresh task prevents cancellation from discarding this refresh.
            await Task { await self.reloadApplicationModule(observeRunning: false) }.value
            deepScanningApplicationID = nil
            deepScanTask = nil
        }
    }

    func canQuitApplication(_ application: InstalledApplication) -> Bool {
        application.isRunning && !application.isSystem
            && application.bundleURL.resolvingSymlinksInPath().standardizedFileURL
                != Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
            && !quittingApplicationIDs.contains(application.id)
            && !isDeletionInProgress && !updateInProgress && deepScanningApplicationID == nil
    }

    var selectedApplicationsToQuit: [InstalledApplication] {
        applications.filter { quitSelectedApplicationIDs.contains($0.id) && canQuitApplication($0) }
    }

    func toggleApplicationQuitSelection(_ application: InstalledApplication) {
        guard quittingApplicationIDs.isEmpty else { return }
        if quitSelectedApplicationIDs.remove(application.id) != nil { return }
        guard canQuitApplication(application) else { return }
        quitSelectedApplicationIDs.insert(application.id)
    }

    func quitSelectedApplications() {
        guard quittingApplicationIDs.isEmpty else { return }
        // Capture explicit checkbox choices before tasks or live status updates run.
        let targets = selectedApplicationsToQuit
        for application in targets { quitApplication(application) }
    }

    func quitApplication(_ application: InstalledApplication) {
        guard canQuitApplication(application) else { return }
        quittingApplicationIDs.insert(application.id)
        applicationQuitMessages[application.id] = nil
        Task { [weak self] in
            let result = await ApplicationQuitService.quit(application)
            guard let self else { return }
            quittingApplicationIDs.remove(application.id)
            switch result {
            case .terminated, .notRunning:
                quitSelectedApplicationIDs.remove(application.id)
                applicationQuitMessages[application.id] = nil
            case .refused, .stillRunning:
                applicationQuitMessages[application.id] = L10n.text("应用尚未退出，请切换到该应用处理保存提示或手动退出。")
            case .protectedApplication:
                applicationQuitMessages[application.id] = L10n.text("不能在此退出系统应用或 SuperCleaner 自身。")
            }
            refreshRunningApplications()
        }
    }

    func refreshApplications() {
        guard !updateInProgress, deepScanningApplicationID == nil, !isLoadingApplications, !isScanRunning, phase != .executing else { return }
        guard systemReport != nil else { selection = .cleanupCenter; return }
        Task { [weak self] in await self?.reloadApplicationModule() }
    }

    private func updateRunningApplicationIDs(_ identifiers: Set<String>) {
        guard runningApplicationIDs != identifiers else { return }
        runningApplicationIDs = identifiers
        quitSelectedApplicationIDs.formIntersection(Set(applications.filter(\.isRunning).map(\.id)))
        cachedApplicationUninstallPlans = nil
        var selection = uninstallSelectionState
        selection.reconcile(plans: applicationUninstallPlans)
        uninstallSelectedIDs = selection.selectedItemIDs
        reconcileApplicationSelection()
    }

    func refreshRunningApplications() {
        guard hasScanResult(for: .applications), let report = systemReport else { return }
        updateRunningApplicationIDs(currentRunningApplicationIDs())
        guard !isPreparingStoppedAppPlans, !isLoadingApplications, deepScanningApplicationID == nil,
              moduleScanTasks[.applications] == nil, !updateInProgress, !isDeletionInProgress else { return }
        let previous = report.applicationUninstallInventory
        let generationID = report.generationID
        let needsPlan = applicationIDsAwaitingQuitAnalysis
        guard !needsPlan.isEmpty else { return }

        isPreparingStoppedAppPlans = true
        let liveApplications = applications
        let context = ScanContext(homeDirectory: home, fileSystem: fileSystem, protectionPolicy: protectionPolicy)
        Task { [weak self] in
            let refreshed = await ApplicationUninstallAnalyzer().analyzeStoppedApplications(needsPlan, in: liveApplications, context: context, cachedIndex: previous.associationIndex)
            guard let self else { return }
            defer { isPreparingStoppedAppPlans = false }
            guard !refreshed.isEmpty, !isDeletionInProgress, !updateInProgress, !isLoadingApplications,
                  deepScanningApplicationID == nil, moduleScanTasks[.applications] == nil,
                  hasScanResult(for: .applications), let current = systemReport,
                  current.generationID == generationID, current.applicationUninstallInventory == previous else { return }

            let running = currentRunningApplicationIDs()
            updateRunningApplicationIDs(running)
            let byID = Dictionary(uniqueKeysWithValues: refreshed.filter {
                !running.contains($0.application.bundleIdentifier)
            }.map { ($0.id, $0) })
            guard !byID.isEmpty else { return }
            let scanned = previous.applicationInventory
            let inventory = ApplicationInventory(applications: scanned.applications.map { byID[$0.id]?.application ?? $0 },
                coverage: scanned.coverage, scannedAt: scanned.scannedAt)
            let updated = ApplicationUninstallInventory(applicationInventory: inventory,
                analyses: previous.analyses.map { byID[$0.id] ?? $0 },
                associationCoverage: previous.associationCoverage, ownershipGraph: previous.ownershipGraph, associationIndex: previous.associationIndex)
                .observing(Dictionary(uniqueKeysWithValues: previous.analyses.compactMap { analysis in
                    analysis.runtimeObservation.map { (analysis.id, $0) }
                }))
            install(current.replacing(module: .applications, payload: .applications(updated), completedAt: Date()))
        }
    }

    private func currentRunningApplicationIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
    }

    private func reconcileApplicationSelection() {
        let visible = visibleApplications
        if let selectedApplicationID, visible.contains(where: { $0.id == selectedApplicationID }) { return }
        selectedApplicationID = visible.first?.id
    }

    func toggleUninstall(_ item: UninstallItem) {
        guard !isDeletionInProgress else { return }
        var selection = uninstallSelectionState
        selection.toggle(item: item)
        uninstallSelectedIDs = selection.selectedItemIDs
    }

    func toggleUninstall(_ plan: UninstallPlan) {
        guard !isDeletionInProgress else { return }
        var selection = uninstallSelectionState
        selection.toggle(plan: plan)
        uninstallSelectedIDs = selection.selectedItemIDs
    }

    func clearUninstallSelection() {
        guard !isDeletionInProgress else { return }
        if quittingApplicationIDs.isEmpty { quitSelectedApplicationIDs.removeAll() }
        uninstallSelectedIDs.removeAll()
    }

    func setPackageReceiptSelected(_ selected: Bool, packageID: String) {
        guard !isDeletionInProgress else { return }
        packageReceiptSelection.setSelected(selected, packageID: packageID)
    }

    func executeUninstallBatch() {
        updateRunningApplicationIDs(currentRunningApplicationIDs())
        guard canExecuteUninstallBatch else { return }
        let selection = uninstallSelectionState
        let selectedItems = selection.selectedItems(in: applicationUninstallPlans)
        let summary = selection.summary(plans: applicationUninstallPlans)
        guard !selectedItems.isEmpty else {
            statusMessage = L10n.text("请先勾选要卸载的应用或具体项目")
            return
        }
        do {
            let plan = try planBuilder.build(
                candidates: selectedItems.map { packageReceiptSelection.applying(to: $0.candidate) },
                selectedIDs: selection.selectedItemIDs
            )
            let progress = prepareDeletion(plan: plan, modules: [.applications])
            executionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let receipt = try await cleanupExecutionCoordinator.execute(
                        plan: plan,
                        retentionPolicy: defaultQuarantineRetentionPolicy,
                        progress: progress
                    )
                    finishExecutionProgress(receipt)
                    recordAppManagementObservation(from: receipt, selectedItems: selectedItems)
                    recordCompletedCleanup(receipt, attemptedCandidates: selectedItems.map(\.candidate))
                    await reloadHistory()
                    await reloadQuarantineSchedules()
                    phase = .completed
                    if receipt.overallStatus == .completed {
                        statusMessage = L10n.text("已删除 {0} 个应用的 {1} 项，可在恢复记录中撤销", String(describing: summary.applicationCount), String(describing: summary.itemCount))
                    }
                    deletionResult = receipt
                } catch {
                    finishCleanupSilently(error)
                }
                activeCleanupModules.removeAll()
                executionTask = nil
            }
        } catch { statusMessage = L10n.text("批量卸载计划无效：{0}", String(describing: error.localizedDescription)) }
    }

    @discardableResult
    private func recordCleanupOutcome(
        attemptedCandidates: [CleanupCandidate],
        receipt: OperationReceipt
    ) -> DefaultCleanupAttemptOutcome {
        let outcome = DefaultCleanupAttemptOutcome(
            attemptedCandidates: attemptedCandidates,
            receipt: receipt
        )
        for candidate in attemptedCandidates where outcome.successfulCandidateIDs.contains(candidate.id) {
            if let module = oneClickModule(for: candidate) {
                cleanedModules.insert(module)
            }
        }
        let attemptedIDs = Set(attemptedCandidates.map(\.id))
        cleanupFailures.removeAll { attemptedIDs.contains($0.candidate.id) }
        cleanupFailures.append(contentsOf: outcome.failures)
        var tracking = DefaultCleanupTrackingState(
            selectedCandidateIDs: selectedIDs,
            uninstallSelectedItemIDs: uninstallSelectedIDs,
            cleanedCandidateIDs: oneClickCleanedCandidateIDs,
            failures: cleanupFailures
        )
        tracking.reconcileSuccessfulAliases(
            outcome: outcome,
            knownCandidates: allKnownCleanupCandidates
        )
        selectedIDs = tracking.selectedCandidateIDs
        uninstallSelectedIDs = tracking.uninstallSelectedItemIDs
        oneClickCleanedCandidateIDs = tracking.cleanedCandidateIDs
        cleanupFailures = tracking.failures
        recordScanCleanupEffects(receipt.results)
        if let current = systemReport {
            install(current.reconcilingCleanup(receipt))
            selectedIDs.formIntersection(Set(allKnownCleanupCandidates.map(\.id)))
            if let selectedDiskNodeURL, diskUsageTree?.node(at: selectedDiskNodeURL) == nil {
                self.selectedDiskNodeURL = nil
            }
        }
        return outcome
    }

    @discardableResult
    private func recordCompletedCleanup(
        _ receipt: OperationReceipt,
        attemptedCandidates: [CleanupCandidate]
    ) -> DefaultCleanupAttemptOutcome {
        sessionCleanupSummary.record(receipt)
        return recordCleanupOutcome(attemptedCandidates: attemptedCandidates, receipt: receipt)
    }

    private func recordDefaultCleanupProgress(
        outcome: DefaultCleanupAttemptOutcome,
        attemptedCandidates: [CleanupCandidate],
        checkedModules: Set<ScanModuleID> = []
    ) {
        var progress = DefaultCleanupProgress(
            cleanedCandidateIDs: oneClickCleanedCandidateIDs,
            completedByModule: oneClickCompletedByModule
        )
        progress.markChecked(checkedModules)
        progress.record(outcome: outcome, attemptedCandidates: attemptedCandidates)
        oneClickCleanedCandidateIDs = progress.cleanedCandidateIDs
        oneClickCompletedByModule = progress.completedByModule
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(PermissionStatusService.fullDiskAccessSettingsURL)
    }

    func openAppManagementSettings() {
        NSWorkspace.shared.open(PermissionStatusService.appManagementSettingsURL)
    }

    private func runScan(token: UUID) async {
        guard !Task.isCancelled, activeScanToken == token else { return }
        await loadPermissions()
        // Check on every scan; a previous attempt is not proof of current access.
        if permissionSnapshot?.fullDiskAccess.status != .granted {
            await ScanPermissionPreflight(fileSystem: fileSystem).requestScanAccess(
                homeDirectory: home, includeStandardFolders: true)
        }
        guard !Task.isCancelled, activeScanToken == token else { return }
        statusMessage = L10n.text("正在扫描可访问位置；不会修改任何文件")
        let runningBundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let activePaths = runningBundleIDs.flatMap { bundleID in
            [
                home.appendingPathComponent("Library/Caches/\(bundleID)", isDirectory: true),
            ]
        }
        let configuration: (context: ScanContext, pack: RulePack)
        do {
            configuration = try await runtime.configuration(activePaths: Set(activePaths), runningBundleIdentifiers: Set(runningBundleIDs))
            protectionPolicy = configuration.context.protectionPolicy
            rulesetVersion = configuration.pack.executionVersion
        } catch {
            phase = .failed(L10n.text("清理规则无法验证"))
            statusMessage = L10n.text("扫描已停止：{0}", String(describing: error.localizedDescription))
            activeScanToken = nil
            isScanRunning = false
            scanTask = nil
            finishFullScanTimingIfIdle()
            return
        }
        guard !Task.isCancelled, activeScanToken == token else { return }
        let generationID = UUID()
        activeScanGenerationID = generationID
        scanCleanupReconciliation = ScanCleanupReconciliation(generationID: generationID)
        let session = ModuleScanSession(
            coordinator: SystemScanCoordinator(
                diskUsageScanner: DiskUsageScanner(minimumFileBytes: largeFileThreshold.bytes, maximumEntries: 50_000),
                rulePack: configuration.pack
            ),
            context: configuration.context, runningBundleIdentifiers: Set(runningBundleIDs),
            generationID: generationID, startedAt: Date()
        )
        moduleScanSession = session
        for module in ScanModuleID.allCases where scanProgressByModule[module]?.state != .cancelled {
            startModuleScan(module, session: session)
        }
        scanTask = nil
        finishModuleScanSessionIfIdle()
    }

    private func startModuleScan(_ module: ScanModuleID, session: ModuleScanSession) {
        let token = UUID()
        let preselectInstallers = preselectLargeFileInstallers
        let access = ScanAccessTrackingFileSystem(base: session.context.fileSystem)
        let original = session.context
        let context = ScanContext(homeDirectory: original.homeDirectory, fileSystem: access,
            pathPolicy: original.pathPolicy, now: original.now, activePaths: original.activePaths,
            protectionPolicy: original.protectionPolicy, runningBundleIdentifiers: original.runningBundleIdentifiers,
            activeProcessNames: original.activeProcessNames, activityProbeAvailable: original.activityProbeAvailable,
            projectActivityAvailable: original.projectActivityAvailable, enforcesEntryBudgets: false)
        scanDeniedPaths[module] = []
        scanPresentedStatuses.removeValue(forKey: module)
        moduleScanTokens[module] = token
        scanProgressByModule[module] = ScanModuleStatus(module: module, state: .scanning, startedAt: Date())
        moduleScanTasks[module] = Task { [weak self] in
            let report = await session.coordinator.scan(
                context: context, generationID: session.generationID, modules: [module],
                runningBundleIdentifiers: session.runningBundleIdentifiers,
                preselectLargeFileInstallers: preselectInstallers,
                moduleResult: { [weak self] result in
                    let deniedPaths = await access.deniedPaths
                    await self?.receiveModuleScanResult(result, token: token, session: session, deniedPaths: deniedPaths)
                },
                progress: { [weak self] event in
                    await self?.receiveModuleScanProgress(event, token: token)
                }
            )
            guard let self, !Task.isCancelled, moduleScanTokens[module] == token else { return }
            if module == .agentEnvironment, readyScanModules.contains(module) {
                await analyzeAgentOverlapsDuringScan()
            }
            guard !Task.isCancelled, moduleScanTokens[module] == token else { return }
            moduleScanTokens.removeValue(forKey: module)
            moduleScanTasks.removeValue(forKey: module)
            if let status = report?.modules[module] {
                // The progressive payload has already classified expected access skips.
                scanProgressByModule[module] = [.completed, .limited].contains(status.state)
                    ? scanPresentedStatuses[module] ?? status : status
            }
            else { scanProgressByModule[module] = ScanModuleStatus(module: module, state: .failed, completedAt: Date()) }
            if let current = systemReport { systemReport = current.updatingModuleStatuses(scanProgressByModule) }
            finishModuleScanSessionIfIdle()
        }
    }

    private func receiveModuleScanProgress(_ event: SystemScanProgressEvent, token: UUID) {
        guard moduleScanTokens[event.module] == token, activeScanGenerationID == event.generationID else { return }
        let previous = scanProgressByModule[event.module]
        // A scanner may publish actionable data before optional observations finish.
        // Keep its cancel control until the module task itself finishes.
        scanProgressByModule[event.module] = ScanModuleStatus(
            module: event.module, state: .scanning, startedAt: previous?.startedAt ?? Date(),
            message: event.message, limitations: event.limitations
        )
    }

    private func receiveModuleScanResult(_ result: SystemScanModuleResult, token: UUID, session: ModuleScanSession, deniedPaths: Set<URL>) {
        guard moduleScanTokens[result.module] == token, activeScanGenerationID == result.generationID,
              let scanToken = activeScanToken, [.completed, .limited].contains(result.status.state) else { return }
        scanDeniedPaths[result.module] = deniedPaths
        let presentation = ScanAccessPresentation(deniedPaths: deniedPaths)
        let presentedResult = SystemScanModuleResult(generationID: result.generationID,
            status: presentation.status(for: result), payload: result.payload)
        scanPresentedStatuses[result.module] = presentedResult.status
        var accumulator = ProgressiveScanReportAccumulator(
            generationID: session.generationID, startedAt: session.startedAt, rulesetVersion: rulesetVersion,
            baseline: systemReport, initialStatuses: scanProgressByModule
        )
        guard accumulator.apply(presentedResult) else { return }
        readyScanModules.insert(result.module)
        installProgressive(accumulator.report, completedModule: result.module, token: scanToken)
        if case let .agentEnvironment(inventory) = result.payload, inventory.capabilitiesOnly {
            scheduleAgentOverlapAnalysis()
        }
    }

    private func finishModuleScanSessionIfIdle() {
        guard scanTask == nil, moduleScanSession != nil, moduleScanTasks.isEmpty,
              !scanProgressByModule.values.contains(where: { !$0.state.isTerminal }) else { return }
        defer { finishFullScanTimingIfIdle() }
        isScanRunning = false
        scanTask = nil
        if let current = systemReport, let token = activeScanToken {
            completeScan(current.updatingModuleStatuses(scanProgressByModule), token: token)
        } else {
            activeScanToken = nil
            activeScanGenerationID = nil
            if phase == .scanning { phase = .cancelled }
        }
    }

    private func finishFullScanTimingIfIdle() {
        guard fullScanStartedAt != nil, fullScanStoppedAt == nil,
              !isScanRunning, !agentOverlapAnalysisIsRunning,
              !preparingAgentSkillPresentation,
              agentPreselectionCalculationTask == nil else { return }
        fullScanStoppedAt = Date()
    }

    private func completeScan(_ next: SystemScanReport, token: UUID) {
        guard activeScanToken == token else { return }
        install(applyingScanCleanup(to: next))
        scanProgressByModule = next.modules
        activeScanToken = nil
        activeScanGenerationID = nil
        isScanRunning = false
        scanTask = nil
        reconcileFocus()
        applyAgentAutoPreselection(from: agentOverlapMatches)
        if agentOverlapNeedsScanAnalysis && scanProgressByModule[.agentEnvironment]?.state != .cancelled {
            agentOverlapNeedsScanAnalysis = false
            scheduleAgentOverlapAnalysis()
        }
        // Progressive publications already selected defaults for each module.
        // Preserve manual choices and any cleanup currently executing.
        if phase == .scanning {
            phase = .reviewing
            guard !oneClickCleanupIsRunning else { return }
            if next.modules.values.contains(where: { $0.state == .cancelled }) {
                statusMessage = L10n.text("部分模块已取消；已有结果保留，可分别继续扫描。")
                return
            }
            let limitedCount = next.modules.values.filter { [.limited, .failed].contains($0.state) }.count
            statusMessage = limitedCount == 0 ? L10n.text("可访问范围扫描完成，已生成清理方案") : L10n.text("扫描已结束，{0} 个模块仍有未完成项", String(describing: limitedCount))
        }
    }

    private func installProgressive(
        _ incoming: SystemScanReport,
        completedModule: ScanModuleID,
        token: UUID
    ) {
        guard isScanRunning,
              activeScanToken == token,
              activeScanGenerationID == incoming.generationID
        else { return }
        let next = applyingScanCleanup(to: incoming)
        let previousLargeFiles = systemReport?.largeFileCandidates ?? []
        let previousLargeFileIDs = Set(previousLargeFiles.map(\.id))
        let previousRecommendations = Set(previousLargeFiles.filter(\.isLargeFilePreselected).map(\.id))
        let diskSelection = DiskUsageSelectionState(
            candidates: previousLargeFiles,
            selectedIDs: selectedIDs.subtracting(previousRecommendations)
        )
        let generationChanged = systemReport?.generationID != next.generationID
        systemReport = next
        if completedModule == .largeFiles {
            indexLargeFileCandidates(next.largeFileCandidates)
        }
        if generationChanged {
            selectedIDs.removeAll()
            autoSelectedAgentCandidateIDs.removeAll()
            uninstallSelectedIDs.removeAll()
            focusState = ReviewFocusState()
            selectedDiskNodeURL = nil
        }
        let defaults = defaultCleanupPolicy.selection(for: next)
        if completedModule == .largeFiles, !generationChanged {
            selectedIDs.subtract(previousLargeFileIDs)
            selectedIDs.formUnion(diskSelection.selectedCandidateIDs(in: next.largeFileCandidates))
        }
        if completedModule == .largeFiles {
            selectedIDs.formUnion(defaults.largeFiles.map(\.id))
        }
        if completedModule == .general {
            selectedIDs.subtract(next.generalCandidates.map(\.id))
            selectedIDs.formUnion(defaults.systemCleanup.map(\.id))
        }
        if completedModule == .agentEnvironment {
            selectedIDs.subtract(next.agentAssets.map(\.id))
            selectedIDs.formUnion(defaults.agentEnvironment.map(\.id))
        }
        if completedModule == .applications {
            var uninstallSelection = uninstallSelectionState
            uninstallSelection.reconcile(plans: next.applicationUninstallInventory.plans)
            uninstallSelectedIDs = uninstallSelection.selectedItemIDs
            reconcileApplicationSelection()
        }
    }

    private func indexLargeFileCandidates(_ candidates: [CleanupCandidate]) {
        largeFileCandidatesByPath = candidates.reduce(into: [:]) {
            $0[$1.url.standardizedFileURL.path] = $1
        }
    }

    private func scanResultDestination(for module: ScanModuleID) -> AppDestination? {
        guard let report = systemReport else { return nil }
        if readyScanModules.contains(module), report.generationID == moduleScanSession?.generationID {
            return navigationPolicy.scanResultDestination(for: module, state: .completed)
        }
        let visibleStatus = isScanRunning
            ? scanProgressByModule[module]
            : report.modules[module]
        guard let state = visibleStatus?.state,
              let destination = navigationPolicy.scanResultDestination(for: module, state: state),
              navigationPolicy.scanResultDestination(
                for: module,
                state: report.modules[module]?.state ?? .waiting
              ) != nil
        else { return nil }
        if isScanRunning, report.generationID != activeScanGenerationID { return nil }
        return destination
    }

    private func bootstrapPersistentState() async {
        do {
            rulesetVersion = try await runtime.rules.currentPack().executionVersion
            protectionPolicy = try await runtime.protections.snapshot()
        } catch {
            protectionPolicy = ProtectionPolicy(homeDirectory: home, isAvailable: false)
            configurationMessage = L10n.text("配置无法读取，删除已停用：{0}", String(describing: error.localizedDescription))
        }
        do {
            let recovered = try await cleanupExecutionCoordinator.recoverPendingExecutions()
            if !recovered.isEmpty {
                recoveryMessage = L10n.text("已恢复 {0} 个上次中断的清理批次，并完成真实状态复验", String(describing: recovered.count))
                recoveryMessageIsError = false
            }
        } catch {
            recoveryMessage = L10n.text("启动恢复失败，执行日志已保留供下次重试：{0}", String(describing: error.localizedDescription))
            recoveryMessageIsError = true
        }
        await reloadHistory()
        do {
            // Legacy records without a schedule retain the previous grace period.
            _ = try await cleanupExecutionCoordinator.migrateUnscheduled(
                policy: .hours24,
                at: Date()
            )
        } catch {
            recoveryMessage = L10n.text("已删除项目自动清除计划加载失败：{0}", String(describing: error.localizedDescription))
            recoveryMessageIsError = true
        }
        await reloadQuarantineSchedules()
        await runQuarantineMaintenance()
    }

    private func reloadHistory() async {
        do {
            let loadedReceipts = try await cleanupExecutionCoordinator.receipts()
            receipts = loadedReceipts.sorted { $0.completedAt > $1.completedAt }
        } catch {
            recoveryMessage = L10n.text("恢复记录读取失败；当前界面继续保留上一次成功加载的记录：{0}", String(describing: error.localizedDescription))
            recoveryMessageIsError = true
        }
    }

    private func reloadQuarantineSchedules() async {
        let schedules = (try? await cleanupExecutionCoordinator.schedules()) ?? []
        quarantineSchedules = Dictionary(uniqueKeysWithValues: schedules.map { ($0.receiptID, $0) })
    }

    private func runQuarantineMaintenance() async {
        guard !updateInProgress, !maintenanceInProgress, !isDeletionInProgress, deepScanningApplicationID == nil else { return }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        do {
            let result = try await cleanupExecutionCoordinator.processDue(at: Date())
            guard result.processedScheduleCount > 0 else { return }
            await reloadHistory()
            await reloadQuarantineSchedules()
            var completedMessages: [String] = []
            if result.trashedItemCount > 0 {
                completedMessages.append(L10n.text("已将 {0} 项移入系统废纸篓，可在清空废纸篓前恢复", String(describing: result.trashedItemCount)))
            }
            if result.deletedItemCount > 0 {
                completedMessages.append(L10n.text("已按计划彻底删除 {0} 项，释放约 {1}", String(describing: result.deletedItemCount), String(describing: ByteCountFormatter.cleanerString(bytes: result.releasedBytes))))
            }
            if result.unavailableItemCount > 0 {
                completedMessages.append(L10n.text("{0} 项保留内容已不存在，已结束恢复记录", String(describing: result.unavailableItemCount)))
            }
            if !completedMessages.isEmpty {
                recoveryMessage = completedMessages.joined(separator: "；")
                recoveryMessageIsError = false
            }
            if result.failedItemCount > 0 {
                recoveryMessage = L10n.text("自动彻底删除有 {0} 项失败；内容仍可从恢复记录找回，将稍后重试", String(describing: result.failedItemCount))
                recoveryMessageIsError = true
            }
        } catch {
            recoveryMessage = L10n.text("已删除项目自动清除失败：{0}", String(describing: error.localizedDescription))
            recoveryMessageIsError = true
            await reloadQuarantineSchedules()
        }
    }
    private func reloadApplicationModule(observeRunning: Bool = true) async {
        guard !updateInProgress else { return }
        guard let current = systemReport else { return }
        isLoadingApplications = true
        defer { isLoadingApplications = false }
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let access = ScanAccessTrackingFileSystem(base: fileSystem)
        let inventory = await ApplicationScanner().installedApplications(
            context: ScanContext(homeDirectory: home, fileSystem: access, protectionPolicy: protectionPolicy, enforcesEntryBudgets: false),
            runningBundleIdentifiers: runningBundleIDs
        )
        let analyzedInventory = await ApplicationUninstallAnalyzer().analyze(
            inventory: inventory,
            context: ScanContext(homeDirectory: home, fileSystem: access, protectionPolicy: protectionPolicy, enforcesEntryBudgets: false)
        )
        scanDeniedPaths[.applications] = await access.deniedPaths
        let retained = Dictionary(uniqueKeysWithValues: current.applicationUninstallInventory.analyses.compactMap { analysis in
            analysis.runtimeObservation.map { (analysis.id, $0) }
        })
        let baseline = analyzedInventory.observing(retained)
        let updated = current.replacing(
            module: .applications,
            payload: .applications(baseline),
            completedAt: Date()
        )
        install(updated)
        var uninstallSelection = uninstallSelectionState
        uninstallSelection.reconcile(plans: updated.applicationUninstallInventory.plans)
        uninstallSelectedIDs = uninstallSelection.selectedItemIDs
        if !applications.contains(where: { $0.id == selectedApplicationID }) {
            selectedApplicationID = applications.first?.id
        }
        if observeRunning {
            let running = inventory.applications.filter { $0.isRunning && !$0.isSystem }
            _ = await ApplicationRuntimeSampler().observe(applications: running, home: home) { [weak self] observations in
                await self?.installRuntimeObservations(observations)
            }
        }
    }

    func refreshModule(_ module: ScanModuleID) {
        guard !updateInProgress, deepScanningApplicationID == nil, systemReport != nil,
              [.largeFiles, .agentEnvironment].contains(module), !isScanRunning,
              phase != .executing, !oneClickCleanupIsRunning else { return }
        isFullScanTimingSession = false
        let token = UUID()
        activeScanToken = token
        scanProgressByModule[module] = ScanModuleStatus(module: module, state: .waiting)
        scanTask = Task { [weak self] in
            guard let self, let current = systemReport else { return }
            let configurationTask = Task { try await runtime.configuration() }
            let configurationResult = await configurationTask.result
            guard !Task.isCancelled, activeScanToken == token else { return }
            guard case let .success(configuration) = configurationResult else {
                if case let .failure(error) = configurationResult {
                    statusMessage = L10n.text("模块刷新失败：{0}", error.localizedDescription)
                    phase = .failed(L10n.text("模块刷新失败"))
                }
                scanProgressByModule[module] = ScanModuleStatus(module: module, state: .failed, completedAt: Date())
                if module == .agentEnvironment { agentOverlapFullRecalculationRequested = false }
                isScanRunning = false
                scanTask = nil
                activeScanToken = nil
                activeScanGenerationID = nil
                return
            }
            guard !Task.isCancelled, activeScanToken == token else { return }
            let session = ModuleScanSession(
                coordinator: SystemScanCoordinator(
                    diskUsageScanner: DiskUsageScanner(minimumFileBytes: largeFileThreshold.bytes, maximumEntries: 50_000),
                    rulePack: configuration.pack
                ), context: configuration.context,
                runningBundleIdentifiers: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
                generationID: current.generationID, startedAt: current.startedAt
            )
            moduleScanSession = session
            activeScanGenerationID = session.generationID
            scanCleanupReconciliation = ScanCleanupReconciliation(generationID: session.generationID)
            let requestedStatus = scanProgressByModule[module]
            scanProgressByModule = current.modules
            scanProgressByModule[module] = requestedStatus
            readyScanModules = Set(current.modules.values.filter { [.completed, .limited].contains($0.state) }.map(\.module))
            if scanProgressByModule[module]?.state != .cancelled { startModuleScan(module, session: session) }
            scanTask = nil
            finishModuleScanSessionIfIdle()
        }
        isScanRunning = true
        phase = .scanning
    }

    private func rulesDidChange(_ pack: RulePack) {
        rulesetVersion = pack.executionVersion
        systemReport = nil; scanProgressByModule.removeAll()
        moduleScanSession = nil
        readyScanModules.removeAll()
        activeCleanupModules.removeAll(); cleanedModules.removeAll()
        cleanedModules.removeAll()
        selectedIDs.removeAll(); uninstallSelectedIDs.removeAll(); excludedBaseIDs.removeAll()
        cleanupFailures.removeAll(); oneClickCompletedByModule.removeAll()
        restoreConfirmationReceipt = nil; purgeConfirmationReceipt = nil
        statusMessage = L10n.text("规则已变更，旧扫描与计划失效；请重新扫描。")
        phase = .idle
    }

    func navigateToScan() { selection = .cleanupCenter }

    private func scanContext() -> ScanContext {
        let runningBundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let activePaths = runningBundleIDs.flatMap { bundleID in
            [
                home.appendingPathComponent("Library/Caches/\(bundleID)", isDirectory: true),
            ]
        }
        return ScanContext(
            homeDirectory: home,
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: home),
            activePaths: Set(activePaths),
            protectionPolicy: protectionPolicy,
            runningBundleIdentifiers: Set(runningBundleIDs)
        )
    }

    private func install(_ incoming: SystemScanReport) {
        var next = incoming
        if let status = incoming.modules[.applications] {
            let result = SystemScanModuleResult(generationID: incoming.generationID, status: status,
                payload: .applications(incoming.applicationUninstallInventory))
            var statuses = incoming.modules
            statuses[.applications] = applicationScanPresentation.status(for: result)
            next = incoming.updatingModuleStatuses(statuses)
        }
        let generationChanged = systemReport?.generationID != next.generationID
        let previousRecommendations = Set(systemReport?.largeFileCandidates.filter(\.isLargeFilePreselected).map(\.id) ?? [])
        let currentRecommendations = Set(next.largeFileCandidates.filter(\.isLargeFilePreselected).map(\.id))
        systemReport = next
        indexLargeFileCandidates(next.largeFileCandidates)
        selectedIDs.subtract(previousRecommendations.subtracting(currentRecommendations))
        if !isScanRunning { scanProgressByModule = next.modules }
        if generationChanged {
            selectedIDs.removeAll()
            autoSelectedAgentCandidateIDs.removeAll()
            uninstallSelectedIDs.removeAll()
            focusState = ReviewFocusState()
            selectedDiskNodeURL = nil
        }
        var uninstallSelection = uninstallSelectionState
        uninstallSelection.reconcile(plans: next.applicationUninstallInventory.plans)
        uninstallSelectedIDs = uninstallSelection.selectedItemIDs
        reconcileApplicationSelection()
    }

    private var uninstallSelectionState: UninstallBatchSelectionState {
        UninstallBatchSelectionState(selectedItemIDs: uninstallSelectedIDs)
    }

    private var allKnownCleanupCandidates: [CleanupCandidate] {
        guard let report = systemReport else { return [] }
        return report.generalCandidates
            + report.largeFileCandidates
            + report.agentAssets.map(\.candidate)
            + report.applicationUninstallInventory.plans.flatMap(\.items).map(\.candidate)
    }

    private var cleanupBaseEligibleIDs: Set<UUID> {
        let allowed: Set<CleanupDisposition>
        switch cleanupMode {
        case .smart: allowed = [.recommended]
        case .deep: allowed = [.recommended, .deepClean]
        case .custom: allowed = Set(CleanupDisposition.allCases)
        }
        return Set(candidates(for: .systemCleanup).filter {
            $0.risk.isSelectable && allowed.contains(recommendationPolicy.disposition(for: $0))
        }.map(\.id))
    }
    func loadPermissions() async {
        let storedObservation = UserDefaults.standard.string(
            forKey: Self.appManagementObservationDefaultsKey
        ).flatMap(PermissionCapabilityStatus.init(rawValue:)) ?? .unverified
        permissionSnapshot = await PermissionStatusService(
            fileSystem: fileSystem,
            homeDirectory: home,
            appManagementObservation: storedObservation == .actionRequired ? .actionRequired : .unverified
        ).snapshot()
    }

    private func recordAppManagementObservation(
        from receipt: OperationReceipt,
        selectedItems: [UninstallItem]
    ) {
        let applicationPaths = Set(selectedItems.compactMap { item -> String? in
            let candidate = item.candidate
            guard candidate.category == .application, candidate.source == .application else { return nil }
            return candidate.url.standardizedFileURL.path
        })
        guard !applicationPaths.isEmpty else { return }
        let applicationResults = receipt.results.filter {
            applicationPaths.contains($0.originalURL.standardizedFileURL.path)
        }
        guard !applicationResults.isEmpty else { return }
        let observation: PermissionCapabilityStatus = applicationResults.contains { $0.status == .succeeded }
            ? .granted
            : .actionRequired
        UserDefaults.standard.set(observation.rawValue, forKey: Self.appManagementObservationDefaultsKey)
        if let current = permissionSnapshot {
            permissionSnapshot = PermissionSnapshot(
                level: current.level, availableCategories: current.availableCategories,
                affectedCategories: current.affectedCategories, settingsURL: current.settingsURL,
                explanation: current.explanation, fullDiskAccess: current.fullDiskAccess,
                appManagement: .init(status: observation, settingsURL: current.appManagement.settingsURL,
                    explanation: observation == .granted
                        ? L10n.text("最近一次应用卸载已通过系统授权并成功删除")
                        : L10n.text("最近一次应用操作被系统拒绝或未完成，请检查 App 管理权限")))
        }
    }

    private func invalidateAgentVisibleLists() {
        cachedHiddenSelectedCounts.removeValue(forKey: .agentEnvironment)
        cachedVisibleAgentSkills = nil
        cachedVisibleAgentMCPs = nil
    }

    private func invalidateAgentSkillPresentationCache() {
        invalidateAgentVisibleLists()
        cachedAgentSkillPresentation = nil
        cachedAgentSkillPresentationSelectedIDs.removeAll(keepingCapacity: true)
    }

    private func invalidateAgentEnvironmentCaches() {
        agentPreselectionCalculationTask?.cancel()
        agentPreselectionCalculationTask = nil
        agentPreselectionToken = nil
        invalidateAgentSkillPresentationCache()
        agentSkillPresentationTask?.cancel()
        agentSkillPresentationTask = nil
        agentSkillPresentationToken = nil
        preparingAgentSkillPresentation = false
        cachedAgentCandidateByPath = nil
    }

    private func prepareAgentSkillPresentation() {
        guard !agentSkills.isEmpty else { return }
        let skills = agentSkills
        let assets = agentAssets
        let selected = selectedIDs
        let token = UUID()
        agentSkillPresentationToken = token
        preparingAgentSkillPresentation = true
        let task = Task.detached(priority: .userInitiated) {
            AgentSkillCatalogPresentation(skills: skills, assets: assets, selectedIDs: selected)
        }
        agentSkillPresentationTask = Task { [weak self] in
            let presentation = await task.value
            guard let self, agentSkillPresentationToken == token else { return }
            cachedAgentSkillPresentation = presentation
            cachedAgentSkillPresentationSelectedIDs = selected
            invalidateAgentVisibleLists()
            agentSkillPresentationTask = nil
            agentSkillPresentationToken = nil
            preparingAgentSkillPresentation = false
            applyAgentAutoPreselection(from: agentOverlapMatches)
            finishFullScanTimingIfIdle()
        }
    }

    private func invalidateCandidatePresentationCaches(includingAgent: Bool = true) {
        cachedAllCandidates = nil
        if includingAgent { cachedAgentAssets = nil }
        cachedSelectedCandidates.removeAll()
        cachedHiddenSelectedCounts.removeAll()
        cachedDefaultCleanupSelection = nil
        cachedCandidatesByDestination.removeAll()
        cachedRecommendationBreakdowns.removeAll()
        cachedApplicationUninstallPlans = nil
    }

}

// Exercises the same model gates used by the action bars without executing any
// filesystem operations or starting the live scanners.
extension AppModel {
    static func checkDuplicateLargeFileSelection(home: URL) async throws {
        struct InvalidSelection: Error, CustomStringConvertible { let description: String }
        let threshold = LargeFileThreshold.mb10
        let context = ScanContext(homeDirectory: home)
        let coordinator = SystemScanCoordinator(diskUsageScanner: DiskUsageScanner(minimumFileBytes: threshold.bytes),
            largeFileIndex: DuplicateFixtureIndex())
        let domain = "SuperCleaner.LargeFilePreferencesTests.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: domain),
              let report = await coordinator.scan(context: context, modules: [.largeFiles]),
              let retained = report.largeFileCandidates.first(where: { $0.url.lastPathComponent == "a.rip" }),
              let root = report.diskUsageTree.roots.first, case let .loaded(files) = root.children else {
            throw InvalidSelection(description: "Missing recursive large-file fixture")
        }
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppModel(home: home, largeFilePreferences: preferences)
        model.largeFileThreshold = threshold
        model.selection = .largeFiles
        let token = UUID()
        model.isScanRunning = true
        model.activeScanToken = token
        model.activeScanGenerationID = report.generationID
        model.installProgressive(report, completedModule: .largeFiles, token: token)
        model.completeScan(report, token: token)
        let selectedNames = Set(model.selectedCandidates.map(\.displayName))
        guard model.preselectLargeFileInstallers, !model.showsDuplicateLargeFilesOnly, model.largeFileSortOrder == .selection,
              selectedNames == ["b.data", "packed.zip", "setup.dmg"],
              model.sortedDiskNodes(files).first?.url.lastPathComponent == "setup.dmg",
              model.canExecuteSelection else { throw InvalidSelection(description: "Wrong default scope, order, or selection: \(selectedNames.sorted())") }
        model.toggle(retained)
        guard model.selectedCandidates.contains(where: { $0.id == retained.id }) else { throw InvalidSelection(description: "Retained file is missing from all-file selection") }
        model.showsDuplicateLargeFilesOnly = true
        guard Set(model.selectedCandidates.map(\.displayName)) == ["b.data", "packed.zip"] else { throw InvalidSelection(description: "Duplicate selection includes other files") }
        let removed = OperationResult(candidateID: retained.id, originalURL: retained.url,
            disposition: .quarantined, status: .succeeded, bytes: retained.bytes)
        model.install(report.reconcilingCleanup([removed]))
        guard model.duplicateLargeFiles.map(\.displayName) == ["packed.zip"],
              model.selectedCandidates.map(\.displayName) == ["packed.zip"] else { throw InvalidSelection(description: "Invalid duplicate proof remained selected") }
        model.showsDuplicateLargeFilesOnly = false
        guard Set(model.selectedCandidates.map(\.displayName)) == ["packed.zip", "setup.dmg"] else { throw InvalidSelection(description: "Valid installer and ZIP were not preserved") }

        model.updateLargeFileInstallerPreselection(false)
        guard let reopenedPreferences = UserDefaults(suiteName: domain),
              !AppModel(home: home, largeFilePreferences: reopenedPreferences).preselectLargeFileInstallers,
              Set(model.selectedCandidates.map(\.displayName)) == ["packed.zip", "setup.dmg"] else {
            throw InvalidSelection(description: "Installer preference did not persist or changed the current selection")
        }
        let session = ModuleScanSession(coordinator: coordinator, context: context, runningBundleIdentifiers: [],
            generationID: report.generationID, startedAt: report.startedAt)
        model.moduleScanSession = session
        model.activeScanToken = UUID()
        model.activeScanGenerationID = session.generationID
        model.isScanRunning = true
        model.startModuleScan(.largeFiles, session: session)
        await model.moduleScanTasks[.largeFiles]?.value
        guard Set(model.selectedCandidates.map(\.displayName)) == ["b.data", "packed.zip"],
              let installer = model.candidates(for: .largeFiles).first(where: { $0.displayName == "setup.dmg" }) else {
            throw InvalidSelection(description: "Scan did not honor the installer preference")
        }
        model.toggle(installer)
        guard model.selectedCandidates.contains(installer) else {
            throw InvalidSelection(description: "Installer is not manually selectable with preselection disabled")
        }
        print("PASS: large-file ordering, installer preference persistence and refresh, duplicate filtering and retained-path reconciliation")
    }

    static func checkAgentPresentationPerformance() async throws {
        struct Failure: Error {}
        let model = AppModel(home: URL(fileURLWithPath: "/tmp/AgentPresentationFixture"))
        let skills = (0..<1_000).map { index in
            let root = URL(fileURLWithPath: "/tmp/AgentPresentationFixture/skills/skill-\(index)")
            return SkillCatalogEntry(id: root.path, logicalID: "skill-\(index)", provider: .codex, scope: .global, source: .userInstalled, kind: .workflow,
                skillRootURL: root, manifestURL: root.appendingPathComponent("SKILL.md"), displayName: "Skill \(index)",
                summary: nil, tags: [], triggers: [], tools: [], pluginName: nil, registryName: nil,
                pluginVersion: nil, parseStatus: .manifestParsed, sourceAssetURLs: [root])
        }
        model.systemReport = SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [:], generalCandidates: [], applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: [],
            agentAssets: [], agentSkills: skills)
        model.agentItemsSelectionFilter = .all
        let expected = model.visibleAgentSkillSections.flatMap(\.skills).map(\.id)
        guard expected.count == skills.count else { throw Failure() }
        model.oneClickCleanedCandidateIDs.insert(UUID())
        guard model.cachedAgentSkillPresentation != nil,
              model.visibleAgentSkillSections.flatMap(\.skills).map(\.id) == expected else { throw Failure() }
        let start = Date()
        var count = 0
        for _ in 0..<100 { count += model.visibleAgentSkillSections.reduce(0) { $0 + $1.skillCount } }
        let elapsed = Date().timeIntervalSince(start)
        guard count == 100_000 else { throw Failure() }
        model.agentProviderFilter = .claude
        guard model.visibleAgentSkillSections.isEmpty else { throw Failure() }
        model.agentProviderFilter = nil
        guard model.visibleAgentSkillSections.flatMap(\.skills).map(\.id) == expected else { throw Failure() }
        model.agentItemsSelectionFilter = .selected
        guard model.visibleAgentSkillSections.isEmpty else { throw Failure() }

        let assets = skills.enumerated().map { index, skill in
            let url = skill.skillRootURL.appendingPathComponent("cache/item-\(index)")
            let candidate = CleanupCandidate(url: url, displayName: "Item \(index)", category: .agentSandbox,
                bytes: 100, risk: .review, evidence: [],
                identity: FileIdentity(device: 1, inode: UInt64(index + 1), size: 100,
                    modificationTime: 1, kind: .file), source: .agentWorkspace,
                lastAccessDate: nil, isActive: false)
            return AgentAssetRecord(candidate: candidate, provider: .codex, scope: .global,
                resourceKind: .buildCache, activity: .completed, cleanupEligibility: .retained,
                cleanupUnitURL: url)
        }
        model.systemReport = SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture-2"),
            modules: [:], generalCandidates: [], applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: [],
            agentAssets: assets, agentSkills: skills)
        await model.agentSkillPresentationTask?.value
        model.overlapAnalysisTask?.cancel()
        model.overlapAnalysisTask = nil
        model.agentOverlapAnalysisIsRunning = false
        model.selection = .agentEnvironment
        model.selectedIDs = Set(assets.prefix(3).map(\.id))
        model.agentItemsSelectionFilter = .selected
        guard model.hiddenSelectedCount == 0 else { throw Failure() }
        model.agentEnvironmentSection = .mcp
        guard model.hiddenSelectedCount == 3 else { throw Failure() }
        model.agentEnvironmentSection = .skills
        model.agentProviderFilter = .claude
        guard model.hiddenSelectedCount == 3 else { throw Failure() }
        model.agentProviderFilter = nil
        model.selectedIDs.removeAll()
        var index = AgentOverlapIndex()
        index.revision = "fixture"
        let objectIDs = skills.map { "skill|\($0.id)" }
        for (position, objectID) in objectIDs.enumerated() {
            index.entries[objectID] = AgentOverlapMemoryEntry(id: objectID, cacheID: position,
                kind: .skill, title: skills[position].displayName, featureTexts: ["feature"], featureVectors: [])
        }
        var recommendations = [AgentOverlapMatch]()
        for position in objectIDs.indices {
            let targetPosition = position.isMultiple(of: 2) ? min(position + 1, objectIDs.count - 1) : position - 1
            let sourceID = objectIDs[position]
            let targetID = objectIDs[targetPosition]
            if sourceID != targetID {
                let first = index.entries[sourceID]!
                let second = index.entries[targetID]!
                let key = "\(min(first.cacheID, second.cacheID)):\(max(first.cacheID, second.cacheID))"
                index.matches[key] = AgentOverlapPair(firstID: first.cacheID < second.cacheID ? sourceID : targetID,
                    secondID: first.cacheID < second.cacheID ? targetID : sourceID,
                    firstCovered: Data([1]), secondCovered: Data([1]))
                recommendations.append(AgentOverlapMatch(sourceID: sourceID,
                    targets: [.init(targetID: targetID, title: skills[targetPosition].displayName, coverage: 1)],
                    coveredFeatureCount: 1, totalFeatureCount: 1))
            }
        }
        model.overlapIndex = index
        model.agentOverlapMatches = recommendations
        model.agentOverlapMatchBySourceID = Dictionary(uniqueKeysWithValues: recommendations.map { ($0.sourceID, $0) })
        let schedulingStart = Date()
        model.applyAgentAutoPreselection(from: recommendations)
        let schedulingElapsed = Date().timeIntervalSince(schedulingStart)
        guard schedulingElapsed < 0.05, model.agentPreselectionToken != nil else { throw Failure() }
        let proposed = await model.agentPreselectionCalculationTask?.value
        guard proposed?.isEmpty == true else { throw Failure() }
        model.agentPreselectionCalculationTask?.cancel()
        model.agentPreselectionCalculationTask = nil
        model.agentPreselectionToken = nil
        print("PASS: Agent presentation 1,000 Skills x 100 reads: \(elapsed)s; preselection scheduled off-main in \(schedulingElapsed)s; global resources kept and visible unit counts match filters")
    }

    static func checkScanPermissionPresentation() throws {
        struct PermissionSheetStillPresented: Error {}
        let model = AppModel(home: URL(fileURLWithPath: "/tmp/ScanPermissionPresentationFixture"))
        model.showsScanPermissionPreparation = true
        model.isScanRunning = true
        model.continueScanWithCurrentPermissions()
        guard !model.showsScanPermissionPreparation else {
            throw PermissionSheetStillPresented()
        }
        print("PASS: starting or continuing a running scan dismisses the permission sheet")
    }

    static func checkNavigationPresentation() throws {
        struct Failure: Error, CustomStringConvertible { let description: String }
        let model = AppModel(home: NavigationPresentationFixture.home)
        let report = NavigationPresentationFixture.report()
        model.systemReport = report
        model.scanProgressByModule = report.modules
        model.selectedIDs = Set(report.agentAssets.prefix(10_000).map(\.id))
        model.selection = .agentEnvironment
        _ = model.selectedCandidates
        _ = model.hiddenSelectedCount
        _ = model.defaultCleanupSelection
        let started = Date()
        for _ in 0..<20 {
            guard model.selectedCandidates.count == 10_000,
                  model.defaultCleanupSelection?.systemCleanup.count == 5_000 else {
                throw Failure(description: "selection or default cleanup changed")
            }
            _ = model.hiddenSelectedCount
        }
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed < 0.15 else {
            throw Failure(description: "cached navigation reads took \(elapsed)s")
        }
        model.selectedIDs.removeAll()
        guard model.selectedCandidates.isEmpty else { throw Failure(description: "stale selected candidates") }
        let removed = report.generalCandidates[0]
        model.oneClickCleanedCandidateIDs.insert(removed.id)
        guard model.defaultCleanupSelection?.systemCleanup.count == 4_999 else {
            throw Failure(description: "cleanup did not invalidate default selection")
        }
        model.scanProgressByModule[.general] = .init(module: .general, state: .scanning)
        model.isScanRunning = true
        model.activeScanGenerationID = report.generationID
        guard model.defaultCleanupSelection?.systemCleanup.isEmpty == true else {
            throw Failure(description: "in-progress module exposed actionable defaults")
        }
        model.scanProgressByModule[.agentEnvironment] = .init(module: .agentEnvironment, state: .scanning)
        guard model.agentEnvironmentProgressMessage == L10n.text("正在扫描 Agent 环境，发现 Skill 与 MCP 配置…") else {
            throw Failure(description: "Agent scanning state missing")
        }
        model.isScanRunning = false
        model.protectionPolicy = .init(entries: [.init(url: report.generalCandidates[1].url)],
            homeDirectory: NavigationPresentationFixture.home)
        guard model.defaultCleanupSelection?.systemCleanup.count == 4_998 else {
            throw Failure(description: "new protection did not invalidate default selection")
        }
        print("PASS: navigation 20 cached reads, 20,000 Agent assets / 5,000 cleanup items: \(elapsed)s; selection, cleanup and scan-state invalidation")
    }

    static func checkConcurrentScanCleanup() throws {
        struct Failure: Error, CustomStringConvertible { let description: String }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw Failure(description: message) }
        }
        let home = URL(fileURLWithPath: "/tmp/SuperCleaner-ScanCleanup-Fixture")
        let deniedRoot = home.appendingPathComponent("Library/Caches/Unavailable")
        let accessFailure = ScanFailure(scannerID: "fixture", message: "denied", path: deniedRoot, reason: .access)
        let accessReport = ScanReport(candidates: [], failures: [accessFailure], startedAt: Date(), completedAt: Date())
        let accessResult = SystemScanModuleResult(generationID: UUID(), status: .init(module: .general, state: .limited,
            limitations: [accessFailure.limitation]), payload: .general(accessReport))
        let hiddenAccess = ScanAccessPresentation(deniedPaths: [deniedRoot.appendingPathComponent("child")])
        let visibleStatus = hiddenAccess.status(for: accessResult)
        try check(visibleStatus.state == .completed && visibleStatus.limitations.isEmpty,
            "access-denied locations must not appear as skipped-location notices in the overview")
        let model = AppModel(home: home)
        let generation = UUID()
        let app = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Fixture.app"),
            bundleIdentifier: "com.contract.fixture", name: "Fixture", version: "1", isRunning: false, isSystem: false)
        let item = CleanupCandidate(url: app.bundleURL, displayName: "Fixture", category: .application,
            bytes: 100, risk: .review, evidence: [], identity: .init(device: 1, inode: 2, size: 100, modificationTime: 1, kind: .directory), source: .application, lastAccessDate: nil, isActive: false)
        let log = CleanupCandidate(url: home.appendingPathComponent("Library/Logs/fixture.log"), displayName: "fixture.log", category: .log,
            bytes: 50, risk: .safe, evidence: [], identity: .init(device: 1, inode: 3, size: 50, modificationTime: 1, kind: .file), source: .general, lastAccessDate: nil, isActive: false)
        let kept = CleanupCandidate(url: home.appendingPathComponent("Library/Logs/keep.log"), displayName: "keep.log", category: .log,
            bytes: 25, risk: .safe, evidence: [], identity: .init(device: 1, inode: 4, size: 25, modificationTime: 1, kind: .file), source: .general, lastAccessDate: nil, isActive: false, defaultSelection: true)
        let apps = ApplicationInventory(applications: [app], coverage: .init(), scannedAt: Date())
        let uninstall = ApplicationUninstallInventory(applicationInventory: apps, analyses: [
            .init(application: app, plan: .init(application: app, items: [.init(candidate: item, containsUserData: false, isShared: false)]), state: .complete)
        ])
        let statuses = Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
            ($0, ScanModuleStatus(module: $0, state: [.general, .applications].contains($0) ? .completed : .scanning))
        })
        let report = SystemScanReport(metadata: .init(generationID: generation, startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: statuses, generalCandidates: [log, kept], applicationInventory: apps, applicationUninstallInventory: uninstall,
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()), largeFileCandidates: [], agentAssets: [])
        // Checkbox quit choices are independent of focus and uninstall items.
        let quitModel = AppModel(home: home)
        let runningFirst = app.withRunningState(true)
        let runningSecond = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Second.app"),
            bundleIdentifier: "com.contract.second", name: "Second", version: "1", isRunning: true, isSystem: false)
        let quitApps = ApplicationInventory(applications: [runningFirst, runningSecond], coverage: .init(), scannedAt: Date())
        quitModel.install(report.replacing(module: .applications, payload: .applications(
            .init(applicationInventory: quitApps, analyses: [])), completedAt: Date()))
        quitModel.selectedApplicationID = runningFirst.id
        try check(quitModel.selectedApplicationsToQuit.isEmpty, "focusing an app must not select it for quitting")
        quitModel.toggleApplicationQuitSelection(runningFirst)
        quitModel.toggleApplicationQuitSelection(runningSecond)
        try check(Set(quitModel.selectedApplicationsToQuit.map(\.id)) == [runningFirst.id, runningSecond.id],
            "both checked running apps must be included in the quit batch")
        try check(quitModel.uninstallSelectedIDs.isEmpty, "quit checkboxes must not select uninstall items")
        quitModel.toggleApplicationQuitSelection(runningFirst)
        try check(quitModel.selectedApplicationsToQuit.map(\.id) == [runningSecond.id], "unchecking removes only that quit target")
        quitModel.quittingApplicationIDs.insert(runningSecond.id)
        quitModel.toggleApplicationQuitSelection(runningFirst)
        try check(!quitModel.quitSelectedApplicationIDs.contains(runningFirst.id), "quit batch selection is frozen while executing")
        quitModel.quittingApplicationIDs.removeAll()
        quitModel.updateRunningApplicationIDs([])
        try check(quitModel.quitSelectedApplicationIDs.isEmpty && quitModel.uninstallSelectedIDs.isEmpty,
            "exited apps lose quit selections without gaining uninstall selections")

        let offline = CleanupCandidate(url: home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"),
            displayName: "CacheStorage", category: .cache, bytes: 100, risk: .safe, evidence: [],
            identity: .init(device: 1, inode: 6, size: 100, modificationTime: 1, kind: .directory),
            source: .general, lastAccessDate: nil, isActive: false, defaultSelection: true,
            requiresExplicitSelection: true,
            cleanupApplication: .init(bundleIdentifier: "com.google.Chrome", name: "Google Chrome", kind: "Offline content"))
        let cleanupModel = AppModel(home: home)
        cleanupModel.selection = .systemCleanup
        let cleanupReport = report.replacing(module: .general,
            payload: .general(.init(candidates: [kept, offline], failures: [], startedAt: Date(), completedAt: Date())), completedAt: Date())
        cleanupModel.install(cleanupReport)
        for mode in [CleanupMode.smart, .deep] {
            cleanupModel.setCleanupMode(mode)
            try check(!cleanupModel.selectedIDs.contains(offline.id), "GUI automatic modes never select offline data")
        }
        cleanupModel.selectedIDs.removeAll()
        cleanupModel.toggleCleanupCategory([kept, offline])
        try check(cleanupModel.selectedIDs == [kept.id], "GUI group selection excludes manual-only items")
        cleanupModel.setCleanupMode(.custom)
        cleanupModel.toggle(offline)
        try check(cleanupModel.selectedIDs.contains(offline.id), "GUI individual selection grants offline consent")
        cleanupModel.setCleanupMode(.deep)
        try check(!cleanupModel.selectedIDs.contains(offline.id), "returning to automatic mode removes manual offline consent")
        cleanupModel.toggle(offline)
        cleanupModel.install(SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: cleanupReport.modules, generalCandidates: cleanupReport.generalCandidates,
            applicationInventory: apps, diskUsageTree: cleanupReport.diskUsageTree, largeFileCandidates: [], agentAssets: []))
        try check(!cleanupModel.selectedIDs.contains(offline.id), "GUI fresh report resets offline selection")
        let token = UUID()
        model.phase = .scanning
        model.isScanRunning = true
        model.activeScanToken = token
        model.activeScanGenerationID = generation
        model.scanProgressByModule = statuses
        model.install(report)
        model.selection = .applications
        try check(model.uninstallSelectedIDs.isEmpty && !model.canExecuteUninstallBatch,
            "a newly scanned uninstall plan must require manual selection")
        let cachedRunning = uninstall.analyses[0].withRunningState(true)
        let cachedRunningInventory = ApplicationUninstallInventory(
            applicationInventory: .init(applications: [app.withRunningState(true)], coverage: apps.coverage, scannedAt: apps.scannedAt),
            analyses: [cachedRunning])
        model.install(report.replacing(module: .applications, payload: .applications(cachedRunningInventory), completedAt: Date()))
        model.updateRunningApplicationIDs([app.bundleIdentifier])
        try check(model.applicationUninstallPlans.isEmpty, "prepared running plans must never be actionable")
        model.updateRunningApplicationIDs([])
        try check(model.visibleApplications == [app] && model.applicationIDsAwaitingQuitAnalysis.isEmpty
            && model.applicationUninstallPlans.first?.items.map(\.id) == [item.id]
            && model.uninstallAnalysis(for: app)?.state == .complete,
            "quit must expose the same prepared plan synchronously without scheduling filesystem work")
        let initiallyRunning = app.withRunningState(true)
        let runningInventory = ApplicationUninstallInventory(
            applicationInventory: .init(applications: [initiallyRunning], coverage: apps.coverage, scannedAt: apps.scannedAt),
            analyses: [.init(application: initiallyRunning, plan: nil, state: .protected)])
        model.install(report.replacing(module: .applications, payload: .applications(runningInventory), completedAt: Date()))
        model.updateRunningApplicationIDs([])
        try check(model.visibleApplications == [app] && model.applicationFilterSummary.visibleCount == 1 && model.applicationFilterSummary.totalCount == 1,
            "a recently stopped app must appear immediately even when its legacy plan needs preparation")
        model.applicationScope = .all
        try check(model.visibleApplications == [app] && model.uninstallAnalysis(for: app) == nil,
            "All must show the app without an actionable plan while it is being analyzed")
        model.applicationScope = .uninstallable
        model.install(report)
        try check(model.visibleApplications == [app] && model.uninstallSelectedIDs.isEmpty && !model.canExecuteUninstallBatch,
            "a newly analyzed app must move to Uninstallable with all items unchecked")
        model.uninstallSelectedIDs = [item.id]
        try check(!model.hasCompletedScan && model.hasScanResult(for: .applications), "fixture must have app results before the full scan finishes")
        try check(model.canExecuteUninstallBatch, "completed app module must allow deletion while other modules scan")
        model.updateRunningApplicationIDs([app.bundleIdentifier])
        try check(model.visibleApplications.isEmpty && !model.canExecuteUninstallBatch && model.uninstallSelectedIDs.isEmpty,
            "a relaunched app must immediately leave Uninstallable and drop its selected items")
        model.applicationScope = .running
        try check(model.visibleApplications.map(\.id) == [app.id] && model.uninstallAnalysis(for: model.visibleApplications[0])?.state == .protected,
            "a relaunched app must appear as protected in Running")
        model.updateRunningApplicationIDs([])
        try check(model.visibleApplications.isEmpty, "a stopped app must leave Running")
        model.applicationScope = .uninstallable
        try check(model.visibleApplications == [app] && model.applicationUninstallPlans.first?.items.map(\.id) == [item.id]
            && model.uninstallSelectedIDs.isEmpty && !model.canExecuteUninstallBatch,
            "a stopped app must reappear in Uninstallable with its existing plan unchecked")
        model.uninstallSelectedIDs = [item.id]
        model.selection = .systemCleanup
        model.selectedIDs = [log.id]
        try check(model.canExecuteSelection && model.canRunOneClickCleanup, "completed system module must allow selected and default cleanup during unrelated scans")
        for state in [ScanModuleState.waiting, .scanning, .failed, .cancelled] {
            model.scanProgressByModule[.general] = .init(module: .general, state: state)
            model.scanProgressByModule[.applications] = .init(module: .applications, state: state)
            try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "unavailable own module must block deletion: \(state)")
        }
        for state in [ScanModuleState.completed, .limited] {
            model.scanProgressByModule[.general] = .init(module: .general, state: state)
            model.scanProgressByModule[.applications] = .init(module: .applications, state: state)
            try check(model.canExecuteSelection && model.canExecuteUninstallBatch, "ready own module permits verified choices: \(state)")
        }
        model.activeScanGenerationID = UUID()
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "previous-generation results cannot authorize cleanup")
        model.activeScanGenerationID = generation
        model.selectedIDs.removeAll()
        model.uninstallSelectedIDs.removeAll()
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "empty selections must stay disabled")
        model.selectedIDs = [log.id]
        model.uninstallSelectedIDs = [item.id]
        model.updateInProgress = true
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "updates block both cleanup entry points")
        model.updateInProgress = false
        model.deepScanningApplicationID = app.id
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "runtime observation blocks execution")
        model.deepScanningApplicationID = nil
        model.isLoadingApplications = true
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "app inventory refresh blocks execution")
        model.isLoadingApplications = false
        model.oneClickCleanupIsRunning = true
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "another cleanup cannot overlap execution")
        model.oneClickCleanupIsRunning = false
        model.phase = .executing
        try check(!model.canExecuteSelection && !model.canExecuteUninstallBatch, "executing cleanup must retain the exclusive mutation gate")

        let effects = [item, log].map {
            OperationResult(candidateID: $0.id, originalURL: $0.url, disposition: .quarantined, status: .succeeded, bytes: $0.bytes)
        }
        model.recordScanCleanupEffects(effects)
        model.pendingExecutionResults = effects
        model.applyPendingExecutionResults()
        try check(model.applications.isEmpty && model.systemReport?.generalCandidates.map(\.id) == [kept.id], "streamed success removes app and system rows immediately")
        try check(model.isScanRunning && model.phase == .executing, "cleanup reconciliation must not stop background scans or reset execution")
        model.scanProgressByModule[.agentEnvironment] = .init(module: .agentEnvironment, state: .limited)
        model.pendingExecutionResults = effects
        model.applyPendingExecutionResults()
        try check(model.scanProgressByModule[.agentEnvironment]?.state == .limited, "cleanup must not rewind newer module progress")
        model.selectedIDs = [kept.id]
        let lateReport = report.replacing(module: .largeFiles, payload: .largeFiles(report.diskUsageTree, []), completedAt: Date())
        model.scanProgressByModule[.largeFiles] = .init(module: .largeFiles, state: .completed)
        model.installProgressive(lateReport, completedModule: .largeFiles, token: token)
        try check(model.applications.isEmpty && model.systemReport?.generalCandidates.map(\.id) == [kept.id], "late progressive snapshots cannot resurrect cleaned rows")
        try check(model.selectedIDs == [kept.id] && model.phase == .executing, "unrelated scan publications preserve selections and execution")
        model.statusMessage = "fixture execution progress"
        let finalReport = SystemScanReport(metadata: report.metadata,
            modules: Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map { ($0, ScanModuleStatus(module: $0, state: .completed)) }),
            generalCandidates: report.generalCandidates, applicationInventory: apps, applicationUninstallInventory: uninstall,
            diskUsageTree: report.diskUsageTree, largeFileCandidates: [], agentAssets: [])
        model.completeScan(finalReport, token: token)
        try check(!model.isScanRunning && model.hasCompletedScan && model.phase == .executing && model.statusMessage == "fixture execution progress", "scan completion cannot end a running cleanup or overwrite its progress")
        try check(model.applications.isEmpty && model.selectedIDs == [kept.id], "final scan snapshot preserves cleanup effects and manual selections")

        // Reverse completion order: cleanup finishes first, then scans publish.
        model.isScanRunning = true
        model.activeScanToken = token
        model.activeScanGenerationID = generation
        model.phase = .completed
        model.installProgressive(report, completedModule: .largeFiles, token: token)
        try check(model.applications.isEmpty && model.isScanRunning && model.phase == .completed, "background publications must continue after cleanup finishes")
        model.completeScan(finalReport, token: UUID())
        try check(model.isScanRunning, "stale scan completion cannot finish the current scan")
        model.phase = .executing
        model.cancelScan()
        try check(!model.isScanRunning && model.phase == .executing, "canceling background scanning cannot cancel cleanup")
        model.installProgressive(report, completedModule: .applications, token: token)
        try check(model.applications.isEmpty, "canceled scan callbacks cannot restore old app rows")
        model.phase = .completed
        model.selectedIDs = [kept.id]
        try check(model.canExecuteSelection, "completed module stays actionable after cancellation of unrelated scans")
        model.phase = .scanning
        model.isScanRunning = true
        model.activeScanToken = token
        model.activeScanGenerationID = generation
        model.oneClickCleanupIsRunning = true
        model.statusMessage = "fixture default cleanup progress"
        model.completeScan(finalReport, token: token)
        try check(model.oneClickCleanupIsRunning && model.statusMessage == "fixture default cleanup progress", "scan completion preserves default-cleanup progress too")
        model.oneClickCleanupIsRunning = false
        model.phase = .reviewing
        let support = CleanupCandidate(url: home.appendingPathComponent("Library/Application Support/Fixture"), displayName: "Fixture", category: .applicationSupport,
            bytes: 25, risk: .review, evidence: [], identity: .init(device: 1, inode: 5, size: 25, modificationTime: 1, kind: .directory), source: .application, lastAccessDate: nil, isActive: false)
        let selectedAppItems = [item, support].map { UninstallItem(candidate: $0, containsUserData: false, isShared: false) }
        let presentationInventory = ApplicationUninstallInventory(applicationInventory: apps, analyses: [
            .init(application: app, plan: .init(application: app, items: selectedAppItems), state: .complete)
        ])
        model.install(report.replacing(module: .applications, payload: .applications(presentationInventory), completedAt: Date()))
        model.uninstallSelectedIDs = [item.id, support.id]
        let uninstallPlan = model.applicationUninstallPlans[0]
        let deletionPlan = try model.planBuilder.build(candidates: [item, support], selectedIDs: [item.id, support.id])
        _ = model.prepareDeletion(plan: deletionPlan, modules: [.applications])
        try check(model.isUninstallItemSelected(uninstallPlan.items[0]) && model.uninstallSelectionState(for: uninstallPlan) == .all,
            "starting uninstall must keep app and item checkmarks selected")
        try check(model.showsDeletionSheet && model.isDeletionInProgress && model.executionProgress.total == 2,
            "starting uninstall must immediately present determinate progress")
        model.toggleUninstall(uninstallPlan)
        model.toggleUninstall(uninstallPlan.items[0])
        model.clearUninstallSelection()
        model.dismissDeletionSheet()
        try check(model.uninstallSelectedIDs == [item.id, support.id] && model.showsDeletionSheet,
            "in-flight selection and progress presentation cannot be cleared")
        let presentationEffects = [support, item].map {
            OperationResult(candidateID: $0.id, originalURL: $0.url, disposition: .quarantined, status: .succeeded, bytes: $0.bytes)
        }
        model.recordScanCleanupEffects([presentationEffects[0]])
        model.pendingExecutionResults = [presentationEffects[0]]
        model.applyPendingExecutionResults()
        try check(model.applications.map(\.id) == [app.id] && model.uninstallSelectedIDs == [item.id]
            && model.uninstallSelectionState(for: model.applicationUninstallPlans[0]) == .all,
            "partial deletion removes completed rows but keeps the app and remaining item checked")
        model.cancelExecution()
        try check(model.isStoppingDeletion && model.isDeletionInProgress && model.showsDeletionSheet,
            "stop request keeps progress visible until the batch actually settles")
        let receipt = OperationReceipt(planID: deletionPlan.id, startedAt: Date(), completedAt: Date(), results: presentationEffects, overallStatus: .completed)
        model.executionProgress = .init(completed: 1, total: 1, currentURL: nil, phase: .movingToTrash)
        model.finishExecutionProgress(receipt)
        try check(model.executionProgress.completed == 2 && model.executionProgress.total == 2
            && model.executionProgress.phase == .savingResults, "saving results restores the whole batch count after a smaller Trash stage")
        model.recordCompletedCleanup(receipt, attemptedCandidates: [item, support])
        model.phase = .completed
        model.deletionResult = receipt
        try check(!model.isDeletionInProgress && model.showsDeletionSheet && model.applications.isEmpty,
            "completion transitions to results while removing confirmed deleted app rows")
        model.dismissDeletionSheet()
        try check(!model.showsDeletionSheet, "dismissing results closes the operation sheet")
        _ = model.prepareDeletion(plan: deletionPlan, modules: [.applications])
        try check(!model.isStoppingDeletion && model.deletionResult == nil && model.deletionResultWarning == nil,
            "new batches reset stop state and previous results")
        model.phase = .failed("fixture")
        model.deletionResultWarning = "fixture failure"
        try check(!model.showsDeletionSheet && !model.isDeletionInProgress,
            "unprocessed items end silently while retaining their execution records")
        model.dismissDeletionSheet()
        try check(!model.showsDeletionSheet, "dismissing execution error clears the sheet")
        model.oneClickCleanupIsRunning = true
        try check(model.isDeletionInProgress && model.showsDeletionSheet, "default system cleanup uses the same progress sheet")
        model.oneClickCleanupIsRunning = false
        print("PASS: model cleanup gates, concurrent scans, retained uninstall checkmarks, progress/result/error presentation, cancellation, and manual-only offline selection")
    }
}

private struct DuplicateFixtureIndex: LargeFileMetadataIndexing {
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] {
        throw LargeFileMetadataIndexError.queryUnavailable
    }
}
