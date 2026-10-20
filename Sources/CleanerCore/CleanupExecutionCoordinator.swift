import Foundation

public enum CleanupExecutionCoordinatorError: Error, Equatable, Sendable {
    case duplicatePlanID(UUID)
    case receiptNotFound(UUID)
}

actor ReceiptLifecycleGate {
    static let shared = ReceiptLifecycleGate()

    private var claimedReceiptIDs = Set<UUID>()
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(receiptID: UUID) async {
        if claimedReceiptIDs.insert(receiptID).inserted { return }
        await withCheckedContinuation { continuation in
            waiters[receiptID, default: []].append(continuation)
        }
    }

    func release(receiptID: UUID) {
        guard var receiptWaiters = waiters[receiptID], !receiptWaiters.isEmpty else {
            claimedReceiptIDs.remove(receiptID)
            waiters.removeValue(forKey: receiptID)
            return
        }
        let next = receiptWaiters.removeFirst()
        if receiptWaiters.isEmpty {
            waiters.removeValue(forKey: receiptID)
        } else {
            waiters[receiptID] = receiptWaiters
        }
        next.resume()
    }
}

public actor CleanupExecutionCoordinator {
    private let executor: CleanupExecutor
    private let historyStore: HistoryStore
    private let journalStore: ExecutionJournalStore
    private let resolutionJournalStore: ResolutionJournalStore
    private let scheduleStore: QuarantineScheduleStore
    private let maintenanceCoordinator: QuarantineMaintenanceCoordinator
    private let lifecycleGate = ReceiptLifecycleGate.shared
    private let now: @Sendable () -> Date
    private var claimedPlanIDs = Set<UUID>()
    private var activePlanIDs = Set<UUID>()

    public init(
        executor: CleanupExecutor,
        historyStore: HistoryStore,
        journalStore: ExecutionJournalStore,
        resolutionJournalStore: ResolutionJournalStore,
        scheduleStore: QuarantineScheduleStore,
        maintenanceCoordinator: QuarantineMaintenanceCoordinator,
        now: @escaping @Sendable () -> Date
    ) {
        self.executor = executor
        self.historyStore = historyStore
        self.journalStore = journalStore
        self.resolutionJournalStore = resolutionJournalStore
        self.scheduleStore = scheduleStore
        self.maintenanceCoordinator = maintenanceCoordinator
        self.now = now
    }

    public func execute(
        plan: CleanupPlan,
        retentionPolicy: QuarantineRetentionPolicy
    ) async throws -> OperationReceipt {
        try await execute(
            plan: plan,
            retentionPolicy: retentionPolicy,
            progress: { _ in }
        )
    }

    public func execute(
        plan: CleanupPlan,
        retentionPolicy: QuarantineRetentionPolicy,
        progress: CleanupExecutor.ProgressHandler
    ) async throws -> OperationReceipt {
        let pendingEntries = try await journalStore.entries()
        let persistedReceipts = try await historyStore.receipts()
        guard !claimedPlanIDs.contains(plan.id),
              !pendingEntries.contains(where: { $0.plan.id == plan.id }),
              !persistedReceipts.contains(where: { $0.planID == plan.id })
        else {
            throw CleanupExecutionCoordinatorError.duplicatePlanID(plan.id)
        }
        claimedPlanIDs.insert(plan.id)
        activePlanIDs.insert(plan.id)
        defer { activePlanIDs.remove(plan.id) }
        let entry = ExecutionJournalEntry(
            id: UUID(),
            plan: plan,
            startedAt: now(),
            retentionPolicy: retentionPolicy
        )
        try await journalStore.upsert(entry)

        let receipt = await executor.execute(
            plan: plan,
            receiptID: entry.id,
            startedAt: entry.startedAt,
            progress: progress
        )
        try await finalize(receipt: receipt, entry: entry)
        return try await applyImmediateRetentionIfNeeded(
            to: receipt,
            policy: retentionPolicy
        )
    }

    @discardableResult
    public func recoverPendingExecutions() async throws -> [OperationReceipt] {
        let entries = try await journalStore.entries()
        var recovered: [OperationReceipt] = []
        for entry in entries {
            if activePlanIDs.contains(entry.plan.id) { continue }
            await lifecycleGate.acquire(receiptID: entry.id)
            let receipt: OperationReceipt
            do {
                // Read only after acquiring the same lifecycle claim used by
                // restore, purge and maintenance. An await during verification
                // must not let a stale snapshot resurrect resolved results.
                if let persistedReceipt = try await historyStore.receipt(id: entry.id) {
                    if persistedReceipt.results.contains(where: { $0.verificationNotBefore != nil }) {
                        receipt = await executor.recoverInterruptedExecution(entry, previousReceipt: persistedReceipt)
                    } else { receipt = persistedReceipt }
                } else {
                    receipt = await executor.recoverInterruptedExecution(entry)
                }
                try await finalize(receipt: receipt, entry: entry)
            } catch {
                await lifecycleGate.release(receiptID: entry.id)
                throw error
            }
            await lifecycleGate.release(receiptID: entry.id)
            let finalizedReceipt = try await applyImmediateRetentionIfNeeded(
                to: receipt,
                policy: entry.retentionPolicy
            )
            recovered.append(finalizedReceipt)
        }
        try await recoverPendingResolutions()
        return recovered
    }

    public func receipts() async throws -> [OperationReceipt] {
        try await historyStore.receipts()
    }

    public func schedules() async throws -> [QuarantineSchedule] {
        try await scheduleStore.schedules()
    }

    public func restore(receipt: OperationReceipt) async throws -> RestoreReceipt {
        await lifecycleGate.acquire(receiptID: receipt.id)
        do {
            guard let latestReceipt = try await historyStore.receipt(id: receipt.id) else {
                throw CleanupExecutionCoordinatorError.receiptNotFound(receipt.id)
            }
            let entry = await executor.prepareResolution(
                action: .restore,
                receipt: latestReceipt,
                id: UUID(),
                startedAt: now()
            )
            try await resolutionJournalStore.upsert(entry)
            let results = await executor.resolve(entry)
            try await finalizeResolution(entry: entry, results: results)
            await lifecycleGate.release(receiptID: receipt.id)
            return RestoreReceipt(
                id: entry.id,
                sourceReceiptID: receipt.id,
                completedAt: now(),
                results: results
            )
        } catch {
            await lifecycleGate.release(receiptID: receipt.id)
            throw error
        }
    }

    public func purge(receipt: OperationReceipt) async throws -> PurgeReceipt {
        await lifecycleGate.acquire(receiptID: receipt.id)
        do {
            guard let latestReceipt = try await historyStore.receipt(id: receipt.id) else {
                throw CleanupExecutionCoordinatorError.receiptNotFound(receipt.id)
            }
            let entry = await executor.prepareResolution(
                action: .purge,
                receipt: latestReceipt,
                id: UUID(),
                startedAt: now()
            )
            try await resolutionJournalStore.upsert(entry)
            let results = await executor.resolve(entry)
            try await finalizeResolution(entry: entry, results: results)
            await lifecycleGate.release(receiptID: receipt.id)
            return PurgeReceipt(
                id: entry.id,
                sourceReceiptID: receipt.id,
                completedAt: now(),
                results: results
            )
        } catch {
            await lifecycleGate.release(receiptID: receipt.id)
            throw error
        }
    }

    public func reschedule(
        receiptID: UUID,
        policy: QuarantineRetentionPolicy,
        at date: Date
    ) async throws {
        await lifecycleGate.acquire(receiptID: receiptID)
        do {
            try await maintenanceCoordinator.reschedule(
                receiptID: receiptID,
                policy: policy,
                at: date
            )
            await lifecycleGate.release(receiptID: receiptID)
        } catch {
            await lifecycleGate.release(receiptID: receiptID)
            throw error
        }
    }

    public func processDue(at date: Date) async throws -> QuarantineMaintenanceResult {
        try await maintenanceCoordinator.processDue(at: date)
    }

    @discardableResult
    public func migrateUnscheduled(
        policy: QuarantineRetentionPolicy,
        at date: Date
    ) async throws -> Int {
        let persistedReceipts = try await historyStore.receipts()
        return try await maintenanceCoordinator.migrateUnscheduled(
            receipts: persistedReceipts,
            policy: policy,
            at: date
        )
    }

    private func finalize(
        receipt: OperationReceipt,
        entry: ExecutionJournalEntry
    ) async throws {
        try await historyStore.upsert(receipt)
        let existingSchedule = try await scheduleStore.schedule(receiptID: receipt.id)
        let awaitsVerification = receipt.results.contains { $0.verificationNotBefore != nil }
        // Reconciliation can run long after a user rescheduled this receipt.
        // Do not reset its deadline, retry history or policy to the old journal.
        // Immediate deletion must also wait for any privileged move to be verified.
        if !(entry.retentionPolicy == .immediate && awaitsVerification),
           (!receipt.hasQuarantinedContent || existingSchedule == nil) {
            try await maintenanceCoordinator.register(
                receipt: receipt,
                policy: entry.retentionPolicy,
                at: receipt.completedAt
            )
        }
        if !awaitsVerification {
            try await journalStore.remove(id: entry.id)
        }
    }

    private func applyImmediateRetentionIfNeeded(
        to receipt: OperationReceipt,
        policy: QuarantineRetentionPolicy
    ) async throws -> OperationReceipt {
        guard policy == .immediate,
              receipt.hasQuarantinedContent,
              !receipt.results.contains(where: { $0.verificationNotBefore != nil })
        else { return receipt }
        _ = try await maintenanceCoordinator.processDue(
            receiptID: receipt.id,
            at: now()
        )
        return try await historyStore.receipt(id: receipt.id) ?? receipt
    }

    private func recoverPendingResolutions() async throws {
        let entries = try await resolutionJournalStore.entries()
        for entry in entries {
            let receiptID = entry.receipt.id
            await lifecycleGate.acquire(receiptID: receiptID)
            do {
                guard let latestReceipt = try await historyStore.receipt(id: receiptID) else {
                    throw CleanupExecutionCoordinatorError.receiptNotFound(receiptID)
                }
                guard latestReceipt.hasQuarantinedContent else {
                    try await resolutionJournalStore.remove(id: entry.id)
                    await lifecycleGate.release(receiptID: receiptID)
                    continue
                }
                let refreshedEntry = ResolutionJournalEntry(
                    id: entry.id,
                    action: entry.action,
                    receipt: latestReceipt,
                    startedAt: entry.startedAt,
                    items: entry.items
                )
                let results = await executor.resolve(refreshedEntry)
                try await finalizeResolution(entry: refreshedEntry, results: results)
                await lifecycleGate.release(receiptID: receiptID)
            } catch {
                await lifecycleGate.release(receiptID: receiptID)
                throw error
            }
        }
    }

    private func finalizeResolution(
        entry: ResolutionJournalEntry,
        results: [OperationResult]
    ) async throws {
        guard let currentReceipt = try await historyStore.receipt(id: entry.receipt.id) else {
            throw CleanupExecutionCoordinatorError.receiptNotFound(entry.receipt.id)
        }
        let updatedReceipt = currentReceipt.applying(resolutionResults: results)
        try await historyStore.upsert(updatedReceipt)
        try await maintenanceCoordinator.reconcile(receipt: updatedReceipt)
        if entry.isFullyResolved(by: results) {
            try await resolutionJournalStore.remove(id: entry.id)
        }
    }
}
