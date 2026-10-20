import Foundation

public struct UninstallBatchSummary: Equatable, Sendable {
    public let applicationCount: Int
    public let itemCount: Int
    public let bytes: UInt64

    public init(applicationCount: Int, itemCount: Int, bytes: UInt64) {
        self.applicationCount = applicationCount
        self.itemCount = itemCount
        self.bytes = bytes
    }
}

public struct UninstallBatchSelectionState: Codable, Hashable, Sendable {
    public private(set) var selectedItemIDs: Set<UUID>

    public init(selectedItemIDs: Set<UUID> = []) {
        self.selectedItemIDs = selectedItemIDs
    }

    public func selectionState(for plan: UninstallPlan) -> SelectionTriState {
        let selectable = plan.selectableItemIDs
        guard !selectable.isEmpty else { return .none }
        let count = selectedItemIDs.intersection(selectable).count
        if count == 0 { return .none }
        return count == selectable.count ? .all : .partial
    }

    public mutating func toggle(plan: UninstallPlan) {
        let selectable = plan.selectableItemIDs
        guard !selectable.isEmpty else { return }
        if selectionState(for: plan) == .all {
            selectedItemIDs.subtract(selectable)
        } else {
            selectedItemIDs.formUnion(selectable)
        }
    }

    public mutating func toggle(item: UninstallItem) {
        guard Self.isSelectable(item) else { return }
        if selectedItemIDs.remove(item.id) == nil {
            selectedItemIDs.insert(item.id)
        }
    }

    public mutating func reconcile(plans: [UninstallPlan]) {
        let validIDs = Set(plans.flatMap(\.items).filter(Self.isSelectable).map(\.id))
        selectedItemIDs.formIntersection(validIDs)
    }

    public func selectedItems(in plans: [UninstallPlan]) -> [UninstallItem] {
        var seenPaths = Set<String>()
        return plans
            .flatMap(\.items)
            .filter { item in
                selectedItemIDs.contains(item.id)
                    && Self.isSelectable(item)
                    && seenPaths.insert(item.candidate.url.standardizedFileURL.path).inserted
            }
            .sorted { $0.candidate.url.path.localizedStandardCompare($1.candidate.url.path) == .orderedAscending }
    }

    public func summary(plans: [UninstallPlan]) -> UninstallBatchSummary {
        let items = selectedItems(in: plans)
        let applicationCount = plans.filter { plan in
            !selectedItemIDs.intersection(Set(plan.items.map(\.id))).isEmpty
        }.count
        return UninstallBatchSummary(
            applicationCount: applicationCount,
            itemCount: items.count,
            bytes: items.reduce(0) { $0 + $1.candidate.bytes }
        )
    }

    private static func isSelectable(_ item: UninstallItem) -> Bool {
        item.candidate.risk.isSelectable
            && !item.candidate.isActive
            && !item.isShared
    }
}
