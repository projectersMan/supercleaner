import Foundation

public enum ApplicationUninstallCoverageState: String, Codable, Hashable, Sendable {
    case complete
    case limited
    case protected
    case unavailable
}

public struct ApplicationUninstallAnalysis: Identifiable, Codable, Hashable, Sendable {
    public var id: URL { application.id }
    public let application: InstalledApplication
    public let plan: UninstallPlan?
    public let state: ApplicationUninstallCoverageState
    public let message: String?
    public let limitations: [ScanLimitation]
    public let ownership: ApplicationOwnershipNode?
    public let runtimeObservation: ApplicationRuntimeObservation?
    public let preparedPlan: UninstallPlan?
    public let preparedState: ApplicationUninstallCoverageState?
    public let preparedMessage: String?

    public init(
        application: InstalledApplication,
        plan: UninstallPlan?,
        state: ApplicationUninstallCoverageState,
        message: String? = nil,
        limitations: [ScanLimitation] = [],
        ownership: ApplicationOwnershipNode? = nil,
        runtimeObservation: ApplicationRuntimeObservation? = nil,
        preparedPlan: UninstallPlan? = nil,
        preparedState: ApplicationUninstallCoverageState? = nil,
        preparedMessage: String? = nil
    ) {
        self.application = application
        self.plan = plan
        self.state = state
        self.message = message
        self.limitations = limitations
        self.ownership = ownership
        self.runtimeObservation = runtimeObservation
        self.preparedPlan = preparedPlan
        self.preparedState = preparedState
        self.preparedMessage = preparedMessage
    }

    /// Toggle availability without rediscovery, size traversal, or new item IDs.
    public func withRunningState(_ running: Bool) -> Self {
        guard !application.isSystem else { return self }
        let availablePlan = preparedPlan ?? plan
        let availableState = preparedState ?? state
        let availableMessage = preparedState == nil ? message : preparedMessage
        return Self(application: application.withRunningState(running),
            plan: running ? nil : availablePlan,
            state: running ? .protected : availableState,
            message: running ? L10n.text("应用正在运行，因此暂时不能卸载。退出应用后会自动更新。") : availableMessage,
            limitations: limitations, ownership: ownership, runtimeObservation: runtimeObservation,
            preparedPlan: availablePlan, preparedState: availableState, preparedMessage: availableMessage)
    }

    public var statusTitle: String {
        switch state {
        case .complete: return L10n.text("基础分析完成")
        case .limited: return L10n.text("可卸载 · 部分未统计")
        case .unavailable: return L10n.text("无法分析")
        case .protected:
            return application.isRunning ? L10n.text("运行中 · 暂不可卸载") : L10n.text("当前应用没有可选择的卸载项目")
        }
    }
}

public struct ApplicationUninstallDisclosureState: Codable, Hashable, Sendable {
    public private(set) var isExpanded: Bool

    public init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    public mutating func toggle() {
        isExpanded.toggle()
    }
}

public enum ApplicationUninstallRowInteraction {
    public static func action(clickCount: Int) -> DirectoryRowClickAction {
        clickCount >= 1 ? .selectAndToggleExpansion : .select
    }
}

public struct ApplicationUninstallInventory: Codable, Hashable, Sendable {
    public let applicationInventory: ApplicationInventory
    public let analyses: [ApplicationUninstallAnalysis]
    public let associationCoverage: CoverageSummary
    public let associationIndex: ApplicationAssociationIndex?
    public let ownershipGraph: ApplicationOwnershipGraph?

    public init(
        applicationInventory: ApplicationInventory,
        analyses: [ApplicationUninstallAnalysis],
        associationCoverage: CoverageSummary = CoverageSummary(),
        ownershipGraph: ApplicationOwnershipGraph? = nil,
        associationIndex: ApplicationAssociationIndex? = nil
    ) {
        self.applicationInventory = applicationInventory
        self.analyses = analyses
        self.associationCoverage = associationCoverage
        self.ownershipGraph = ownershipGraph
        self.associationIndex = associationIndex
    }

    public func analysis(for applicationID: URL) -> ApplicationUninstallAnalysis? {
        let target = applicationID.standardizedFileURL
        return analyses.first { $0.id.standardizedFileURL.path == target.path }
    }

    public var plans: [UninstallPlan] {
        analyses.compactMap(\.plan)
    }

    public func observing(_ observations: [URL: ApplicationRuntimeObservation]) -> Self {
        Self(applicationInventory: applicationInventory, analyses: analyses.map { analysis in
            ApplicationUninstallAnalysis(application: analysis.application, plan: analysis.plan, state: analysis.state,
                message: analysis.message, limitations: analysis.limitations, ownership: analysis.ownership,
                runtimeObservation: observations[analysis.id] ?? analysis.runtimeObservation,
                preparedPlan: analysis.preparedPlan, preparedState: analysis.preparedState, preparedMessage: analysis.preparedMessage)
        }, associationCoverage: associationCoverage, ownershipGraph: ownershipGraph, associationIndex: associationIndex)
    }

