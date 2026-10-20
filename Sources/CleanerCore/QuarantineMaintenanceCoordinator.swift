import Foundation

public enum QuarantineMaintenanceError: Error, Sendable {
    case receiptNotFound
    case noQuarantinedContent
}

public struct QuarantineMaintenanceResult: Equatable, Sendable {
    public let processedScheduleCount: Int
    public let deletedItemCount: Int
    public let trashedItemCount: Int
    public let releasedBytes: UInt64
    public let failedItemCount: Int
    public let unavailableItemCount: Int

    public init(
        processedScheduleCount: Int = 0,
        deletedItemCount: Int = 0,
        trashedItemCount: Int = 0,
        releasedBytes: UInt64 = 0,
        failedItemCount: Int = 0,
        unavailableItemCount: Int = 0
    ) {
        self.processedScheduleCount = processedScheduleCount
        self.deletedItemCount = deletedItemCount
        self.trashedItemCount = trashedItemCount
        self.releasedBytes = releasedBytes
        self.failedItemCount = failedItemCount
        self.unavailableItemCount = unavailableItemCount
    }
}

public actor QuarantineMaintenanceCoordinator {
    private let historyStore: HistoryStore
    private let scheduleStore: QuarantineScheduleStore
    private let executor: CleanupExecutor
    private let resolutionJournalStore: ResolutionJournalStore
    private let lifecycleGate = ReceiptLifecycleGate.shared

    public init(
        historyStore: HistoryStore,
        scheduleStore: QuarantineScheduleStore,
        executor: CleanupExecutor,
        resolutionJournalStore: ResolutionJournalStore
    ) {
        self.historyStore = historyStore
        self.scheduleStore = scheduleStore
        self.executor = executor
        self.resolutionJournalStore = resolutionJournalStore
    }

    public func register(
        receipt: OperationReceipt,
        policy: QuarantineRetentionPolicy,
        at date: Date
    ) async throws {
        guard receipt.hasQuarantinedContent else {
            try await scheduleStore.remove(receiptID: receipt.id)
            return
        }
        try await scheduleStore.upsert(QuarantineSchedule(
            receiptID: receipt.id,
            policy: policy,
            scheduledAt: date
        ))
    }

    @discardableResult
    public func migrateUnscheduled(
        receipts: [OperationReceipt],
        policy: QuarantineRetentionPolicy,
        at date: Date
    ) async throws -> Int {
        var migrated = 0
        for receipt in receipts where receipt.hasQuarantinedContent {
            if try await scheduleStore.schedule(receiptID: receipt.id) == nil {
                try await register(receipt: receipt, policy: policy, at: date)
                migrated += 1
            }
        }
        return migrated
    }

    public func reschedule(
        receiptID: UUID,
        policy: QuarantineRetentionPolicy,
        at date: Date
    ) async throws {
        guard let receipt = try await historyStore.receipt(id: receiptID) else {
            throw QuarantineMaintenanceError.receiptNotFound
        }
        guard receipt.hasQuarantinedContent else {
            try await scheduleStore.remove(receiptID: receiptID)
            throw QuarantineMaintenanceError.noQuarantinedContent
        }
        try await register(receipt: receipt, policy: policy, at: date)
    }

    public func reconcile(receipt: OperationReceipt) async throws {
        if !receipt.hasQuarantinedContent {
            try await scheduleStore.remove(receiptID: receipt.id)
        }
    }

    public func processDue(at date: Date) async throws -> QuarantineMaintenanceResult {
        let due = try await scheduleStore.dueSchedules(at: date)
        var deletedItemCount = 0
        var trashedItemCount = 0
        var releasedBytes: UInt64 = 0
        var failedItemCount = 0
        var unavailableItemCount = 0

        for schedule in due {
            let result = try await process(schedule: schedule, at: date)
            deletedItemCount += result.deletedItemCount
            trashedItemCount += result.trashedItemCount
            releasedBytes += result.releasedBytes
            failedItemCount += result.failedItemCount
            unavailableItemCount += result.unavailableItemCount
        }

        return QuarantineMaintenanceResult(
            processedScheduleCount: due.count,
            deletedItemCount: deletedItemCount,
            trashedItemCount: trashedItemCount,
            releasedBytes: releasedBytes,
            failedItemCount: failedItemCount,
            unavailableItemCount: unavailableItemCount
        )
    }

    public func processDue(
        receiptID: UUID,
        at date: Date
    ) async throws -> QuarantineMaintenanceResult {
        guard let schedule = try await scheduleStore.dueSchedules(at: date).first(where: {
            $0.receiptID == receiptID
        }) else {
            return QuarantineMaintenanceResult()
        }
        return try await process(schedule: schedule, at: date)
    }

    private func process(
        schedule: QuarantineSchedule,
        at date: Date
    ) async throws -> QuarantineMaintenanceResult {
        await lifecycleGate.acquire(receiptID: schedule.receiptID)
        do {
            guard let receipt = try await historyStore.receipt(id: schedule.receiptID) else {
                try await scheduleStore.remove(receiptID: schedule.receiptID)
                await lifecycleGate.release(receiptID: schedule.receiptID)
                return QuarantineMaintenanceResult(processedScheduleCount: 1)
            }
            guard receipt.hasQuarantinedContent else {
                try await scheduleStore.remove(receiptID: receipt.id)
                await lifecycleGate.release(receiptID: schedule.receiptID)
                return QuarantineMaintenanceResult(processedScheduleCount: 1)
            }

            let resolutionAction: ResolutionAction = schedule.policy == .immediate ? .trash : .purge
            let pendingResolution = try await resolutionJournalStore.entries().first {
                $0.action == resolutionAction && $0.receipt.id == receipt.id
            }
            let resolutionEntry: ResolutionJournalEntry
            if let pendingResolution {
                resolutionEntry = pendingResolution
            } else {
                resolutionEntry = await executor.prepareResolution(
                    action: resolutionAction,
                    receipt: receipt,
                    id: UUID(),
                    startedAt: date
                )
                try await resolutionJournalStore.upsert(resolutionEntry)
            }
            let rawResolutionResults = await executor.resolve(resolutionEntry)
            let resolutionResults = rawResolutionResults.map { result in
                guard result.status == .sourceMissing else { return result }
                return OperationResult(
                    id: result.id,
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: result.destinationURL,
                    disposition: .unavailable,
                    status: .sourceMissing,
                    bytes: 0,
                    message: "保留内容已不存在，已结束恢复记录；未计入本次释放空间"
                )
            }
            let deleted = resolutionResults.filter {
                $0.disposition == .permanentlyDeleted && $0.status == .succeeded
            }
            let trashed = resolutionResults.filter {
                $0.disposition == .trashed && $0.status == .succeeded
            }
            let unavailable = resolutionResults.filter {
                $0.disposition == .unavailable && $0.status == .sourceMissing
            }
            let failures = resolutionResults.filter {
                !($0.disposition == .permanentlyDeleted && $0.status == .succeeded)
                    && !($0.disposition == .trashed && $0.status == .succeeded)
                    && !($0.disposition == .unavailable && $0.status == .sourceMissing)
            }
            guard let latestReceipt = try await historyStore.receipt(id: receipt.id) else {
                throw QuarantineMaintenanceError.receiptNotFound
            }
            let updatedReceipt = latestReceipt.applying(resolutionResults: resolutionResults)
            let persistenceFailureReason = AutomaticCleanupFailureReason(
                code: .historyPersistenceFailed,
                message: "文件处理已完成，但恢复记录尚未持久化",
                failedItemCount: failures.count
            )

            try await scheduleStore.upsert(schedule.recordingAttempt(
                at: date,
                failureReason: persistenceFailureReason
            ))
            try await historyStore.upsert(updatedReceipt)
            if updatedReceipt.hasQuarantinedContent {
                let failureReason = AutomaticCleanupFailureReason(
                    code: .itemDeletionFailed,
                    message: failures.compactMap(\.message).first ?? "部分已删除项目未能彻底删除",
                    failedItemCount: failures.count
                )
                try await scheduleStore.upsert(schedule.recordingAttempt(
                    at: date,
                    failureReason: failureReason
                ))
            } else {
                try await scheduleStore.remove(receiptID: receipt.id)
            }
            if resolutionEntry.isFullyResolved(by: resolutionResults) {
                try await resolutionJournalStore.remove(id: resolutionEntry.id)
            }
            await lifecycleGate.release(receiptID: schedule.receiptID)
            return QuarantineMaintenanceResult(
                processedScheduleCount: 1,
                deletedItemCount: deleted.count,
                trashedItemCount: trashed.count,
                releasedBytes: deleted.reduce(0) { $0 + $1.bytes },
                failedItemCount: failures.count,
                unavailableItemCount: unavailable.count
            )
        } catch {
            await lifecycleGate.release(receiptID: schedule.receiptID)
            throw error
        }
    }
}

public extension OperationReceipt {
    var hasQuarantinedContent: Bool {
        results.contains { $0.disposition == .quarantined }
    }
}
