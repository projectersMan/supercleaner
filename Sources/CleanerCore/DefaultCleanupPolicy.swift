import Foundation

public struct DefaultCleanupSelection: Sendable, Equatable {
    public let systemCleanup: [CleanupCandidate]
    public let applicationUninstall: [CleanupCandidate]
    public let largeFiles: [CleanupCandidate]
    public let agentEnvironment: [CleanupCandidate]

    public init(
        systemCleanup: [CleanupCandidate],
        applicationUninstall: [CleanupCandidate],
        largeFiles: [CleanupCandidate],
        agentEnvironment: [CleanupCandidate]
    ) {
        self.systemCleanup = systemCleanup
        self.applicationUninstall = applicationUninstall
        self.largeFiles = largeFiles
        self.agentEnvironment = agentEnvironment
    }

    public var candidates: [CleanupCandidate] {
        var seenPaths = Set<String>()
        return (systemCleanup + applicationUninstall + largeFiles + agentEnvironment)
            .filter { seenPaths.insert($0.url.standardizedFileURL.path).inserted }
    }

    public var bytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }
}

public struct DefaultCleanupPolicy: Sendable {
    private let recommendationPolicy = CleanupRecommendationPolicy()
    private let scopePolicy = CleanupScopePolicy()

    public init() {}

    public func selection(for report: SystemScanReport) -> DefaultCleanupSelection {
        let scopedCandidates = scopePolicy.cleanupCenterCandidates(from: report.candidates)
        let defaultSelectedIDs = recommendationPolicy.defaultSelectedIDs(for: scopedCandidates)
        let systemCleanup = scopedCandidates.filter { defaultSelectedIDs.contains($0.id) }
        return DefaultCleanupSelection(
            systemCleanup: systemCleanup,
            applicationUninstall: [],
            largeFiles: report.largeFileCandidates.filter(\.isLargeFilePreselected),
            agentEnvironment: []
        )
    }
}