    public var moduleCoverage: ApplicationModuleCoverage {
        ApplicationModuleCoverage(inventory: self)
    }
}

public enum ApplicationCoverageState: String, Codable, Hashable, Sendable {
    case complete
    case limited
}

public struct ApplicationModuleCoverage: Codable, Hashable, Sendable {
    public let applicationListState: ApplicationCoverageState
    public let associationAnalysisState: ApplicationCoverageState
    public let summary: String
    public let limitations: [ScanLimitation]

    public init(inventory: ApplicationUninstallInventory) {
        let discovery = inventory.applicationInventory.coverage
        applicationListState = discovery.unavailableRoots.isEmpty
            && !discovery.budgetLimitedModules.contains(.applications) ? .complete : .limited

        let individuallyLimited = inventory.analyses.filter {
            [.limited, .unavailable].contains($0.preparedState ?? $0.state)
        }
        associationAnalysisState = inventory.associationCoverage.unavailableRoots.isEmpty
            && !inventory.associationCoverage.budgetLimitedModules.contains(.applications)
            && individuallyLimited.isEmpty ? .complete : .limited

        var issues = discovery.unavailableRoots.map { root in
            ScanLimitation(
                title: L10n.text("应用目录不可访问"),
                path: root,
                impact: L10n.text("该位置中的应用可能没有出现在应用清单中。"),
                recovery: L10n.text("检查文件权限；若该目录受 macOS 保护，请在系统设置中允许访问。")
            )
        }
        if discovery.budgetLimitedModules.contains(.applications) {
            issues.append(ScanLimitation(
                title: L10n.text("应用清单扫描未完成"),
                impact: L10n.text("达到显式扫描边界，清单可能不完整。"),
                recovery: L10n.text("移除扫描边界后重新扫描。")
            ))
        }
        issues += inventory.associationCoverage.unavailableRoots.map { root in
            ScanLimitation(
                title: L10n.text("关联目录不可访问"),
                path: root,
                impact: L10n.text("卸载计划可能遗漏该位置中的应用关联文件。"),
                recovery: L10n.text("允许访问后重新扫描；当前已发现的应用仍可单独审查。")
            )
        }
        issues += individuallyLimited.flatMap { analysis -> [ScanLimitation] in
            if !analysis.limitations.isEmpty { return analysis.limitations }
            return [ScanLimitation(
                title: analysis.state == .unavailable ? L10n.text("应用无法分析") : L10n.text("应用大小分析不完整"),
                path: analysis.application.bundleURL,
                impact: analysis.message ?? L10n.text("该应用的卸载范围不完整。"),
                recovery: L10n.text("确认应用目录可读并重新扫描。")
            )]
        }
        limitations = issues

        switch (applicationListState, associationAnalysisState) {
        case (.complete, .complete):
            summary = L10n.text("应用清单完成 · 关联分析完成")
        case (.complete, .limited):
            summary = L10n.text("应用清单完成 · 关联分析 {0} 个位置受限", String(describing: issues.count))
        case (.limited, .complete):
            summary = L10n.text("应用清单受限 · 已发现应用的关联分析完成")
        case (.limited, .limited):
            summary = L10n.text("应用清单与关联分析均有受限位置")
        }
    }

    public var isLimited: Bool {
        applicationListState == .limited || associationAnalysisState == .limited
    }
}

public struct ApplicationUninstallAnalyzer: Sendable {
    private let scanner: ApplicationScanner
    private let planner: UninstallPlanner
    private let maximumConcurrentApplications: Int
    private let maximumSizeEntries: Int?

    public init(
        scanner: ApplicationScanner = ApplicationScanner(),
        planner: UninstallPlanner = UninstallPlanner(),
        maximumConcurrentApplications: Int = 4,
        maximumSizeEntries: Int? = nil
    ) {
        self.scanner = scanner
        self.planner = planner
        self.maximumConcurrentApplications = max(1, maximumConcurrentApplications)
        self.maximumSizeEntries = maximumSizeEntries.map { max(0, $0) }
    }

    public func analyze(
        inventory: ApplicationInventory,
        context: ScanContext
    ) async -> ApplicationUninstallInventory {
        let applications = inventory.applications
        // Runtime availability is applied separately; ownership/shared-resource checks remain intact.
        let associationIndex = await scanner.associationIndex(for: applications.map { $0.withRunningState(false) }, context: context)
        return ApplicationUninstallInventory(
            applicationInventory: inventory,
            analyses: await analyze(applications, using: associationIndex, context: context),
            associationCoverage: associationIndex.coverage,
            ownershipGraph: associationIndex.ownershipGraph, associationIndex: associationIndex
        )
    }

