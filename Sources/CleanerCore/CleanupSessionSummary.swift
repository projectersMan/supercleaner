import Foundation

public struct CleanupSessionSummary: Equatable, Sendable {
    public private(set) var itemCount: Int
    public private(set) var bytes: UInt64

    public init(itemCount: Int = 0, bytes: UInt64 = 0) {
        self.itemCount = itemCount
        self.bytes = bytes
    }

    public mutating func record(_ receipt: OperationReceipt) {
        let successfulResults = receipt.results.filter(\.countsAsCleanedContent)
        itemCount += successfulResults.count
        bytes += successfulResults.reduce(0) { $0 + $1.bytes }
    }
}

public struct DefaultCleanupFailure: Identifiable, Equatable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public let status: OperationStatus
    public let reason: String
    public let isRetryable: Bool

    public init(
        candidate: CleanupCandidate,
        status: OperationStatus,
        reason: String,
        isRetryable: Bool
    ) {
        self.candidate = candidate
        self.status = status
        self.reason = reason
        self.isRetryable = isRetryable
    }
}

public struct DefaultCleanupModuleResult: Equatable, Sendable {
    public let itemCount: Int
    public let bytes: UInt64

    public init(itemCount: Int, bytes: UInt64) {
        self.itemCount = itemCount
        self.bytes = bytes
    }
}

public struct DefaultCleanupProgress: Equatable, Sendable {
    public private(set) var cleanedCandidateIDs: Set<UUID>
    public private(set) var completedByModule: [ScanModuleID: DefaultCleanupModuleResult]

    public init(
        cleanedCandidateIDs: Set<UUID> = [],
        completedByModule: [ScanModuleID: DefaultCleanupModuleResult] = [:]
    ) {
        self.cleanedCandidateIDs = cleanedCandidateIDs
        self.completedByModule = completedByModule
    }

    public mutating func markChecked(_ modules: Set<ScanModuleID>) {
        for module in modules where completedByModule[module] == nil {
            completedByModule[module] = DefaultCleanupModuleResult(itemCount: 0, bytes: 0)
        }
    }

    public mutating func record(
        outcome: DefaultCleanupAttemptOutcome,
        attemptedCandidates: [CleanupCandidate]
    ) {
        let successfulCandidates = attemptedCandidates.filter {
            outcome.successfulCandidateIDs.contains($0.id)
        }
        cleanedCandidateIDs.formUnion(outcome.successfulCandidateIDs)
        for module in ScanModuleID.allCases {
            let completed = successfulCandidates.filter { $0.defaultCleanupModule == module }
            guard !completed.isEmpty else { continue }
            let previous = completedByModule[module] ?? DefaultCleanupModuleResult(itemCount: 0, bytes: 0)
            completedByModule[module] = DefaultCleanupModuleResult(
                itemCount: previous.itemCount + completed.count,
                bytes: previous.bytes + completed.reduce(0) { $0 + $1.bytes }
            )
        }
    }
}

public struct DefaultCleanupTrackingState: Equatable, Sendable {
    public private(set) var selectedCandidateIDs: Set<UUID>
    public private(set) var uninstallSelectedItemIDs: Set<UUID>
    public private(set) var cleanedCandidateIDs: Set<UUID>
    public private(set) var failures: [DefaultCleanupFailure]

    public init(
        selectedCandidateIDs: Set<UUID>,
        uninstallSelectedItemIDs: Set<UUID>,
        cleanedCandidateIDs: Set<UUID>,
        failures: [DefaultCleanupFailure]
    ) {
        self.selectedCandidateIDs = selectedCandidateIDs
        self.uninstallSelectedItemIDs = uninstallSelectedItemIDs
        self.cleanedCandidateIDs = cleanedCandidateIDs
        self.failures = failures
    }

