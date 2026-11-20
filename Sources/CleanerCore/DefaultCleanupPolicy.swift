import Foundation

public struct DefaultCleanupSelection: Sendable, Equatable {
    public let systemCleanup: [CleanupCandidate]
    public let applicationUninstall: [CleanupCandidate]
    public let largeFiles: [CleanupCandidate]
    public let agentEnvironment: [CleanupCandidate]
    public let localAIModels: [CleanupCandidate]
    public let projects: [CleanupCandidate]

    public init(
        systemCleanup: [CleanupCandidate],
        applicationUninstall: [CleanupCandidate],
        largeFiles: [CleanupCandidate],
        agentEnvironment: [CleanupCandidate],
        localAIModels: [CleanupCandidate],
        projects: [CleanupCandidate]
    ) {
        self.systemCleanup = systemCleanup
        self.applicationUninstall = applicationUninstall
        self.largeFiles = largeFiles
        self.agentEnvironment = agentEnvironment
        self.localAIModels = localAIModels
        self.projects = projects
    }

    public var candidates: [CleanupCandidate] {
        CleanupSelection.executionCandidates(from: systemCleanup + applicationUninstall + largeFiles + agentEnvironment + localAIModels + projects)
    }

    public func candidates(for module: ScanModuleID) -> [CleanupCandidate] {
        let items: [CleanupCandidate] = switch module {
        case .general: systemCleanup
        case .applications: applicationUninstall
        case .largeFiles: largeFiles
        case .agentEnvironment: agentEnvironment
        case .localAIModels: localAIModels
        case .projects: projects
        }
        let ids = Set(items.map(\.id))
        return candidates.filter { ids.contains($0.id) }
    }

    public var bytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }

    public func buildPlan(using builder: PlanBuilder) throws -> CleanupPlan {
        // Keep aliases and covered children until all protection and copy proofs
        // have been validated. PlanBuilder consolidates execution only afterward.
        let items = systemCleanup + applicationUninstall + largeFiles + agentEnvironment + localAIModels + projects
        return try builder.build(candidates: items, selectedIDs: Set(items.map(\.id)))
    }
}

public struct DefaultCleanupPolicy: Sendable {
    private let recommendationPolicy = CleanupRecommendationPolicy()
    private let scopePolicy = CleanupScopePolicy()
    private let preselectProjectArtifacts: Bool

    public init(preselectProjectArtifacts: Bool = false) {
        self.preselectProjectArtifacts = preselectProjectArtifacts
    }

    public func selection(
        for report: SystemScanReport,
        selectedIDs: Set<UUID>,
        automaticallySelectedAgentIDs: Set<UUID>
    ) -> DefaultCleanupSelection {
        let proposed = selection(for: report)
        return DefaultCleanupSelection(
            systemCleanup: proposed.systemCleanup.filter { selectedIDs.contains($0.id) },
            applicationUninstall: [],
            largeFiles: proposed.largeFiles.filter { selectedIDs.contains($0.id) },
            agentEnvironment: report.agentAssets.map(\.candidate).filter {
                selectedIDs.contains($0.id) && automaticallySelectedAgentIDs.contains($0.id)
                    && $0.risk.isSelectable && !$0.isActive && $0.requiresExplicitSelection != true
            },
            localAIModels: [],
            projects: proposed.projects.filter { selectedIDs.contains($0.id) })
    }

    public func selection(for report: SystemScanReport) -> DefaultCleanupSelection {
        let scopedCandidates = scopePolicy.cleanupCenterCandidates(from: report.candidates)
        let defaultSelectedIDs = recommendationPolicy.defaultSelectedIDs(for: scopedCandidates)
        let systemCleanup = scopedCandidates.filter { defaultSelectedIDs.contains($0.id) }
        return DefaultCleanupSelection(
            systemCleanup: systemCleanup,
            applicationUninstall: [],
            largeFiles: report.largeFileReviewCandidates.filter(\.isLargeFilePreselected),
            agentEnvironment: [],
            localAIModels: [],
            projects: preselectProjectArtifacts
                ? ResourceCleanupListPolicy.selectableCandidates(ResourceCleanupListPolicy.projectReviewCandidates(
                    scopePolicy.candidates(for: .projects, from: report.candidates))) : []
        )
    }
}
