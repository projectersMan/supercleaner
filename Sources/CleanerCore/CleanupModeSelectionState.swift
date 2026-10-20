import Foundation

public struct CleanupModeSelectionState: Codable, Hashable, Sendable {
    public let mode: CleanupMode
    public let selectedIDs: Set<UUID>

    public init(mode: CleanupMode = .defaultMode, selectedIDs: Set<UUID> = []) {
        self.mode = mode
        self.selectedIDs = selectedIDs
    }

    public func applying(
        _ mode: CleanupMode,
        to candidates: [CleanupCandidate],
        policy: CleanupRecommendationPolicy = CleanupRecommendationPolicy()
    ) -> CleanupModeSelectionState {
        let scopedCandidateIDs = Set(candidates.map(\.id))
        let preservedSelection = selectedIDs.subtracting(scopedCandidateIDs)
        let scopedSelection = policy.selectedIDs(
            for: candidates,
            mode: mode,
            currentSelection: selectedIDs.intersection(scopedCandidateIDs)
        )
        return CleanupModeSelectionState(
            mode: mode,
            selectedIDs: preservedSelection.union(scopedSelection)
        )
    }

    public func removing(_ candidates: [CleanupCandidate]) -> CleanupModeSelectionState {
        CleanupModeSelectionState(
            mode: mode,
            selectedIDs: selectedIDs.subtracting(candidates.map(\.id))
        )
    }
}

public extension CleanupMode {
    static let defaultMode: CleanupMode = .deep
    static let userFacingCases: [CleanupMode] = [.deep, .custom]

    var displayTitle: String {
        switch self {
        case .smart: L10n.text("推荐")
        case .deep: L10n.text("自动清理")
        case .custom: L10n.text("手动选择")
        }
    }
}
