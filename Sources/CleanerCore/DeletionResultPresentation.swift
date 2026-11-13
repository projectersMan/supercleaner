import Foundation

/// Keep the result sheet's totals, row labels and recovery guidance consistent.
public struct DeletionResultPresentation: Sendable {
    public enum Outcome: Equatable, Sendable { case deleted, skipped, failed }

    public let deletedCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let recoveryMessages: [String]
    public var incompleteCount: Int { skippedCount + failedCount }
    public var isComplete: Bool { incompleteCount == 0 }

    public init(receipt: OperationReceipt) {
        self.init(results: receipt.displayResults, recoveryResults: receipt.results)
    }

    public init(results: [OperationResult], recoveryResults: [OperationResult]? = nil) {
        var deleted = 0, skipped = 0, failed = 0
        for result in results {
            switch Self.outcome(for: result) {
            case .deleted: deleted += 1
            case .skipped: skipped += 1
            case .failed: failed += 1
            }
        }
        deletedCount = deleted
        skippedCount = skipped
        failedCount = failed

        let completed = Set((recoveryResults ?? results).filter(\.countsAsCleanedContent).map(\.disposition))
        var messages: [String] = []
        if completed.contains(.quarantined) {
            messages.append(L10n.text("已删除项目可在保留期内从恢复记录找回；保留期间仍占用磁盘空间。"))
        }
        if completed.contains(.trashed) {
            messages.append(L10n.text("已移入系统废纸篓，可在清空前恢复；清空废纸篓后才会释放空间。"))
        }
        if completed.contains(.permanentlyDeleted) {
            messages.append(L10n.text("已彻底删除的项目无法恢复。"))
        }
        recoveryMessages = messages
    }

    public static func outcome(for result: OperationResult) -> Outcome {
        switch result.disposition {
        case .quarantined, .trashed, .permanentlyDeleted:
            result.countsAsCleanedContent ? .deleted : .failed
        case .skipped, .unavailable:
            .skipped
        case .restored:
            [.succeeded, .restored, .restoreConflict].contains(result.status) ? .skipped : .failed
        case .failed:
            .failed
        }
    }

    public static func statusTitle(for result: OperationResult) -> String {
        guard outcome(for: result) != .failed else { return L10n.text("失败") }
        switch result.disposition {
        case .quarantined: return L10n.text("已移入恢复区")
        case .trashed: return L10n.text("已移入系统废纸篓")
        case .permanentlyDeleted: return L10n.text("已彻底删除")
        case .skipped: return L10n.text("已跳过")
        case .unavailable: return L10n.text("保留内容已不存在")
        case .restored: return L10n.text("已恢复")
        case .failed: return L10n.text("失败")
        }
    }
}
