import Foundation

public enum CleanupDisposition: String, Codable, Hashable, Sendable, CaseIterable {
    case recommended
    case deepClean
    case retain
    case protected
}

public enum CleanupMode: String, Codable, Hashable, Sendable, CaseIterable {
    case smart
    case deep
    case custom
}

public struct CleanupRecommendationBreakdown: Equatable, Sendable {
    public let recommended: [CleanupCandidate]
    public let deepClean: [CleanupCandidate]
    public let retained: [CleanupCandidate]
    public let protected: [CleanupCandidate]

    public var recommendedGroupCandidates: [CleanupCandidate] { recommended + deepClean }
    public var deepReviewCandidates: [CleanupCandidate] { retained + protected }

    public init(
        recommended: [CleanupCandidate],
        deepClean: [CleanupCandidate],
        retained: [CleanupCandidate],
        protected: [CleanupCandidate]
    ) {
        self.recommended = recommended
        self.deepClean = deepClean
        self.retained = retained
        self.protected = protected
    }
}

public struct CleanupRecommendationPolicy: Sendable {
    public init() {}

    public func disposition(for candidate: CleanupCandidate) -> CleanupDisposition {
        if candidate.risk == .blocked || candidate.hasIncompleteScan || candidate.category == .credential { return .protected }
        if candidate.requiresExplicitSelection == true { return .retain }
        if candidate.source == .historicalApplicationResidue
            || [.applicationSupport, .configuration, .userKnowledge].contains(candidate.category) { return .retain }
        if candidate.isActive && !candidate.isDisposableRuntimeCache { return .retain }
        // Keep low-impact and regeneration evidence distinct inside the merged
        // recommended group so cleanup costs remain explainable.
        if candidate.risk == .safe && candidate.defaultSelection == true { return .recommended }
        if candidate.isDisposableRuntimeCache { return .deepClean }
        return .retain
    }

    public func breakdown(for candidates: [CleanupCandidate]) -> CleanupRecommendationBreakdown {
        var recommended: [CleanupCandidate] = []
        var deepClean: [CleanupCandidate] = []
        var retained: [CleanupCandidate] = []
        var protected: [CleanupCandidate] = []

        for candidate in candidates {
            switch disposition(for: candidate) {
            case .recommended: recommended.append(candidate)
            case .deepClean: deepClean.append(candidate)
            case .retain: retained.append(candidate)
            case .protected: protected.append(candidate)
            }
        }
        return CleanupRecommendationBreakdown(
            recommended: recommended,
            deepClean: deepClean,
            retained: retained,
            protected: protected
        )
    }

    public func selectedIDs(
        for candidates: [CleanupCandidate],
        mode: CleanupMode,
        currentSelection: Set<UUID>
    ) -> Set<UUID> {
        switch mode {
        case .smart, .deep:
            return defaultSelectedIDs(for: candidates)
        case .custom:
            let selectableIDs = Set(candidates.filter { $0.risk.isSelectable }.map(\.id))
            return currentSelection.intersection(selectableIDs)
        }
    }

    /// The recommended group includes verified regenerable caches.
    public func defaultSelectedIDs(for candidates: [CleanupCandidate]) -> Set<UUID> {
        Set(breakdown(for: candidates).recommendedGroupCandidates.filter(\.risk.isSelectable).map(\.id))
    }
}
