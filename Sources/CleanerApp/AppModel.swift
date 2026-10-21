import CleanerCore
import Foundation
import AppKit
import SwiftUI

typealias SidebarDestination = AppDestination

typealias OneClickCleanupResult = DefaultCleanupModuleResult

private actor ProgressiveScanReportBuilder {
    private let rulesetVersion: String
    private let baseline: SystemScanReport?
    private var accumulator: ProgressiveScanReportAccumulator?

    init(rulesetVersion: String, baseline: SystemScanReport?) {
        self.rulesetVersion = rulesetVersion
        self.baseline = baseline
    }

    func apply(
        _ result: SystemScanModuleResult,
        startedAt: Date,
        initialStatuses: [ScanModuleID: ScanModuleStatus]
    ) -> SystemScanReport? {
        if accumulator == nil {
            accumulator = ProgressiveScanReportAccumulator(
                generationID: result.generationID,
                startedAt: startedAt,
                rulesetVersion: rulesetVersion,
                baseline: baseline,
                initialStatuses: initialStatuses
            )
        }
        guard accumulator?.apply(result) == true else { return nil }
        return accumulator?.report
    }
}

private struct ScanPresentationSnapshots: Sendable {
    let systemCleanupCandidates: [CleanupCandidate]
    let largeFileCandidates: [CleanupCandidate]
    let applicationUninstallPlans: [UninstallPlan]

    static func make(report: SystemScanReport, protectionPolicy: ProtectionPolicy, cleanedIDs: Set<UUID>) -> Self {
        let scopePolicy = CleanupScopePolicy()
        let systemCleanupCandidates = CleanupCandidateVisibility.remaining(
            candidates: scopePolicy.candidates(for: .systemCleanup, from: report.candidates),
            cleanedCandidateIDs: cleanedIDs
        ).map(protectionPolicy.applying)
        let largeFileCandidates = CleanupCandidateVisibility.remaining(
            candidates: scopePolicy.candidates(for: .largeFiles, from: report.candidates),
            cleanedCandidateIDs: cleanedIDs
        ).map(protectionPolicy.applying)
        let applicationUninstallPlans = report.applicationUninstallInventory.plans.map { plan in
            UninstallPlan(
                id: plan.id,
                application: plan.application,
                items: plan.items.map {
                    UninstallItem(
                        candidate: protectionPolicy.applying(to: $0.candidate),
                        containsUserData: $0.containsUserData,
                        isShared: $0.isShared
                    )
                }
            )
        }
        return Self(
            systemCleanupCandidates: systemCleanupCandidates,
            largeFileCandidates: largeFileCandidates,
            applicationUninstallPlans: applicationUninstallPlans
        )
    }
}

