import CleanerCore
import Foundation

func runCleanupSessionSummaryContracts() {
    let cleaned = cleanupOutcomeCandidate(path: "/tmp/cleaned")
    let retryable = cleanupOutcomeCandidate(path: "/tmp/retryable", source: .application)
    let stale = cleanupOutcomeCandidate(path: "/tmp/stale")
    let receipt = OperationReceipt(
        planID: UUID(),
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        results: [
            OperationResult(
                candidateID: cleaned.id,
                originalURL: cleaned.url,
                disposition: .quarantined,
                status: .succeeded,
                bytes: 1_024
            ),
            OperationResult(
                candidateID: retryable.id,
                originalURL: retryable.url,
                disposition: .failed,
                status: .failed,
                bytes: 2_048,
                message: "权限暂时不足"
            ),
            OperationResult(
                candidateID: stale.id,
                originalURL: stale.url,
                disposition: .skipped,
                status: .skippedIdentityChanged,
                bytes: 4_096,
                message: "文件身份已变化"
            ),
        ],
        overallStatus: .partial
    )

    var summary = CleanupSessionSummary()
    summary.record(receipt)
    summary.record(receipt)
    require(summary == CleanupSessionSummary(itemCount: 2, bytes: 2_048), "session cleanup summary must accumulate only successful deletions")

    let outcome = DefaultCleanupAttemptOutcome(
        attemptedCandidates: [cleaned, retryable, stale],
        receipt: receipt
    )
    require(outcome.successfulCandidateIDs == [cleaned.id], "one-click outcome must identify successful candidates")
    require(outcome.failures.map(\.candidate.id) == [retryable.id, stale.id], "failed outcomes must retain their candidates")
    require(outcome.failures.first?.status == .failed, "failed outcomes must retain operation status")
    require(outcome.failures.first?.reason == "权限暂时不足", "failed outcomes must retain per-item reasons")
    require(outcome.failures.first?.isRetryable == true, "transient operation failures must be retryable")
    require(outcome.failures.last?.isRetryable == false, "identity changes must require a fresh scan")

    var progress = DefaultCleanupProgress()
    progress.markChecked([.general, .applications])
    progress.record(outcome: outcome, attemptedCandidates: [cleaned, retryable, stale])
    require(progress.cleanedCandidateIDs == [cleaned.id], "initial default cleanup must remember successful candidate IDs")
    require(
        progress.completedByModule[.general] == DefaultCleanupModuleResult(itemCount: 1, bytes: cleaned.bytes),
        "initial default cleanup must update the owning module statistics"
    )
    require(
        progress.completedByModule[.applications] == DefaultCleanupModuleResult(itemCount: 0, bytes: 0),
        "checked modules without cleaned items must retain a zero result"
    )

    let retryReceipt = OperationReceipt(
        planID: UUID(),
        startedAt: Date(timeIntervalSince1970: 3),
        completedAt: Date(timeIntervalSince1970: 4),
        results: [
            OperationResult(
                candidateID: retryable.id,
                originalURL: retryable.url,
                disposition: .quarantined,
                status: .succeeded,
                bytes: retryable.bytes
            ),
        ],
        overallStatus: .completed
    )
    let retryOutcome = DefaultCleanupAttemptOutcome(
        attemptedCandidates: [retryable],
        receipt: retryReceipt
    )
    progress.record(outcome: retryOutcome, attemptedCandidates: [retryable])
    require(
        progress.cleanedCandidateIDs == Set([cleaned.id, retryable.id]),
        "successful retry must add its candidate to the cleaned-ID exclusion set"
    )
    require(
        progress.completedByModule[.general] == DefaultCleanupModuleResult(itemCount: 1, bytes: cleaned.bytes),
        "successful retry must not alter another module's statistics"
    )
    require(
        progress.completedByModule[.applications] == DefaultCleanupModuleResult(itemCount: 1, bytes: retryable.bytes),
        "successful retry must update its owning module statistics"
    )

    let aliasPath = "/tmp/shared-cache"
    let generalAlias = cleanupOutcomeCandidate(path: aliasPath)
    let applicationAlias = cleanupOutcomeCandidate(path: "/tmp/./shared-cache", source: .application)
    let agentAlias = cleanupOutcomeCandidate(path: "/tmp/folder/../shared-cache", source: .agentWorkspace)
    let aliasReceipt = OperationReceipt(
        planID: UUID(),
        startedAt: Date(timeIntervalSince1970: 5),
        completedAt: Date(timeIntervalSince1970: 6),
        results: [
            OperationResult(
                candidateID: generalAlias.id,
                originalURL: generalAlias.url,
                disposition: .quarantined,
                status: .succeeded,
                bytes: generalAlias.bytes
            ),
        ]
    )
    let aliasOutcome = DefaultCleanupAttemptOutcome(
        attemptedCandidates: [generalAlias],
        receipt: aliasReceipt
    )
    var tracking = DefaultCleanupTrackingState(
        selectedCandidateIDs: [generalAlias.id, agentAlias.id],
        uninstallSelectedItemIDs: [applicationAlias.id],
        cleanedCandidateIDs: [],
        failures: [
            DefaultCleanupFailure(
                candidate: applicationAlias,
                status: .failed,
                reason: "旧别名失败",
                isRetryable: true
            ),
        ]
    )
    tracking.reconcileSuccessfulAliases(
        outcome: aliasOutcome,
        knownCandidates: [generalAlias, applicationAlias, agentAlias]
    )
    require(tracking.selectedCandidateIDs.isEmpty, "successful cleanup must clear every selected alias by standardized path")
    require(tracking.uninstallSelectedItemIDs.isEmpty, "successful cleanup must clear uninstall aliases with different UUIDs")
    require(
        tracking.cleanedCandidateIDs == Set([generalAlias.id, applicationAlias.id, agentAlias.id]),
        "successful cleanup must exclude every module alias from the default queue"
    )
    require(tracking.failures.isEmpty, "successful cleanup must clear stale failures for every path alias")
    let failedCandidate = cleanupOutcomeCandidate(path: "/tmp/still-pending")
    let remaining = CleanupCandidateVisibility.remaining(
        candidates: [generalAlias, applicationAlias, agentAlias, failedCandidate],
        cleanedCandidateIDs: tracking.cleanedCandidateIDs
    )
    require(
        remaining.map(\.id) == [failedCandidate.id],
        "manual selection must hide every successfully cleaned alias while retaining pending items"
    )
}

private func cleanupOutcomeCandidate(
    path: String,
    source: CandidateSource = .general
) -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: path),
        displayName: URL(fileURLWithPath: path).lastPathComponent,
        category: .cache,
        bytes: 1_024,
        risk: .safe,
        evidence: [],
        identity: FileIdentity(
            device: 1,
            inode: UInt64(path.utf8.reduce(0) { $0 + UInt64($1) }),
            size: 1_024,
            modificationTime: 1,
            kind: .file
        ),
        source: source,
        lastAccessDate: nil,
        isActive: false
    )
}