    public func analyzeStoppedApplications(
        _ ids: Set<URL>, in applications: [InstalledApplication], context: ScanContext,
        cachedIndex: ApplicationAssociationIndex? = nil
    ) async -> [ApplicationUninstallAnalysis] {
        let targets = applications.filter { ids.contains($0.id) && !$0.isRunning && !$0.isSystem }
        guard !targets.isEmpty else { return [] }
        // Reuse the shared ownership index; a quit must never restart discovery.
        guard let cachedIndex else {
            return targets.map { ApplicationUninstallAnalysis(application: $0, plan: nil, state: .unavailable,
                message: L10n.text("缺少关联扫描结果，请刷新应用列表。")) }
        }
        return await analyze(targets, using: cachedIndex, context: context)
    }

    private func analyze(
        _ applications: [InstalledApplication], using associationIndex: ApplicationAssociationIndex, context: ScanContext
    ) async -> [ApplicationUninstallAnalysis] {
        var analyses: [ApplicationUninstallAnalysis] = []
        for batchStart in stride(from: 0, to: applications.count, by: maximumConcurrentApplications) {
            let batchEnd = min(applications.count, batchStart + maximumConcurrentApplications)
            let batch = Array(applications[batchStart..<batchEnd])
            let batchAnalyses = await withTaskGroup(of: ApplicationUninstallAnalysis.self) { group in
                for application in batch {
                    group.addTask {
                        let associations = associationIndex.associations[application.id, default: []]
                        return await analyze(
                            application,
                            associations: associations,
                            context: context,
                            ownership: associationIndex.ownershipGraph?.application(at: application.id)
                        )
                    }
                }
                var results: [ApplicationUninstallAnalysis] = []
                for await result in group { results.append(result) }
                return results
            }
            analyses.append(contentsOf: batchAnalyses)
        }

        let order = Dictionary(uniqueKeysWithValues: applications.enumerated().map { ($0.element.id, $0.offset) })
        analyses.sort { order[$0.id, default: .max] < order[$1.id, default: .max] }
        return analyses
    }

    private func analyze(
        _ application: InstalledApplication,
        associations: [ApplicationAssociation],
        context: ScanContext,
        ownership: ApplicationOwnershipNode?
    ) async -> ApplicationUninstallAnalysis {
        if application.isSystem {
            return ApplicationUninstallAnalysis(
                application: application,
                plan: nil,
                state: .protected,
                message: L10n.text("这是由 macOS 管理的系统应用，无论是否运行都不会提供卸载操作。"), ownership: ownership
            )
        }

        do {
            let result = try await planner.buildPlan(
                application.withRunningState(false),
                associations: associations,
                context: context,
                maximumSizeEntries: maximumSizeEntries,
                ownership: ownership
            )
            let limited = result.reachedSizeBudget || !result.limitations.isEmpty
            return ApplicationUninstallAnalysis(
                application: application,
                plan: result.plan,
                state: limited ? .limited : .complete,
                message: ownership?.serviceReferences?.isEmpty == false || ownership?.ownershipVerified == false
                    ? ownership?.guidance
                    : ownership?.requiresExternalUninstall == true
                        ? L10n.text("可以单独移除应用本体；安装来源记录和关联内容可能保留。完整卸载可使用原安装工具。")
                        : limited ? L10n.text("应用本体可卸载；部分文件未完整统计，受影响的关联项保持保护。") : nil,
                limitations: result.limitations,
                ownership: ownership
            ).withRunningState(application.isRunning)
        } catch {
            return ApplicationUninstallAnalysis(
                application: application,
                plan: nil,
                state: .unavailable,
                message: L10n.text("无法验证应用本体：{0}", String(describing: ApplicationAnalysisErrorDescription.describe(error))),
                limitations: [ScanLimitation(
                    title: ApplicationAnalysisErrorDescription.describe(error),
                    path: application.bundleURL,
                    impact: L10n.text("应用本体无法验证，因此没有生成卸载计划。"),
                    recovery: L10n.text("确认应用仍在原位置并可读取，然后刷新应用。")
                )], ownership: ownership
            ).withRunningState(application.isRunning)
        }
    }
}

enum ApplicationAnalysisErrorDescription {
    static func describe(_ error: Error) -> String {
        if let failure = error as? FileSystemError {
            switch failure {
            case .missing: return L10n.text("文件已不存在")
            case .invalidAttributes: return L10n.text("无法读取完整文件信息")
            case .unreadableContent: return L10n.text("文件不可读取")
            default: break
            }
        }
        if error is CancellationError { return L10n.text("分析已取消") }
        let failure = error as NSError
        if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
            || (failure.domain == NSPOSIXErrorDomain && [1, 13].contains(failure.code)) {
            return L10n.text("没有读取权限")
        }
        return failure.localizedDescription
    }
}