@MainActor final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, reviewing, executing, completed, cancelled, failed(String) }
    enum RecoveryActionKind: Equatable { case restore, purge }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var systemReport: SystemScanReport? {
        didSet {
            invalidateCandidatePresentationCaches()
            invalidateAgentEnvironmentCaches()
            cachedScanDiscoverySummary = nil
        }
    }
    @Published private(set) var scanProgressByModule: [ScanModuleID: ScanModuleStatus] = [:]
    @Published private(set) var receipts: [OperationReceipt] = []
    @Published private(set) var quarantineSchedules: [UUID: QuarantineSchedule] = [:]
    @Published private(set) var defaultQuarantineRetentionPolicy: QuarantineRetentionPolicy
    @Published private(set) var largeFileThreshold: LargeFileThreshold
    @Published private(set) var permissionSnapshot: PermissionSnapshot?
    @Published private(set) var executionProgress = ExecutionProgress(completed: 0, total: 0, currentURL: nil)
    @Published var selectedIDs = Set<UUID>() {
        didSet { invalidateAgentSkillPresentationCache() }
    }
    @Published private(set) var excludedBaseIDs = Set<UUID>()
    @Published var selection: SidebarDestination = .cleanupCenter {
        didSet {
            if selection != oldValue, phase != .scanning, phase != .executing {
                statusMessage = nil
            }
        }
    }
    @Published var reviewQuery = "" { didSet { reconcileFocus() } }
    @Published var reviewDispositionFilter: ReviewDispositionFilter = .all { didSet { reconcileFocus() } }
    @Published var showsSelectedOnly = false { didSet { reconcileFocus() } }
    @Published private(set) var cleanupMode: CleanupMode = .defaultMode
    @Published private(set) var focusState = ReviewFocusState()
    @Published var deletionResult: OperationReceipt?
    @Published var deletionResultWarning: String?
    @Published var selectedApplicationID: URL?
    @Published var selectedDiskNodeURL: URL?
    @Published var largeFileSortOrder: LargeFileSortOrder = .size
    @Published var applicationSortOrder: ApplicationSortOrder = .name {
        didSet { reconcileApplicationSelection() }
    }
    @Published var applicationQuery = "" { didSet { reconcileApplicationSelection() } }
    @Published var applicationScope: ApplicationListScope = .uninstallable { didSet { reconcileApplicationSelection() } }
    @Published private(set) var isLoadingApplications = false
    @Published var agentCleanupPresentation: AgentCleanupPresentation?
    var agentCleanupGenerationID: UUID?
    @Published var agentProviderFilter: AgentProvider?
    @Published var agentItemsSelectionFilter: AgentItemsSelectionFilter = .all
    @Published var uninstallSelectedIDs = Set<UUID>()
    @Published var statusMessage: String?
    @Published private(set) var recoveryActionReceiptID: UUID?
    @Published private(set) var recoveryActionKind: RecoveryActionKind?
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var recoveryMessageIsError = false
    @Published var restoreConfirmationReceipt: OperationReceipt?
    @Published var purgeConfirmationReceipt: OperationReceipt?
    @Published private(set) var oneClickCleanupIsRunning = false
    @Published private(set) var oneClickActiveModules = Set<ScanModuleID>()
    @Published private(set) var activeCleanupModules = Set<ScanModuleID>()
    @Published private(set) var cleanedModules = Set<ScanModuleID>()
    @Published private(set) var oneClickCompletedByModule: [ScanModuleID: OneClickCleanupResult] = [:]
    @Published private(set) var sessionCleanupSummary = CleanupSessionSummary()
    @Published private(set) var cleanupFailures: [DefaultCleanupFailure] = []
    @Published private(set) var protectionPolicy: ProtectionPolicy {
        didSet { invalidateCandidatePresentationCaches() }
    }
    @Published private(set) var rulesetVersion = "loading"
    @Published private(set) var configurationMessage: String?
    @Published private(set) var updateInProgress = false
    @Published private(set) var bootstrapInProgress = true
    @Published private(set) var maintenanceInProgress = false
    let helper: HelperSettingsModel

    private let home: URL
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
        !updateInProgress && !bootstrapInProgress && !maintenanceInProgress && !helper.isChanging && !isLoadingApplications
            && phase != .scanning && phase != .executing && !oneClickCleanupIsRunning && recoveryActionReceiptID == nil
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
    private var activeScanToken: UUID?
    private var activeScanGenerationID: UUID?
    private var executionTask: Task<Void, Never>?
    private var oneClickExecutionTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var oneClickCleanedCandidateIDs = Set<UUID>() {
        didSet {
            invalidateCandidatePresentationCaches()
            invalidateAgentEnvironmentCaches()
        }
    }
    private var cachedAllCandidates: [CleanupCandidate]?
    private var cachedCandidatesByDestination: [SidebarDestination: [CleanupCandidate]] = [:]
    private var cachedApplicationUninstallPlans: [UninstallPlan]?
    private var cachedAgentSkillPresentation: AgentSkillCatalogPresentation?
    private var cachedScanDiscoverySummary: ScanDiscoverySummary?
    private var cachedAgentSkillPresentationGenerationID: UUID?
    private var cachedAgentSkillPresentationCompletedAt: Date?
    private var cachedAgentSkillPresentationSelectedIDs = Set<UUID>()
    private var cachedAgentCandidateByPath: [String: CleanupCandidate]?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        protectionPolicy = ProtectionPolicy(homeDirectory: home)
        defaultQuarantineRetentionPolicy = UserDefaults.standard.string(
            forKey: Self.quarantineRetentionDefaultsKey
        ).flatMap(QuarantineRetentionPolicy.init(rawValue:)) ?? .hours24
        let storedLargeFileBytes = (UserDefaults.standard.object(
            forKey: Self.largeFileThresholdDefaultsKey
        ) as? NSNumber)?.uint64Value
        largeFileThreshold = LargeFileThreshold(storedBytes: storedLargeFileBytes)
        let infrastructure = AppInfrastructure.live(home: home)
        fileSystem = infrastructure.fileSystem
        helper = infrastructure.helper
        runtime = infrastructure.runtime
        cleanupExecutionCoordinator = infrastructure.cleanupCoordinator
        helper.configureAvailability { [weak self] in
            guard let self else { return false }
            return !updateInProgress && phase != .executing && phase != .scanning
        }
    }

    private static let quarantineRetentionDefaultsKey = "quarantine.retentionPolicy"
    private static let largeFileThresholdDefaultsKey = "largeFiles.minimumBytes"
    private static let appManagementObservationDefaultsKey = "permissions.appManagementObservation"

    var hasCompletedScan: Bool { systemReport?.isCommitEligible == true }

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
            globalScanIsRunning: phase == .scanning,
            availableModules: availableModules
        )
    }

    func openScanResult(_ module: ScanModuleID) {
        guard let destination = scanResultDestination(for: module) else { return }
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
    var applications: [InstalledApplication] { systemReport?.applicationInventory.applications ?? [] }
    var diskUsageTree: DiskUsageTree? { systemReport?.diskUsageTree }
    var largeFileThresholdNeedsRefresh: Bool {
        guard let diskUsageTree else { return false }
        return diskUsageTree.minimumFileBytes != largeFileThreshold.bytes
    }
    var agentAssets: [AgentAssetRecord] {
        let cleanedIDs = oneClickCleanedCandidateIDs
        return (systemReport?.agentAssets ?? []).filter { !cleanedIDs.contains($0.id) }
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
    var agentSkillCatalogPresentation: AgentSkillCatalogPresentation {
        if let cachedAgentSkillPresentation,
           cachedAgentSkillPresentationGenerationID == systemReport?.generationID,
           cachedAgentSkillPresentationCompletedAt == systemReport?.completedAt,
           cachedAgentSkillPresentationSelectedIDs == selectedIDs {
            return cachedAgentSkillPresentation
        }
        let presentation = AgentSkillCatalogPresentation(
            skills: agentSkills,
            assets: agentAssets,
            selectedIDs: selectedIDs
        )
        cachedAgentSkillPresentation = presentation
        cachedAgentSkillPresentationGenerationID = systemReport?.generationID
        cachedAgentSkillPresentationCompletedAt = systemReport?.completedAt
        cachedAgentSkillPresentationSelectedIDs = selectedIDs
        return presentation
    }
    var visibleAgentSkillSections: [AgentSkillCatalogSection] {
        agentSkillCatalogPresentation.filteredSections(
            query: "",
            scope: nil,
            provider: agentProviderFilter,
            deletableOnly: false
        ).compactMap { section in
            let skills = section.skills.filter { binding in
                agentItemsSelectionFilter == .all || binding.decision == .plannedForDeletion
            }
            guard !skills.isEmpty else { return nil }
            return AgentSkillCatalogSection(group: section.group, skills: skills)
        }
    }
    var visibleAgentSkillBindings: [AgentSkillCleanupBinding] {
        visibleAgentSkillSections.flatMap(\.skills)
    }
    var visibleAgentMCPConfigurations: [MCPConfigurationRecord] {
        agentMCPConfigurations.filter { configuration in
            let providerMatches = agentProviderFilter == nil || configuration.provider == agentProviderFilter
            guard providerMatches else { return false }
            guard agentItemsSelectionFilter == .selected else { return true }
            guard let candidate = agentMCPCandidate(for: configuration) else { return false }
            return selectedIDs.contains(candidate.id)
        }
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
    var isCurrentModuleScanning: Bool {
        let module: ScanModuleID?
        switch selection {
        case .systemCleanup: module = .general
        case .applications: module = .applications
        case .largeFiles: module = .largeFiles
        case .agentEnvironment: module = .agentEnvironment
        default: module = nil
        }
        return navigationPolicy.showsModuleScanControls(
            for: selection,
            globalScanIsRunning: phase == .scanning,
            moduleState: module.flatMap { scanProgressByModule[$0]?.state }
        )
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates(for: selection).filter { selectedIDs.contains($0.id) }
    }
    var selectedBytes: UInt64 { selectedCandidates.reduce(0) { $0 + $1.bytes } }
    var focusedCandidateID: UUID? { focusState.focusedCandidateID }
    var inspectedCandidate: CleanupCandidate? {
        guard let focusedCandidateID else { return nil }
        return visibleCandidates(for: selection).first { $0.id == focusedCandidateID }
    }
    var hiddenSelectedCount: Int {
        let visible = Set(visibleCandidates(for: selection).map(\.id))
        return Set(selectedCandidates.map(\.id)).subtracting(visible).count
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
        let defaults = defaultCleanupPolicy.selection(for: report)
        let excludedIDs = oneClickCleanedCandidateIDs.union(cleanupFailures.map(\.candidate.id))
        return DefaultCleanupSelection(
            systemCleanup: hasScanResult(for: .general)
                ? defaults.systemCleanup.filter { !excludedIDs.contains($0.id) && (try? protectionPolicy.validate($0.url)) != nil }
                : [],
            applicationUninstall: [],
            largeFiles: [],
            agentEnvironment: []
        )
    }
    var canRunOneClickCleanup: Bool {
        hasScanResult(for: .general)
            && !updateInProgress
            && !(defaultCleanupSelection?.systemCleanup.isEmpty ?? true)
            && !oneClickCleanupIsRunning
            && phase != .executing
    }

    func oneClickStatus(for module: ScanModuleID) -> String? {
        if oneClickActiveModules.contains(module) { return L10n.text("正在清理默认项…") }
        let failures = failedCleanupResult(for: module)
        if failures.itemCount > 0 {
            if let result = oneClickCompletedByModule[module], result.itemCount > 0 {
                return L10n.text("已清理 {0} 项 · {1}　未处理 {2} 项 · {3}", String(describing: result.itemCount), String(describing: ByteCountFormatter.cleanerString(bytes: result.bytes)), String(describing: failures.itemCount), String(describing: ByteCountFormatter.cleanerString(bytes: failures.bytes)))
            }
            return L10n.text("未处理 {0} 项 · {1}", String(describing: failures.itemCount), String(describing: ByteCountFormatter.cleanerString(bytes: failures.bytes)))
        }
        if let result = oneClickCompletedByModule[module] {
            return result.itemCount > 0
                ? L10n.text("已清理 {0} 项 · {1}", String(describing: result.itemCount), String(describing: ByteCountFormatter.cleanerString(bytes: result.bytes)))
                : L10n.text("无需清理")
        }
        guard hasScanResult(for: module) else { return nil }
        if module == .applications { return L10n.text("请手动选择要卸载的项目") }
        let count = defaultCleanupCount(for: module)
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
        let filtered = ApplicationListFilter(query: applicationQuery, scope: applicationScope).apply(to: applications)
        let selectedApplicationURLs = applicationSortOrder == .selection
            ? Set(applicationUninstallPlans.compactMap { plan in
                plan.items.contains(where: { uninstallSelectedIDs.contains($0.id) })
                    ? plan.application.bundleURL.standardizedFileURL
                    : nil
            })
            : []
        return applicationSortOrder.sorted(filtered, selectedApplicationURLs: selectedApplicationURLs)
    }
    var applicationFilterSummary: ApplicationFilterSummary {
        ApplicationListFilter(query: applicationQuery, scope: applicationScope).summary(for: applications)
    }
    var applicationUninstallPlans: [UninstallPlan] {
        if let cachedApplicationUninstallPlans { return cachedApplicationUninstallPlans }
        let plans = (systemReport?.applicationUninstallInventory.plans ?? []).map { plan in
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
    var canExecuteUninstallBatch: Bool {
        hasCompletedScan
            && !updateInProgress
            && !uninstallSelectedIDs.isEmpty
            && phase != .scanning
            && phase != .executing
            && !oneClickCleanupIsRunning
    }

    func uninstallAnalysis(for application: InstalledApplication) -> ApplicationUninstallAnalysis? {
        guard let analysis = systemReport?.applicationUninstallInventory.analysis(for: application.id) else { return nil }
        return ApplicationUninstallAnalysis(application: analysis.application,
            plan: applicationUninstallPlans.first { $0.application.id == application.id }, state: analysis.state,
            message: analysis.message, limitations: analysis.limitations, ownership: analysis.ownership)
    }

    func openOfficialUninstaller(for application: InstalledApplication, expectedURL: URL) {
        guard !updateInProgress else { return }
        guard phase != .scanning, phase != .executing else { return }
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
        recommendationPolicy.breakdown(for: candidates(for: destination))
    }

    func candidates(for destination: SidebarDestination) -> [CleanupCandidate] {
        if destination == .agentEnvironment {
            return agentAssets.map(\.candidate)
        }
        if let cached = cachedCandidatesByDestination[destination] { return cached }
        let scoped = scopePolicy.candidates(for: destination, from: systemReport?.candidates ?? [])
        let result = CleanupCandidateVisibility.remaining(
            candidates: scoped,
            cleanedCandidateIDs: oneClickCleanedCandidateIDs
        ).map(protectionPolicy.applying)
        cachedCandidatesByDestination[destination] = result
        return result
    }

    func visibleCandidates(for destination: SidebarDestination) -> [CleanupCandidate] {
        if destination == .agentEnvironment {
            return currentAgentCleanupPresentation?
                .filteredGroups(scope: nil, kind: nil)
                .flatMap(\.assets).map(\.candidate) ?? []
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
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await bootstrapPersistentState()
            bootstrapInProgress = false
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
        guard phase != .executing, phase != .scanning else { return }
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
        UserDefaults.standard.set(NSNumber(value: threshold.bytes), forKey: Self.largeFileThresholdDefaultsKey)
        if hasCompletedScan {
            statusMessage = L10n.text("大文件标准已更新为 ≥ {0}；刷新大文件模块后生效", String(describing: threshold.shortTitle))
        }
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
        guard !updateInProgress else { return }
        guard phase != .scanning, phase != .executing, !oneClickCleanupIsRunning else { return }
        guard PermissionScanStartPolicy.shouldStartFullScan(
            fullDiskAccess: permissionSnapshot?.fullDiskAccess.status ?? .unverified
        ) else { return }
        beginFullScan()
    }

    private func beginFullScan() {
        scanTask?.cancel()
        let scanToken = UUID()
        activeScanToken = scanToken
        activeScanGenerationID = nil
        oneClickCleanedCandidateIDs.removeAll()
        activeCleanupModules.removeAll()
        cleanedModules.removeAll()
        oneClickCompletedByModule.removeAll()
        cleanupFailures.removeAll()
        phase = .scanning
        statusMessage = systemReport == nil
            ? L10n.text("扫描开始后将依次请求桌面、文稿和下载文件夹权限；拒绝某项后会继续扫描其余可访问位置")
            : L10n.text("正在重新扫描；需要时将依次请求文件夹权限，完成前继续保留上一次结果")
        scanProgressByModule = Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
            ($0, ScanModuleStatus(module: $0, state: .waiting))
        })
        scanTask = Task { [weak self] in await self?.runScan(token: scanToken) }
    }

    func applicationDidBecomeActive() {
        Task { [weak self] in
            guard let self else { return }
            await loadPermissions()
            await runQuarantineMaintenance()
        }
    }

    func cancelScan() {
        scanTask?.cancel(); scanTask = nil; phase = .cancelled
        activeScanToken = nil
        activeScanGenerationID = nil
        scanProgressByModule = scanProgressByModule.mapValues { status in
            status.state.isTerminal ? status : ScanModuleStatus(
                module: status.module,
                state: .cancelled,
                startedAt: status.startedAt,
                completedAt: Date(),
                message: L10n.text("用户已取消")
            )
        }
        if systemReport?.isCommitEligible == true {
            phase = .reviewing
            statusMessage = L10n.text("扫描已取消，继续使用上一次完整结果")
        } else if systemReport != nil {
            phase = .reviewing
            statusMessage = L10n.text("扫描已取消；已经完成的模块结果仍可查看")
        } else {
            statusMessage = L10n.text("扫描已取消，没有生成报告，也没有修改文件")
        }
    }

    func toggle(_ candidate: CleanupCandidate) {
        guard candidate.risk.isSelectable else { return }
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

    func cleanupSelectionState(for candidates: [CleanupCandidate]) -> SelectionTriState {
        guard let generationID = systemReport?.generationID else { return .none }
        return CleanupStrategySelectionState(
            strategy: cleanupMode,
            generationID: generationID,
            selectedIDs: selectedIDs,
            excludedBaseIDs: excludedBaseIDs
        ).selectionState(for: Set(candidates.filter { $0.risk.isSelectable }.map(\.id)))
    }

    func toggleCleanupCategory(_ candidates: [CleanupCandidate]) {
        guard let generationID = systemReport?.generationID else { return }
        var state = CleanupStrategySelectionState(
            strategy: cleanupMode,
            generationID: generationID,
            selectedIDs: selectedIDs,
            excludedBaseIDs: excludedBaseIDs
        )
        state.toggleCategory(candidates: candidates, baseEligibleIDs: cleanupBaseEligibleIDs)
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

    func toggleDiskFile(_ node: DiskUsageNode) {
        guard node.kind == .file,
              let candidate = largeFileCandidatesByPath[node.url.standardizedFileURL.path]
        else { return }
        toggle(candidate)
    }

    func isDiskFileSelected(_ node: DiskUsageNode) -> Bool {
        guard let candidate = largeFileCandidatesByPath[node.url.standardizedFileURL.path] else { return false }
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
        guard let binding = agentSkillCatalogPresentation.binding(for: skillID) else { return }
        switch decision {
        case .retain, .deletionUnavailable:
            selectedIDs.subtract(binding.selectableCandidateIDs)
        case .plannedForDeletion:
            guard binding.isDeletionAvailable else { return }
            selectedIDs.formUnion(binding.selectableCandidateIDs)
        }
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
            selectedIDs.subtract(selected.map(\.id))
            reconcileFocus()
        }
    }

    func requestExecution() {
        guard !updateInProgress else { return }
        guard hasCompletedScan, phase != .scanning, phase != .executing, !oneClickCleanupIsRunning else { return }
        let selected = Set(selectedCandidates.map(\.id))
        guard !selected.isEmpty else { return }
        do {
            let plan = try planBuilder.build(candidates: candidates(for: selection), selectedIDs: selected)
            executeSelection(plan: plan)
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
            oneClickActiveModules = [.general]
            oneClickCleanupIsRunning = true
            statusMessage = L10n.text("正在执行一键系统清理")
            executionProgress = ExecutionProgress(completed: 0, total: plan.selectedItems.count, currentURL: nil)
            oneClickExecutionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let receipt = try await cleanupExecutionCoordinator.execute(
                        plan: plan,
                        retentionPolicy: defaultQuarantineRetentionPolicy,
                        progress: { progress in
                            Task { @MainActor [weak self] in self?.executionProgress = progress }
                        }
                    )
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
                    statusMessage = outcome.failures.isEmpty
                        ? L10n.text("系统清理完成")
                        : L10n.text("系统清理完成；{0} 项未处理，可查看原因并安全重试", String(describing: outcome.failures.count))
                } catch {
                    statusMessage = L10n.text("系统清理未完成，执行记录已保留以供启动恢复：{0}", String(describing: error.localizedDescription))
                    deletionResultWarning = statusMessage
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

    func retryCleanupFailures(_ failures: [DefaultCleanupFailure]) {
        guard !updateInProgress else { return }
        guard phase != .scanning, phase != .executing, !oneClickCleanupIsRunning else { return }
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
        guard !updateInProgress else { return }
        deletionResultWarning = nil
        activeCleanupModules = Set(plan.selectedItems.compactMap { oneClickModule(for: $0.candidate) })
        executionProgress = ExecutionProgress(completed: 0, total: plan.selectedItems.count, currentURL: nil)
        statusMessage = L10n.text("正在检查并删除所选项目")
        phase = .executing
        executionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await cleanupExecutionCoordinator.execute(
                    plan: plan,
                    retentionPolicy: defaultQuarantineRetentionPolicy,
                    progress: { progress in
                        Task { @MainActor [weak self] in self?.executionProgress = progress }
                    }
                )
                await reloadHistory()
                await reloadQuarantineSchedules()
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
                phase = receipt.overallStatus == .completed ? .completed : .failed(L10n.text("部分项目未处理，请查看逐项原因"))
                deletionResult = receipt
            } catch {
                statusMessage = L10n.text("删除未完成，执行记录已保留以供启动恢复：{0}", String(describing: error.localizedDescription))
                deletionResultWarning = statusMessage
                phase = .failed(statusMessage ?? L10n.text("删除未完成"))
            }
            activeCleanupModules.removeAll()
            executionTask = nil
        }
    }

    func cancelExecution() {
        executionTask?.cancel()
        statusMessage = L10n.text("正在完成当前原子移动，尚未开始的项目将停止")
    }

    func requestRestore(_ receipt: OperationReceipt) {
        guard !updateInProgress else { return }
        guard recoveryActionReceiptID == nil,
              receipt.results.contains(where: { $0.disposition == .quarantined })
        else { return }
        restoreConfirmationReceipt = receipt
    }

    func dismissRestoreConfirmation() { restoreConfirmationReceipt = nil }

    func confirmRestore() {
        guard !updateInProgress else { return }
        guard let receipt = restoreConfirmationReceipt, recoveryActionReceiptID == nil else { return }
        restoreConfirmationReceipt = nil
        restore(receipt)
    }

    private func restore(_ receipt: OperationReceipt) {
        guard !updateInProgress else { return }
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
            } catch {
                recoveryMessage = L10n.text("文件已处理，但恢复记录更新失败：{0}", String(describing: error.localizedDescription))
                recoveryMessageIsError = true
            }
            recoveryActionReceiptID = nil
            recoveryActionKind = nil
        }
    }

    func requestPermanentDeletion(_ receipt: OperationReceipt) {
        guard !updateInProgress else { return }
        guard recoveryActionReceiptID == nil,
              receipt.results.contains(where: { $0.disposition == .quarantined })
        else { return }
        purgeConfirmationReceipt = receipt
    }

    func dismissPermanentDeletion() { purgeConfirmationReceipt = nil }

    func confirmPermanentDeletion() {
        guard !updateInProgress else { return }
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

    func refreshApplications() {
        guard !updateInProgress else { return }
        guard systemReport != nil else { selection = .cleanupCenter; return }
        Task { [weak self] in await self?.reloadApplicationModule() }
    }

    private func reconcileApplicationSelection() {
        let visible = visibleApplications
        if let selectedApplicationID, visible.contains(where: { $0.id == selectedApplicationID }) { return }
        selectedApplicationID = visible.first?.id
    }

    func toggleUninstall(_ item: UninstallItem) {
        var selection = uninstallSelectionState
        selection.toggle(item: item)
        uninstallSelectedIDs = selection.selectedItemIDs
    }

    func toggleUninstall(_ plan: UninstallPlan) {
        var selection = uninstallSelectionState
        selection.toggle(plan: plan)
        uninstallSelectedIDs = selection.selectedItemIDs
    }

    func clearUninstallSelection() {
        uninstallSelectedIDs.removeAll()
    }

    func executeUninstallBatch() {
        guard !updateInProgress else { return }
        guard phase != .scanning, phase != .executing, !oneClickCleanupIsRunning else { return }
        let selection = uninstallSelectionState
        let selectedItems = selection.selectedItems(in: applicationUninstallPlans)
        let summary = selection.summary(plans: applicationUninstallPlans)
        guard !selectedItems.isEmpty else {
            statusMessage = L10n.text("请先勾选要卸载的应用或具体项目")
            return
        }
        do {
            let plan = try planBuilder.build(
                candidates: selectedItems.map(\.candidate),
                selectedIDs: selection.selectedItemIDs
            )
            uninstallSelectedIDs.removeAll()
            deletionResultWarning = nil
            activeCleanupModules = [.applications]
            phase = .executing
            executionTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let receipt = try await cleanupExecutionCoordinator.execute(
                        plan: plan,
                        retentionPolicy: defaultQuarantineRetentionPolicy
                    )
                    recordAppManagementObservation(from: receipt, selectedItems: selectedItems)
                    await reloadHistory()
                    await reloadQuarantineSchedules()
                    recordCompletedCleanup(receipt, attemptedCandidates: selectedItems.map(\.candidate))
                    await reloadApplicationModule()
                    phase = receipt.overallStatus == .completed ? .completed : .failed(L10n.text("部分卸载项未处理"))
                    if receipt.overallStatus == .completed {
                        statusMessage = L10n.text("已删除 {0} 个应用的 {1} 项，可在恢复记录中撤销", String(describing: summary.applicationCount), String(describing: summary.itemCount))
                    }
                    deletionResult = receipt
                } catch {
                    statusMessage = L10n.text("应用卸载未完成，执行记录已保留以供启动恢复：{0}", String(describing: error.localizedDescription))
                    deletionResultWarning = statusMessage
                    phase = .failed(statusMessage ?? L10n.text("应用卸载未完成"))
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
        guard let url = permissionSnapshot?.fullDiskAccess.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openAppManagementSettings() {
        guard let url = permissionSnapshot?.appManagement.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func runScan(token: UUID) async {
        await ScanPermissionPreflight(fileSystem: fileSystem).requestStandardFolderAccess(homeDirectory: home)
        guard !Task.isCancelled, activeScanToken == token else { return }
        statusMessage = L10n.text("文件夹权限检查完成，正在扫描支持且可安全访问的位置；不会修改任何文件")
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
            scanTask = nil
            return
        }
        let context = configuration.context
        let coordinator = SystemScanCoordinator(
            diskUsageScanner: DiskUsageScanner(minimumFileBytes: largeFileThreshold.bytes, maximumDepth: 8, maximumEntries: 50_000),
            rulePack: configuration.pack
        )
        let reportBuilder = ProgressiveScanReportBuilder(
            rulesetVersion: rulesetVersion,
            baseline: systemReport
        )
        let next = await coordinator.scan(
            context: context,
            runningBundleIdentifiers: Set(runningBundleIDs),
            moduleResult: { [weak self] result in
                let initialState = await MainActor.run {
                    guard let self else { return (Date(), [ScanModuleID: ScanModuleStatus]()) }
                    let startedAt = self.scanProgressByModule.values.compactMap(\.startedAt).min() ?? Date()
                    return (startedAt, self.scanProgressByModule)
                }
                guard let report = await reportBuilder.apply(
                    result,
                    startedAt: initialState.0,
                    initialStatuses: initialState.1
                ) else { return }
                await MainActor.run {
                    self?.installProgressive(report, completedModule: result.module, token: token)
                }
            }
        ) { [weak self] event in
            await MainActor.run {
                guard let self, self.activeScanToken == token else { return }
                if self.activeScanGenerationID == nil {
                    self.activeScanGenerationID = event.generationID
                }
                guard self.activeScanGenerationID == event.generationID else { return }
                let previous = self.scanProgressByModule[event.module]
                self.scanProgressByModule[event.module] = ScanModuleStatus(
                    module: event.module,
                    state: event.state,
                    startedAt: previous?.startedAt ?? (event.state == .scanning ? Date() : nil),
                    completedAt: event.state.isTerminal ? Date() : nil,
                    message: event.message,
                    limitations: event.limitations
                )
            }
        }
        guard !Task.isCancelled, activeScanToken == token, let next else { return }
        let policySnapshot = protectionPolicy
        let cleanedIDsSnapshot = oneClickCleanedCandidateIDs
        let presentationSnapshots = await Task.detached(priority: .userInitiated) {
            ScanPresentationSnapshots.make(
                report: next,
                protectionPolicy: policySnapshot,
                cleanedIDs: cleanedIDsSnapshot
            )
        }.value
        guard !Task.isCancelled, activeScanToken == token else { return }
        install(next)
        cachedCandidatesByDestination[.systemCleanup] = presentationSnapshots.systemCleanupCandidates
        cachedCandidatesByDestination[.largeFiles] = presentationSnapshots.largeFileCandidates
        cachedApplicationUninstallPlans = presentationSnapshots.applicationUninstallPlans
        activeScanToken = nil
        activeScanGenerationID = nil
        cleanupMode = .defaultMode
        let defaults = defaultCleanupPolicy.selection(for: next)
        selectedIDs = Set((defaults.systemCleanup + defaults.largeFiles + defaults.agentEnvironment).map(\.id))
            .subtracting(oneClickCleanedCandidateIDs)
        reconcileFocus()
        phase = .reviewing
        scanTask = nil
        let limitedCount = next.modules.values.filter { [.limited, .failed].contains($0.state) }.count
        statusMessage = limitedCount == 0 ? L10n.text("完整扫描完成，已生成清理方案") : L10n.text("扫描完成，{0} 个模块存在访问限制", String(describing: limitedCount))
    }

    private func installProgressive(
        _ next: SystemScanReport,
        completedModule: ScanModuleID,
        token: UUID
    ) {
        guard phase == .scanning,
              activeScanToken == token,
              activeScanGenerationID == next.generationID
        else { return }
        let previousLargeFileIDs = Set(systemReport?.largeFileCandidates.map(\.id) ?? [])
        let diskSelection = DiskUsageSelectionState(
            candidates: systemReport?.largeFileCandidates ?? [],
            selectedIDs: selectedIDs
        )
        let generationChanged = systemReport?.generationID != next.generationID
        systemReport = next
        if completedModule == .largeFiles {
            indexLargeFileCandidates(next.largeFileCandidates)
        }
        if generationChanged {
            selectedIDs.removeAll()
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
        let visibleStatus = phase == .scanning
            ? scanProgressByModule[module]
            : report.modules[module]
        guard let state = visibleStatus?.state,
              let destination = navigationPolicy.scanResultDestination(for: module, state: state),
              navigationPolicy.scanResultDestination(
                for: module,
                state: report.modules[module]?.state ?? .waiting
              ) != nil
        else { return nil }
        if phase == .scanning, report.generationID != activeScanGenerationID { return nil }
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
            _ = try await cleanupExecutionCoordinator.migrateUnscheduled(
                policy: defaultQuarantineRetentionPolicy,
                at: Date()
            )
        } catch {
            recoveryMessage = L10n.text("已删除项目自动清除计划加载失败：{0}", String(describing: error.localizedDescription))
            recoveryMessageIsError = true
        }
        await reloadQuarantineSchedules()
        await runQuarantineMaintenance()
        await loadPermissions()
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
        guard !updateInProgress else { return }
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
    private func reloadApplicationModule() async {
        guard !updateInProgress else { return }
        guard let current = systemReport else { return }
        isLoadingApplications = true
        defer { isLoadingApplications = false }
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let inventory = await ApplicationScanner().installedApplications(
            context: ScanContext(homeDirectory: home, fileSystem: fileSystem, protectionPolicy: protectionPolicy),
            runningBundleIdentifiers: runningBundleIDs
        )
        let analyzedInventory = await ApplicationUninstallAnalyzer().analyze(
            inventory: inventory,
            context: ScanContext(homeDirectory: home, fileSystem: fileSystem, protectionPolicy: protectionPolicy)
        )
        let updated = current.replacing(
            module: .applications,
            payload: .applications(analyzedInventory),
            completedAt: Date()
        )
        install(updated)
        var uninstallSelection = uninstallSelectionState
        uninstallSelection.reconcile(plans: updated.applicationUninstallInventory.plans)
        uninstallSelectedIDs = uninstallSelection.selectedItemIDs
        if !applications.contains(where: { $0.id == selectedApplicationID }) {
            selectedApplicationID = applications.first?.id
        }
    }

    func refreshModule(_ module: ScanModuleID) {
        guard !updateInProgress else { return }
        guard systemReport != nil,
              [.largeFiles, .agentEnvironment].contains(module),
              phase != .scanning,
              phase != .executing,
              !oneClickCleanupIsRunning
        else {
            if systemReport == nil { selection = .cleanupCenter }
            return
        }
        scanProgressByModule[module] = ScanModuleStatus(module: module, state: .scanning, startedAt: Date())
        phase = .scanning
        scanTask = Task { [weak self] in
            guard let self, let current = systemReport else { return }
            let context = scanContext()
            do {
                let updated: SystemScanReport
                switch module {
                case .largeFiles:
                    let minimumBytes = largeFileThreshold.bytes
                    let tree = try await DiskUsageScanner(minimumFileBytes: minimumBytes).scan(context: context)
                    let candidates = try await LargeFileScanner(minimumBytes: minimumBytes).candidates(from: tree, context: context)
                    updated = current.replacing(module: module, payload: .largeFiles(tree, candidates), completedAt: tree.scannedAt)
                case .agentEnvironment:
                    let inventory = try await AgentWorkspaceScanner().scanAssetInventory(context: context)
                    updated = current.replacing(
                        module: module,
                        payload: .agentEnvironment(inventory),
                        completedAt: Date()
                    )
                case .general, .applications:
                    return
                }
                guard !Task.isCancelled else { return }
                install(updated)
                let defaults = defaultCleanupPolicy.selection(for: updated)
                switch module {
                case .largeFiles:
                    selectedIDs.subtract(current.largeFileCandidates.map(\.id))
                    selectedIDs.formUnion(
                        Set(defaults.largeFiles.map(\.id)).subtracting(oneClickCleanedCandidateIDs)
                    )
                case .agentEnvironment:
                    selectedIDs.subtract(current.agentAssets.map(\.id))
                    selectedIDs.formUnion(
                        Set(defaults.agentEnvironment.map(\.id)).subtracting(oneClickCleanedCandidateIDs)
                    )
                case .general, .applications:
                    break
                }
                phase = .reviewing
                scanTask = nil
                statusMessage = L10n.text("模块已刷新；其他模块保留各自的扫描时间")
            } catch {
                phase = .failed(L10n.text("模块刷新失败"))
                scanTask = nil
                statusMessage = L10n.text("模块刷新失败：{0}", String(describing: error.localizedDescription))
            }
        }
    }

    private func rulesDidChange(_ pack: RulePack) {
        rulesetVersion = pack.executionVersion
        systemReport = nil; scanProgressByModule.removeAll()
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

    private func install(_ next: SystemScanReport) {
        let generationChanged = systemReport?.generationID != next.generationID
        systemReport = next
        indexLargeFileCandidates(next.largeFileCandidates)
        scanProgressByModule = next.modules
        if generationChanged {
            selectedIDs.removeAll()
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
    private func loadPermissions() async {
        let storedObservation = UserDefaults.standard.string(
            forKey: Self.appManagementObservationDefaultsKey
        ).flatMap(PermissionCapabilityStatus.init(rawValue:)) ?? .unverified
        permissionSnapshot = await PermissionStatusService(
            fileSystem: fileSystem,
            homeDirectory: home,
            appManagementObservation: storedObservation
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
        Task { [weak self] in await self?.loadPermissions() }
    }

    private func invalidateAgentSkillPresentationCache() {
        cachedAgentSkillPresentation = nil
        cachedAgentSkillPresentationGenerationID = nil
        cachedAgentSkillPresentationCompletedAt = nil
        cachedAgentSkillPresentationSelectedIDs.removeAll(keepingCapacity: true)
    }

    private func invalidateAgentEnvironmentCaches() {
        invalidateAgentSkillPresentationCache()
        cachedAgentCandidateByPath = nil
    }

    private func invalidateCandidatePresentationCaches() {
        cachedAllCandidates = nil
        cachedCandidatesByDestination.removeAll()
        cachedApplicationUninstallPlans = nil
    }

}
