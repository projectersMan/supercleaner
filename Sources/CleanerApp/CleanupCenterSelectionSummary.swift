import CleanerCore
import Foundation

struct CleanupCenterSelectionSummary: Equatable {
    enum Kind { case recommended, manual, mixed }

    let kind: Kind
    let metrics: DefaultCleanupModuleResult

    var title: String {
        let count = String(metrics.itemCount)
        let size = ByteCountFormatter.cleanerString(bytes: metrics.bytes)
        switch kind {
        case .recommended: return L10n.text("推荐清理：{0} 项 · {1}", count, size)
        case .manual: return L10n.text("手动已选：{0} 项 · {1}", count, size)
        case .mixed: return L10n.text("当前已选：{0} 项 · {1}", count, size)
        }
    }
}

extension AppModel {
    func cleanupCenterSelectionSummary(for module: ScanModuleID) -> CleanupCenterSelectionSummary? {
        guard hasScanResult(for: module) else { return nil }
        if module == .applications {
            let summary = uninstallBatchSummary
            guard summary.itemCount > 0 else { return nil }
            return CleanupCenterSelectionSummary(kind: .manual,
                metrics: .init(itemCount: summary.itemCount, bytes: summary.bytes))
        }
        let destination = module.cleanupDestination
        let operations = executionSelectionCandidates(for: destination)
        guard !operations.isEmpty else { return nil }
        let selected = Set(operations.map(\.id))
        let recommended = Set(defaultCleanupSelection?.candidates(for: module).map(\.id) ?? [])
        let kind: CleanupCenterSelectionSummary.Kind = selected.isSubset(of: recommended) ? .recommended
            : selected.isDisjoint(with: recommended) ? .manual : .mixed
        let count = module == .localAIModels ? selectedCandidates(for: destination).count : operations.count
        return CleanupCenterSelectionSummary(kind: kind,
            metrics: .init(itemCount: count, bytes: operations.reduce(0) { $0 + $1.bytes }))
    }
}

private extension ScanModuleID {
    var cleanupDestination: AppDestination {
        switch self {
        case .general: .systemCleanup
        case .applications: .applications
        case .largeFiles: .largeFiles
        case .agentEnvironment: .agentEnvironment
        case .localAIModels: .localAIModels
        case .projects: .projects
        }
    }
}
