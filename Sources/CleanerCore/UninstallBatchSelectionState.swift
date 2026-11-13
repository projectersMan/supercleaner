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

    public func selectionState(for plan: UninstallPlan, receipts: [URL] = [],
                               receiptSelection: PackageReceiptCleanupSelection = .init()) -> SelectionTriState {
        guard !plan.application.isUninstallProtected else { return .none }
        let selectable = plan.selectableItemIDs
        let packageIDs = Set(receipts.compactMap(PackageReceiptCleanupSelection.packageID))
        let total = selectable.count + packageIDs.count
        guard total > 0 else { return .none }
        let count = selectedItemIDs.intersection(selectable).count
            + packageIDs.filter { receiptSelection.isSelected($0) }.count
        if count == 0 { return .none }
        return count == total ? .all : .partial
    }

    public mutating func toggle(plan: UninstallPlan) {
        setSelected(selectionState(for: plan) != .all, plan: plan)
    }

    /// A parent checkbox controls every displayed child, including receipt
    /// options. Receipt files remain outside the generic file deletion plan.
    public mutating func toggle(plan: UninstallPlan, receipts: [URL],
                                receiptSelection: inout PackageReceiptCleanupSelection) {
        guard !plan.application.isUninstallProtected else { return }
        let selected = selectionState(for: plan, receipts: receipts, receiptSelection: receiptSelection) != .all
        setSelected(selected, plan: plan)
        for packageID in Set(receipts.compactMap(PackageReceiptCleanupSelection.packageID)) {
            receiptSelection.setSelected(selected, packageID: packageID)
        }
    }

    private mutating func setSelected(_ selected: Bool, plan: UninstallPlan) {
        let selectable = plan.selectableItemIDs
        if selected {
            selectedItemIDs.formUnion(selectable)
        } else {
            selectedItemIDs.subtract(selectable)
        }
    }

    public mutating func toggle(item: UninstallItem) {
        guard Self.isSelectable(item) else { return }
        if selectedItemIDs.remove(item.id) == nil {
            selectedItemIDs.insert(item.id)
        }
    }

    public mutating func reconcile(plans: [UninstallPlan]) {
        let validIDs = Set(plans.filter { !$0.application.isUninstallProtected }.flatMap(\.items).filter(Self.isSelectable).map(\.id))
        selectedItemIDs.formIntersection(validIDs)
    }

    public func selectedItems(in plans: [UninstallPlan]) -> [UninstallItem] {
        var seenPaths = Set<String>()
        return plans
            .filter { !$0.application.isUninstallProtected }
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
        let operations = CleanupSelection.executionCandidates(from: items.map(\.candidate))
        let applicationCount = plans.filter { plan in
            !selectedItemIDs.intersection(plan.selectableItemIDs).isEmpty
        }.count
        return UninstallBatchSummary(
            applicationCount: applicationCount,
            itemCount: operations.count,
            bytes: operations.reduce(0) { $0 + $1.bytes }
        )
    }

    private static func isSelectable(_ item: UninstallItem) -> Bool {
        item.candidate.risk.isSelectable
            && !item.candidate.isActive
            && !item.isShared
    }
}
