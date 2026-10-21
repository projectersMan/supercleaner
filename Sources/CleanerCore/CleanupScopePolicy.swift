public struct CleanupScopePolicy: Sendable {
    public init() {}

    public func cleanupCenterCandidates(from candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        candidates.filter {
            ($0.source == .general || $0.source == .historicalApplicationResidue) && $0.category != .largeFile
        }
    }

    public func candidates(for destination: AppDestination, from candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        switch destination {
        case .systemCleanup: cleanupCenterCandidates(from: candidates)
        case .largeFiles: candidates.filter { $0.category == .largeFile }
        case .agentEnvironment: candidates.filter { $0.source == .agentWorkspace }
        default: candidates
        }
    }
}
