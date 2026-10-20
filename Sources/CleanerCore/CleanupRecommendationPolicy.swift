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
    private static let deepCleanCategories: Set<CleanupCategory> = [
        .cache,
        .log,
        .temporaryFile,
        .installerArtifact,
        .developerCache,
        .agentModelCache,
        .agentPackageCache,
    ]

    public init() {}

    public func disposition(for candidate: CleanupCandidate) -> CleanupDisposition {
        if candidate.risk == .blocked { return .protected }
        if candidate.isActive { return .retain }
        if candidate.risk == .safe { return .recommended }
        if candidate.defaultSelection == false && !Self.deepCleanCategories.contains(candidate.category) {
            return .retain
        }
        if Self.deepCleanCategories.contains(candidate.category) { return .deepClean }
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
        case .smart:
            return Set(candidates.filter { disposition(for: $0) == .recommended }.map(\.id))
        case .deep:
            return Set(candidates.filter { [.recommended, .deepClean].contains(disposition(for: $0)) }.map(\.id))
        case .custom:
            let selectableIDs = Set(candidates.filter { $0.risk.isSelectable }.map(\.id))
            return currentSelection.intersection(selectableIDs)
        }
    }
}
