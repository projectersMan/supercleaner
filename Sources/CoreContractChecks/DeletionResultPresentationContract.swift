import CleanerCore
import Foundation

func runDeletionResultPresentationContracts() {
    func result(_ disposition: OperationDisposition, _ status: OperationStatus = .succeeded) -> OperationResult {
        OperationResult(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/tmp/cache"),
            disposition: disposition, status: status, bytes: 1_024)
    }

    let trashed = (0..<36).map { _ in result(.trashed) }
    let immediate = DeletionResultPresentation(results: trashed)
    require(immediate.deletedCount == 36 && immediate.skippedCount == 0 && immediate.failedCount == 0,
        "36 successful Trash moves must display 36 deleted, zero skipped and zero failures")
    require(trashed.allSatisfy {
        DeletionResultPresentation.outcome(for: $0) == .deleted
            && DeletionResultPresentation.statusTitle(for: $0) == L10n.text("已移入系统废纸篓")
    }, "successful Trash rows must display a successful Trash status instead of Failed")
    require(immediate.recoveryMessages == [L10n.text("已移入系统废纸篓，可在清空前恢复；清空废纸篓后才会释放空间。")],
        "immediate deletion must explain Trash recovery and space usage, not app retention")

    let quarantined = result(.quarantined)
    let permanentlyDeleted = result(.permanentlyDeleted)
    let skipped = result(.skipped, .skippedProtected)
    let cancelled = result(.skipped, .skippedCancelled)
    let missing = result(.unavailable, .sourceMissing)
    let restored = result(.restored, .restoreConflict)
    let failed = result(.failed, .failed)
    let mixedResults = [quarantined, trashed[0], permanentlyDeleted, skipped, cancelled, missing, restored, failed]
    let mixed = DeletionResultPresentation(results: mixedResults)
    require(mixed.deletedCount == 3 && mixed.skippedCount == 4 && mixed.failedCount == 1,
        "mixed batches must count every row once, counting all three successful deletion destinations")
    require(mixed.recoveryMessages.count == 3, "mixed deletion destinations must each retain accurate recovery guidance")
    require(DeletionResultPresentation.statusTitle(for: quarantined) == L10n.text("已移入恢复区"), "quarantine must identify Recovery separately from Trash")
    require(DeletionResultPresentation.statusTitle(for: permanentlyDeleted) == L10n.text("已彻底删除"), "permanent deletion must remain successful")
    require(DeletionResultPresentation.statusTitle(for: skipped) == L10n.text("已跳过"), "protected items must remain skipped")
    require(DeletionResultPresentation.statusTitle(for: cancelled) == L10n.text("已跳过"), "cancelled items must remain skipped")
    require(DeletionResultPresentation.statusTitle(for: missing) == L10n.text("保留内容已不存在"), "missing content must not claim a deletion")
    require(DeletionResultPresentation.statusTitle(for: restored) == L10n.text("已恢复"), "restored content must not count as deleted")
    require(DeletionResultPresentation.statusTitle(for: failed) == L10n.text("失败"), "real failures must remain visible")

    for disposition in [OperationDisposition.quarantined, .trashed, .permanentlyDeleted] {
        let uncertain = result(disposition, .failed)
        let presentation = DeletionResultPresentation(results: [uncertain])
        require(presentation.deletedCount == 0 && presentation.failedCount == 1 && presentation.recoveryMessages.isEmpty,
            "an unverified move or deletion must never be presented as successful")
        require(DeletionResultPresentation.statusTitle(for: uncertain) == L10n.text("失败"),
            "failed verification must override a nominal success disposition")
    }
    let empty = DeletionResultPresentation(results: [])
    require(empty.deletedCount == 0 && empty.skippedCount == 0 && empty.failedCount == 0 && empty.recoveryMessages.isEmpty,
        "an empty result must not claim deletion or recoverable files")
    print("PASS: deletion result totals, successful Trash rows, mixed destinations, skips and verification failures")
}