    public mutating func reconcileSuccessfulAliases(
        outcome: DefaultCleanupAttemptOutcome,
        knownCandidates: [CleanupCandidate]
    ) {
        let successfulPaths = outcome.successfulStandardizedPaths
        let aliasIDs = Set(knownCandidates.compactMap { candidate in
            successfulPaths.contains(candidate.url.standardizedFileURL.path) ? candidate.id : nil
        })
        selectedCandidateIDs.subtract(aliasIDs)
        uninstallSelectedItemIDs.subtract(aliasIDs)
        cleanedCandidateIDs.formUnion(aliasIDs)
        failures.removeAll {
            successfulPaths.contains($0.candidate.url.standardizedFileURL.path)
        }
    }
}

/// Keeps the current scan snapshot useful after cleanup without pretending that
/// failed or skipped items disappeared. A new full scan resets the exclusion set.
public enum CleanupCandidateVisibility {
    public static func remaining(
        candidates: [CleanupCandidate],
        cleanedCandidateIDs: Set<UUID>
    ) -> [CleanupCandidate] {
        candidates.filter { !cleanedCandidateIDs.contains($0.id) }
    }
}

public struct DefaultCleanupAttemptOutcome: Equatable, Sendable {
    public let successfulCandidateIDs: Set<UUID>
    public let successfulStandardizedPaths: Set<String>
    public let failures: [DefaultCleanupFailure]

    public init(attemptedCandidates: [CleanupCandidate], receipt: OperationReceipt) {
        let attemptedByID = Dictionary(
            uniqueKeysWithValues: attemptedCandidates.map { ($0.id, $0) }
        )
        let resultsByID = Dictionary(
            receipt.results.map { ($0.candidateID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let successfulIDs = Set(
            receipt.results.filter(\.countsAsCleanedContent).map(\.candidateID)
        ).intersection(attemptedByID.keys)
        successfulCandidateIDs = successfulIDs
        successfulStandardizedPaths = Set(
            receipt.results.filter(\.countsAsCleanedContent).map {
                $0.originalURL.standardizedFileURL.path
            }
        )
        failures = attemptedCandidates.compactMap { candidate in
            guard !successfulIDs.contains(candidate.id) else { return nil }
            guard let result = resultsByID[candidate.id] else {
                return DefaultCleanupFailure(
                    candidate: candidate,
                    status: .failed,
                    reason: receipt.rejectionReason ?? L10n.text("执行未返回此项目的结果"),
                    isRetryable: false
                )
            }
            return DefaultCleanupFailure(
                candidate: candidate,
                status: result.status,
                reason: result.message ?? result.status.failureDescription,
                isRetryable: result.status.isSafelyRetryable
            )
        }
    }
}

private extension CleanupCandidate {
    var defaultCleanupModule: ScanModuleID {
        switch source {
        case .general: .general
        case .agentWorkspace: .agentEnvironment
        case .diskAnalysis: .largeFiles
        case .application: .applications
        case .projectArtifacts: .general
        }
    }
}

private extension OperationResult {
    var countsAsCleanedContent: Bool {
        status == .succeeded
            && [.quarantined, .trashed, .permanentlyDeleted].contains(disposition)
    }
}

private extension OperationStatus {
    var failureDescription: String {
        switch self {
        case .succeeded: L10n.text("项目已处理")
        case .skippedIdentityChanged: L10n.text("文件身份已变化，请重新扫描")
        case .skippedProtected: L10n.text("路径安全策略拒绝执行")
        case .skippedActive: L10n.text("项目仍在使用")
        case .skippedCancelled: L10n.text("项目尚未开始")
        case .failed: L10n.text("文件操作失败")
        case .restored: L10n.text("项目已恢复")
        case .restoreConflict: L10n.text("恢复目标存在冲突")
        case .sourceMissing: L10n.text("保留内容已不存在")
        }
    }

    var isSafelyRetryable: Bool {
        switch self {
        case .skippedActive, .skippedCancelled, .failed:
            true
        case .succeeded, .skippedIdentityChanged, .skippedProtected, .restored, .restoreConflict, .sourceMissing:
            false
        }
    }
}
