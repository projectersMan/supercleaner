import Foundation

public enum SelectionTriState: String, Codable, Hashable, Sendable {
    case none
    case partial
    case all
}

public struct CleanupStrategySelectionState: Codable, Hashable, Sendable {
    public let strategy: CleanupMode
    public let generationID: UUID
    public private(set) var selectedIDs: Set<UUID>
    public private(set) var excludedBaseIDs: Set<UUID>

    public var isAdjusted: Bool { !excludedBaseIDs.isEmpty }

    public init(
        strategy: CleanupMode,
        generationID: UUID,
        selectedIDs: Set<UUID>,
        excludedBaseIDs: Set<UUID>
    ) {
        self.strategy = strategy
        self.generationID = generationID
        self.selectedIDs = selectedIDs
        self.excludedBaseIDs = excludedBaseIDs
    }

    public mutating func toggle(_ candidate: CleanupCandidate, baseEligibleIDs: Set<UUID>) {
        guard candidate.risk.isSelectable else { return }
        if selectedIDs.remove(candidate.id) != nil {
            if baseEligibleIDs.contains(candidate.id) { excludedBaseIDs.insert(candidate.id) }
        } else {
            selectedIDs.insert(candidate.id)
            excludedBaseIDs.remove(candidate.id)
        }
    }

    public func selectionState(for eligibleIDs: Set<UUID>) -> SelectionTriState {
        guard !eligibleIDs.isEmpty else { return .none }
        let selectedCount = selectedIDs.intersection(eligibleIDs).count
        if selectedCount == 0 { return .none }
        return selectedCount == eligibleIDs.count ? .all : .partial
    }

    public mutating func toggleCategory(
        candidates: [CleanupCandidate],
        baseEligibleIDs: Set<UUID>
    ) {
        let selectableIDs = Set(candidates.filter { $0.risk.isSelectable }.map(\.id))
        guard !selectableIDs.isEmpty else { return }
        if selectionState(for: selectableIDs) == .all {
            selectedIDs.subtract(selectableIDs)
            excludedBaseIDs.formUnion(selectableIDs.intersection(baseEligibleIDs))
        } else {
            selectedIDs.formUnion(selectableIDs)
            excludedBaseIDs.subtract(selectableIDs)
        }
    }
}
