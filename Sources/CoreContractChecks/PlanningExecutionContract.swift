import CleanerCore
import Foundation

func runPlanningExecutionContracts() async throws {
    let now = Date(timeIntervalSince1970: 30_000_000)
    let safe = contractCandidate(path: "/tmp/cleaner-contract-item", risk: .safe)
    let blocked = contractCandidate(path: "/tmp/cleaner-contract-blocked", risk: .blocked)
    do {
        _ = try PlanBuilder().build(candidates: [blocked], selectedIDs: [blocked.id], now: now)
        require(false, "blocked candidate entered a plan")
    } catch is PlanBuilderError {
        // Expected.
    }

    let builder = PlanBuilder(engineVersion: "1.0", ruleVersion: "rules-1", planTTL: 300)
    let plan = try builder.build(candidates: [safe], selectedIDs: [safe.id], now: now)
    require(plan.engineVersion == "1.0" && plan.ruleVersion == "rules-1", "plan must bind engine and rules")

    let changedFS = ExecutionContractFileSystem(entries: [safe.url: contractCandidate(path: safe.url.path, risk: .safe, inode: 99).identity])
    let changedExecutor = CleanupExecutor(fileSystem: changedFS, pathPolicy: PathPolicy(), quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine"), currentRuleVersion: "rules-1", now: { now })
    let changedReceipt = await changedExecutor.execute(plan: plan)
    require(changedReceipt.results.first?.status == .skippedIdentityChanged, "identity race must skip")
    let changedMutations = await changedFS.mutations()
    require(changedMutations.isEmpty, "identity race must not mutate")

    let expiredFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let expiredExecutor = CleanupExecutor(fileSystem: expiredFS, pathPolicy: PathPolicy(), quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine"), currentRuleVersion: "rules-1", now: { now.addingTimeInterval(301) })
    let expiredReceipt = await expiredExecutor.execute(plan: plan)
    require(expiredReceipt.overallStatus == .rejected, "expired plan must be rejected")
    let expiredMutations = await expiredFS.mutationCount()
    require(expiredMutations == 0, "rejected plan must not mutate")

    let recoverableFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let recoverableExecutor = CleanupExecutor(fileSystem: recoverableFS, pathPolicy: PathPolicy(), quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine"), currentRuleVersion: "rules-1", now: { now })
    let cleanupReceipt = await recoverableExecutor.execute(plan: plan)
    require(cleanupReceipt.results.first?.status == .succeeded, "valid cleanup should quarantine")
    await recoverableFS.put(safe.identity, at: safe.url)
    let restoreReceipt = await recoverableExecutor.restore(receipt: cleanupReceipt)
    require(restoreReceipt.results.first?.status == .restoreConflict, "restore must surface destination conflict")
    require(restoreReceipt.results.first?.destinationURL != safe.url, "restore must never overwrite original path")
    let restoredHistory = cleanupReceipt.applying(resolutionResults: restoreReceipt.results)
    require(restoredHistory.results.first?.disposition == .restored, "successful restore must resolve the quarantined history item")

    let purgeFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let purgeExecutor = CleanupExecutor(
        fileSystem: purgeFS,
        pathPolicy: PathPolicy(),
        quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-purge"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await purgeFS.removePermanently(url) }
    )
    let purgeSourceReceipt = await purgeExecutor.execute(plan: plan)
    let purgeReceipt = await purgeExecutor.purge(receipt: purgeSourceReceipt)
    require(purgeReceipt.results.first?.disposition == .permanentlyDeleted, "purge must mark owned quarantine content permanently deleted")
    let purgeSourceStillExists = await purgeFS.fileExists(purgeSourceReceipt.results.first!.destinationURL!)
    require(!purgeSourceStillExists, "purge must release quarantined storage")
    let purgedHistory = purgeSourceReceipt.applying(resolutionResults: purgeReceipt.results)
    require(purgedHistory.results.first?.disposition == .permanentlyDeleted, "purge must resolve the quarantined history item")

    let vanishedPurgeFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let vanishedPurgeExecutor = CleanupExecutor(
        fileSystem: vanishedPurgeFS,
        pathPolicy: PathPolicy(),
        quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-vanished-purge"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await vanishedPurgeFS.removePermanently(url) }
    )
    let vanishedPurgeReceipt = await vanishedPurgeExecutor.execute(plan: plan)
    let vanishedPurgeEntry = await vanishedPurgeExecutor.prepareResolution(
        action: .purge,
        receipt: vanishedPurgeReceipt,
        id: UUID(),
        startedAt: now
    )
    try await vanishedPurgeFS.removePermanently(vanishedPurgeReceipt.results[0].destinationURL!)
    let vanishedPurgeResults = await vanishedPurgeExecutor.resolve(vanishedPurgeEntry)
    require(
        vanishedPurgeResults.first?.status == .succeeded
            && vanishedPurgeResults.first?.disposition == .permanentlyDeleted,
        "a durable purge intent whose source existed before deletion must converge after recovery"
    )
    let absentAtPreparationEntry = await vanishedPurgeExecutor.prepareResolution(
        action: .purge,
        receipt: vanishedPurgeReceipt,
        id: UUID(),
        startedAt: now
    )
    let absentAtPreparationResults = await vanishedPurgeExecutor.resolve(absentAtPreparationEntry)
    require(
        absentAtPreparationResults.first?.status == .sourceMissing
            && absentAtPreparationResults.first?.disposition == .failed,
        "a purge source already absent at preparation must remain unverified"
    )
    let vanishedRecoveryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("cleaner-vanished-purge-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: vanishedRecoveryRoot) }
    let vanishedRecoveryHistory = HistoryStore(
        url: vanishedRecoveryRoot.appendingPathComponent("history.json")
    )
    let vanishedRecoverySchedules = QuarantineScheduleStore(
        url: vanishedRecoveryRoot.appendingPathComponent("schedules.json")
    )
    let vanishedRecoveryExecutionJournal = ExecutionJournalStore(
        url: vanishedRecoveryRoot.appendingPathComponent("execution-journal.json")
    )
    let vanishedRecoveryResolutionJournal = ResolutionJournalStore(
        url: vanishedRecoveryRoot.appendingPathComponent("resolution-journal.json")
    )
    try await vanishedRecoveryHistory.upsert(vanishedPurgeReceipt)
    try await vanishedRecoveryResolutionJournal.upsert(vanishedPurgeEntry)
    let vanishedRecoveryMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: vanishedRecoveryHistory,
        scheduleStore: vanishedRecoverySchedules,
        executor: vanishedPurgeExecutor,
        resolutionJournalStore: vanishedRecoveryResolutionJournal
    )
    let vanishedRecoveryCoordinator = CleanupExecutionCoordinator(
        executor: vanishedPurgeExecutor,
        historyStore: vanishedRecoveryHistory,
        journalStore: vanishedRecoveryExecutionJournal,
        resolutionJournalStore: vanishedRecoveryResolutionJournal,
        scheduleStore: vanishedRecoverySchedules,
        maintenanceCoordinator: vanishedRecoveryMaintenance,
        now: { now }
    )
    _ = try await vanishedRecoveryCoordinator.recoverPendingExecutions()
    let vanishedRecoveredReceipt = try await vanishedRecoveryHistory.receipt(id: vanishedPurgeReceipt.id)
    let vanishedRecoveryEntries = try await vanishedRecoveryResolutionJournal.entries()
    require(
        vanishedRecoveredReceipt?.results.first?.disposition == .permanentlyDeleted,
        "startup recovery must persist a prepared purge whose source is already absent"
    )
    require(
        vanishedRecoveryEntries.isEmpty,
        "startup recovery must clear a purge journal only after terminal history is persisted"
    )

    let maintenanceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-maintenance-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: maintenanceRoot) }
    let maintenanceFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let maintenanceExecutor = CleanupExecutor(
        fileSystem: maintenanceFS,
        pathPolicy: PathPolicy(),
        quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-maintenance"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await maintenanceFS.removePermanently(url) }
    )
    let maintenanceReceipt = await maintenanceExecutor.execute(plan: plan)
    let maintenanceHistory = HistoryStore(url: maintenanceRoot.appendingPathComponent("history.json"))
    let maintenanceSchedules = QuarantineScheduleStore(url: maintenanceRoot.appendingPathComponent("schedules.json"))
    let maintenanceResolutionJournal = ResolutionJournalStore(
        url: maintenanceRoot.appendingPathComponent("resolution-journal.json")
    )
    try await maintenanceHistory.append(maintenanceReceipt)
    let maintenance = QuarantineMaintenanceCoordinator(
        historyStore: maintenanceHistory,
        scheduleStore: maintenanceSchedules,
        executor: maintenanceExecutor,
        resolutionJournalStore: maintenanceResolutionJournal
    )
    try await maintenance.register(
        receipt: maintenanceReceipt,
        policy: .hours24,
        at: now.addingTimeInterval(-86_400)
    )
    let maintenanceResult = try await maintenance.processDue(at: now)
    require(maintenanceResult.deletedItemCount == 1, "due quarantine maintenance must permanently delete owned content")
    let maintainedReceipt = try await maintenanceHistory.receipt(id: maintenanceReceipt.id)
    require(maintainedReceipt?.results.first?.disposition == .permanentlyDeleted, "automatic purge must update the recovery record lifecycle")
    let clearedSchedule = try await maintenanceSchedules.schedule(receiptID: maintenanceReceipt.id)
    require(clearedSchedule == nil, "fully resolved quarantine records must leave no stale schedule")

    let missingMaintenanceFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let missingMaintenanceExecutor = CleanupExecutor(
        fileSystem: missingMaintenanceFS,
        pathPolicy: PathPolicy(),
        quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-maintenance-missing"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await missingMaintenanceFS.removePermanently(url) }
    )
    let missingMaintenanceReceipt = await missingMaintenanceExecutor.execute(plan: plan)
    try await missingMaintenanceFS.removePermanently(missingMaintenanceReceipt.results.first!.destinationURL!)
    let missingMaintenanceHistory = HistoryStore(url: maintenanceRoot.appendingPathComponent("missing-history.json"))
    let missingMaintenanceSchedules = QuarantineScheduleStore(url: maintenanceRoot.appendingPathComponent("missing-schedules.json"))
    let missingMaintenanceResolutionJournal = ResolutionJournalStore(
        url: maintenanceRoot.appendingPathComponent("missing-resolution-journal.json")
    )
    try await missingMaintenanceHistory.append(missingMaintenanceReceipt)
    let missingMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: missingMaintenanceHistory,
        scheduleStore: missingMaintenanceSchedules,
        executor: missingMaintenanceExecutor,
        resolutionJournalStore: missingMaintenanceResolutionJournal
    )
    try await missingMaintenance.register(
        receipt: missingMaintenanceReceipt,
        policy: .hours24,
        at: now.addingTimeInterval(-86_400)
    )
    let missingMaintenanceResult = try await missingMaintenance.processDue(at: now)
    let reconciledMissingReceipt = try await missingMaintenanceHistory.receipt(id: missingMaintenanceReceipt.id)
    require(
        missingMaintenanceResult.unavailableItemCount == 1
            && missingMaintenanceResult.releasedBytes == 0
            && reconciledMissingReceipt?.results.first?.disposition == .unavailable,
        "automatic maintenance must close stale recovery items without claiming released space"
    )
    let missingMaintenanceSchedule = try await missingMaintenanceSchedules.schedule(receiptID: missingMaintenanceReceipt.id)
    require(
        missingMaintenanceSchedule == nil,
        "an unavailable quarantine payload must not remain in the automatic retry queue"
    )

    let failedMaintenanceFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let failedMaintenanceExecutor = CleanupExecutor(
        fileSystem: failedMaintenanceFS,
        quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-maintenance-failure"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in throw FileSystemError.trashUnavailable(url) }
    )
    let failedMaintenanceReceipt = await failedMaintenanceExecutor.execute(plan: plan)
    let failedMaintenanceHistory = HistoryStore(url: maintenanceRoot.appendingPathComponent("failed-history.json"))
    let failedMaintenanceSchedules = QuarantineScheduleStore(url: maintenanceRoot.appendingPathComponent("failed-schedules.json"))
    let failedMaintenanceResolutionJournal = ResolutionJournalStore(
        url: maintenanceRoot.appendingPathComponent("failed-resolution-journal.json")
    )
    try await failedMaintenanceHistory.upsert(failedMaintenanceReceipt)
    let failedMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: failedMaintenanceHistory,
        scheduleStore: failedMaintenanceSchedules,
        executor: failedMaintenanceExecutor,
        resolutionJournalStore: failedMaintenanceResolutionJournal
    )
    try await failedMaintenance.register(
        receipt: failedMaintenanceReceipt,
        policy: .hours24,
        at: now.addingTimeInterval(-86_400)
    )
    let failedMaintenanceResult = try await failedMaintenance.processDue(at: now)
    let failedMaintenanceSchedule = try await failedMaintenanceSchedules.schedule(
        receiptID: failedMaintenanceReceipt.id
    )
    require(
        failedMaintenanceResult.failedItemCount == 1
            && failedMaintenanceSchedule?.failureReason?.code == .itemDeletionFailed
            && failedMaintenanceSchedule?.failureReason?.failedItemCount == 1,
        "automatic cleanup failures must expose a structured reason and failed item count"
    )
    let retainedFailedResolutionEntries = try await failedMaintenanceResolutionJournal.entries()
    require(
        retainedFailedResolutionEntries.count == 1,
        "an unresolved automatic purge must retain its resolution journal for retry"
    )

    let persistenceFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let persistenceExecutor = CleanupExecutor(
        fileSystem: persistenceFS,
        quarantineRoot: maintenanceRoot.appendingPathComponent("persistence-quarantine"),
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await persistenceFS.removePermanently(url) }
    )
    let persistenceReceipt = await persistenceExecutor.execute(plan: plan)
    let persistenceHistory = HistoryStore(
        url: maintenanceRoot.appendingPathComponent("persistence-history.json")
    )
    let persistenceSchedules = QuarantineScheduleStore(
        url: maintenanceRoot.appendingPathComponent("persistence-schedules.json")
    )
    let persistenceResolutionJournal = ResolutionJournalStore(
        url: maintenanceRoot.appendingPathComponent("persistence-resolution-journal.json")
    )
    try await persistenceHistory.upsert(persistenceReceipt)
    let persistenceMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: persistenceHistory,
        scheduleStore: persistenceSchedules,
        executor: persistenceExecutor,
        resolutionJournalStore: persistenceResolutionJournal
    )
    try await persistenceMaintenance.register(
        receipt: persistenceReceipt,
        policy: .hours24,
        at: now.addingTimeInterval(-86_400)
    )
    await persistenceHistory.failNextCommitForTesting()
    do {
        _ = try await persistenceMaintenance.processDue(at: now)
        require(false, "maintenance unexpectedly ignored an interrupted history commit")
    } catch is HistoryStoreError {
        // Expected.
    }
    let persistenceFailureSchedule = try await persistenceSchedules.schedule(
        receiptID: persistenceReceipt.id
    )
    require(
        persistenceFailureSchedule?.lastAttemptAt == now
            && persistenceFailureSchedule?.failureReason?.code == .historyPersistenceFailed,
        "history persistence failure must retain attempt time and a structured reason"
    )
    let schedulesBeforeRetry = try await persistenceSchedules.dueSchedules(
        at: now.addingTimeInterval(3_599)
    )
    require(
        schedulesBeforeRetry.isEmpty,
        "history persistence failure must preserve the one-hour retry backoff"
    )

    let coordinationRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-coordination-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: coordinationRoot) }
    let coordinatedFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let coordinatedQuarantineRoot = coordinationRoot.appendingPathComponent("quarantine", isDirectory: true)
    let coordinatedExecutor = CleanupExecutor(
        fileSystem: coordinatedFS,
        quarantineRoot: coordinatedQuarantineRoot,
        currentRuleVersion: "rules-1",
        now: { now },
        permanentRemove: { url in try await coordinatedFS.removePermanently(url) }
    )
    let coordinatedHistory = HistoryStore(url: coordinationRoot.appendingPathComponent("history.json"))
    let coordinatedSchedules = QuarantineScheduleStore(url: coordinationRoot.appendingPathComponent("schedules.json"))
    let coordinatedJournal = ExecutionJournalStore(url: coordinationRoot.appendingPathComponent("journal.json"))
    let coordinatedResolutionJournal = ResolutionJournalStore(
        url: coordinationRoot.appendingPathComponent("resolution-journal.json")
    )
    let coordinatedMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: coordinatedHistory,
        scheduleStore: coordinatedSchedules,
        executor: coordinatedExecutor,
        resolutionJournalStore: coordinatedResolutionJournal
    )
    let coordinator = CleanupExecutionCoordinator(
        executor: coordinatedExecutor,
        historyStore: coordinatedHistory,
        journalStore: coordinatedJournal,
        resolutionJournalStore: coordinatedResolutionJournal,
        scheduleStore: coordinatedSchedules,
        maintenanceCoordinator: coordinatedMaintenance,
        now: { now }
    )
    let coordinatedReceipt = try await coordinator.execute(plan: plan, retentionPolicy: .hours24)
    let persistedCoordinatedReceipt = try await coordinator.receipts().first {
        $0.id == coordinatedReceipt.id
    }
    let coordinatedSchedule = try await coordinator.schedules().first {
        $0.receiptID == coordinatedReceipt.id
    }
    let remainingCoordinatedEntries = try await coordinatedJournal.entries()
    require(
        persistedCoordinatedReceipt == coordinatedReceipt,
        "coordinated execution must persist history"
    )
    require(
        coordinatedSchedule?.policy == .hours24,
        "coordinated execution must register quarantine retention"
    )
    require(
        remainingCoordinatedEntries.isEmpty,
        "coordinated execution must clear its journal only after finalization"
    )
    let immediateCandidate = contractCandidate(
        path: "/tmp/cleaner-contract-immediate",
        risk: .safe,
        inode: 101
    )
    await coordinatedFS.put(immediateCandidate.identity, at: immediateCandidate.url)
    let immediatePlan = try builder.build(
        candidates: [immediateCandidate],
        selectedIDs: [immediateCandidate.id],
        now: now
    )
    let immediateReceipt = try await coordinator.execute(
        plan: immediatePlan,
        retentionPolicy: .immediate
    )
    let immediateSchedule = try await coordinator.schedules().first {
        $0.receiptID == immediateReceipt.id
    }
    require(
        immediateReceipt.results.first?.disposition == .trashed,
        "immediate retention must move newly quarantined content to the system trash before execution returns"
    )
    require(
        immediateSchedule == nil,
        "immediate retention must not leave a stale quarantine schedule"
    )
    let mutationCountBeforeDuplicate = await coordinatedFS.mutationCount()
    do {
        _ = try await coordinator.execute(plan: plan, retentionPolicy: .hours24)
        require(false, "coordinator accepted a duplicate plan ID")
    } catch let error as CleanupExecutionCoordinatorError {
        require(
            error == .duplicatePlanID(plan.id),
            "duplicate plan rejection must identify the reused plan ID"
        )
    }
    let mutationCountAfterDuplicate = await coordinatedFS.mutationCount()
    require(
        mutationCountAfterDuplicate == mutationCountBeforeDuplicate,
        "duplicate plan rejection must occur before file-system mutation"
    )
    try await coordinatedSchedules.remove(receiptID: coordinatedReceipt.id)
    let migratedScheduleCount = try await coordinator.migrateUnscheduled(
        policy: .days2,
        at: now
    )
    let migratedSchedule = try await coordinator.schedules().first {
        $0.receiptID == coordinatedReceipt.id
    }
    require(
        migratedScheduleCount == 1 && migratedSchedule?.policy == .days2,
        "coordinator must migrate persisted quarantine history without requiring callers to read history"
    )
    try await coordinator.reschedule(
        receiptID: coordinatedReceipt.id,
        policy: .manual,
        at: now
    )
    let rescheduled = try await coordinator.schedules().first {
        $0.receiptID == coordinatedReceipt.id
    }
    require(
        rescheduled?.policy == .manual,
        "coordinator must expose quarantine rescheduling"
    )
    await coordinatedHistory.failNextCommitForTesting()
    do {
        _ = try await coordinator.restore(receipt: coordinatedReceipt)
        require(false, "restore unexpectedly finalized after an interrupted history commit")
    } catch is HistoryStoreError {
        // Expected.
    }
    let interruptedResolutionEntries = try await coordinatedResolutionJournal.entries()
    require(
        interruptedResolutionEntries.count == 1,
        "restore must retain its durable resolution intent until history finalization"
    )
    _ = try await coordinator.recoverPendingExecutions()
    let restoredCoordinatedHistory = try await coordinator.receipts().first {
        $0.id == coordinatedReceipt.id
    }
    let schedulesAfterRestore = try await coordinator.schedules()
    require(
        restoredCoordinatedHistory?.results.first?.disposition == .restored
            && !schedulesAfterRestore.contains(where: { $0.receiptID == coordinatedReceipt.id }),
        "startup recovery must finalize an interrupted restore and reconcile its schedule"
    )
    let recoveredResolutionEntries = try await coordinatedResolutionJournal.entries()
    require(
        recoveredResolutionEntries.isEmpty,
        "startup recovery must clear a finalized resolution journal"
    )

    let coordinatedPurgePlan = try builder.build(
        candidates: [safe],
        selectedIDs: [safe.id],
        now: now
    )
    let coordinatedPurgeSource = try await coordinator.execute(
        plan: coordinatedPurgePlan,
        retentionPolicy: .manual
    )
    let coordinatedPurge = try await coordinator.purge(receipt: coordinatedPurgeSource)
    let purgedCoordinatedHistory = try await coordinator.receipts().first {
        $0.id == coordinatedPurgeSource.id
    }
    require(
        coordinatedPurge.results.first?.disposition == .permanentlyDeleted
            && purgedCoordinatedHistory?.results.first?.disposition == .permanentlyDeleted,
        "coordinated purge must permanently delete content and persist resolution"
    )

    await coordinatedFS.put(safe.identity, at: safe.url)
    let coordinatedDuePlan = try builder.build(
        candidates: [safe],
        selectedIDs: [safe.id],
        now: now
    )
    let coordinatedDueSource = try await coordinator.execute(
        plan: coordinatedDuePlan,
        retentionPolicy: .hours24
    )
    try await coordinator.reschedule(
        receiptID: coordinatedDueSource.id,
        policy: .hours24,
        at: now.addingTimeInterval(-86_400)
    )
    let coordinatedMaintenanceResult = try await coordinator.processDue(at: now)
    require(
        coordinatedMaintenanceResult.deletedItemCount == 1,
        "coordinator must process due quarantine schedules"
    )

    await coordinatedFS.put(safe.identity, at: safe.url)
    let mutuallyExclusivePlan = try builder.build(
        candidates: [safe],
        selectedIDs: [safe.id],
        now: now
    )
    let mutuallyExclusiveReceipt = try await coordinator.execute(
        plan: mutuallyExclusivePlan,
        retentionPolicy: .manual
    )
    async let concurrentRestore = coordinator.restore(receipt: mutuallyExclusiveReceipt)
    async let concurrentPurge = coordinator.purge(receipt: mutuallyExclusiveReceipt)
    let (concurrentRestoreReceipt, concurrentPurgeReceipt) = try await (
        concurrentRestore,
        concurrentPurge
    )
    let concurrentResolutionResults = concurrentRestoreReceipt.results + concurrentPurgeReceipt.results
    require(
        concurrentResolutionResults.filter {
            $0.disposition == .restored || $0.disposition == .permanentlyDeleted
        }.count == 1,
        "restore and purge for one receipt must serialize into exactly one terminal resolution"
    )
    require(
        !concurrentResolutionResults.contains { $0.status == .failed },
        "the operation waiting on a receipt lifecycle lock must re-read history instead of acting on stale quarantine state"
    )

    let recoveryFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity])
    let recoveryExecutor = CleanupExecutor(
        fileSystem: recoveryFS,
        quarantineRoot: coordinatedQuarantineRoot,
        currentRuleVersion: "rules-1",
        now: { now }
    )
    let recoveryHistory = HistoryStore(url: coordinationRoot.appendingPathComponent("recovery-history.json"))
    let recoverySchedules = QuarantineScheduleStore(url: coordinationRoot.appendingPathComponent("recovery-schedules.json"))
    let recoveryJournal = ExecutionJournalStore(url: coordinationRoot.appendingPathComponent("recovery-journal.json"))
    let recoveryResolutionJournal = ResolutionJournalStore(
        url: coordinationRoot.appendingPathComponent("recovery-resolution-journal.json")
    )
    let recoveryMaintenance = QuarantineMaintenanceCoordinator(
        historyStore: recoveryHistory,
        scheduleStore: recoverySchedules,
        executor: recoveryExecutor,
        resolutionJournalStore: recoveryResolutionJournal
    )
    let recoveryCoordinator = CleanupExecutionCoordinator(
        executor: recoveryExecutor,
        historyStore: recoveryHistory,
        journalStore: recoveryJournal,
        resolutionJournalStore: recoveryResolutionJournal,
        scheduleStore: recoverySchedules,
        maintenanceCoordinator: recoveryMaintenance,
        now: { now }
    )
    let recoveryEntry = ExecutionJournalEntry(
        id: UUID(),
        plan: plan,
        startedAt: now,
        retentionPolicy: .days2
    )
    let recoveredDestination = coordinatedQuarantineRoot
        .appendingPathComponent(plan.id.uuidString, isDirectory: true)
        .appendingPathComponent(safe.id.uuidString + "-" + safe.url.lastPathComponent)
    try await recoveryFS.move(safe.url, to: recoveredDestination)
    try await recoveryJournal.upsert(recoveryEntry)
    let startupRecovery = try await recoveryCoordinator.recoverPendingExecutions()
    let remainingRecoveryEntries = try await recoveryJournal.entries()
    require(
        startupRecovery.first?.results.first?.disposition == .quarantined,
        "startup recovery must reconstruct a completed move from the durable journal"
    )
    require(
        remainingRecoveryEntries.isEmpty,
        "startup recovery must finalize and clear recovered journal entries"
    )

    let outsideURL = URL(fileURLWithPath: "/tmp/not-cleaner-owned")
    await purgeFS.put(safe.identity, at: outsideURL)
    let forgedReceipt = OperationReceipt(
        planID: UUID(), startedAt: now, completedAt: now,
        results: [OperationResult(candidateID: safe.id, originalURL: safe.url, destinationURL: outsideURL, disposition: .quarantined, status: .succeeded, bytes: safe.bytes)]
    )
    let rejectedPurge = await purgeExecutor.purge(receipt: forgedReceipt)
    require(rejectedPurge.results.first?.status == .skippedProtected, "purge must reject paths outside the owned quarantine")
    let outsideStillExists = await purgeFS.fileExists(outsideURL)
    require(outsideStillExists, "rejected purge must not delete outside content")
    let rejectedRestore = await purgeExecutor.restore(receipt: forgedReceipt)
    require(rejectedRestore.results.first?.status == .skippedProtected, "restore must reject sources outside the owned quarantine")
    let outsideStillExistsAfterRestore = await purgeFS.fileExists(outsideURL)
    require(outsideStillExistsAfterRestore, "rejected restore must not move outside content")

    let wrongPlanURL = URL(fileURLWithPath: "/tmp/cleaner-quarantine-purge/another-plan/\(safe.id.uuidString)-item")
    await purgeFS.put(safe.identity, at: wrongPlanURL)
    let crossReceipt = OperationReceipt(
        planID: UUID(), startedAt: now, completedAt: now,
        results: [OperationResult(candidateID: safe.id, originalURL: safe.url, destinationURL: wrongPlanURL, disposition: .quarantined, status: .succeeded, bytes: safe.bytes)]
    )
    let rejectedCrossPurge = await purgeExecutor.purge(receipt: crossReceipt)
    require(rejectedCrossPurge.results.first?.status == .skippedProtected, "purge must reject quarantine content owned by another plan")
    let wrongPlanStillExists = await purgeFS.fileExists(wrongPlanURL)
    require(wrongPlanStillExists, "cross-plan purge must not delete another quarantine batch")

    let failingFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity], failMoves: true)
    let failingExecutor = CleanupExecutor(fileSystem: failingFS, pathPolicy: PathPolicy(), quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine"), currentRuleVersion: "rules-1", now: { now })
    let failedReceipt = await failingExecutor.execute(plan: plan)
    require(failedReceipt.results.first?.status == .failed, "move failure must be reported")
    let failureMutations = await failingFS.mutations()
    require(!failureMutations.contains("trash"), "move failure must never fall back to trash or permanent deletion")

    let second = contractCandidate(path: "/tmp/cleaner-contract-second", risk: .safe, inode: 5)
    let cancelPlan = try builder.build(candidates: [safe, second], selectedIDs: [safe.id, second.id], now: now)
    let cancelFS = ExecutionContractFileSystem(entries: [safe.url: safe.identity, second.url: second.identity])
    let cancelExecutor = CleanupExecutor(fileSystem: cancelFS, pathPolicy: PathPolicy(), quarantineRoot: URL(fileURLWithPath: "/tmp/cleaner-quarantine-cancel"), currentRuleVersion: "rules-1", now: { now })
    let cancelledReceipt = await Task {
        await cancelExecutor.execute(plan: cancelPlan) { progress in
            if progress.completed == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }.value
    require(cancelledReceipt.overallStatus == .partial, "cancelled execution was reported complete")
    require(cancelledReceipt.results.contains { $0.status == .skippedCancelled }, "cancelled items were absent from receipt")
}

private func contractCandidate(path: String, risk: RiskLevel, inode: UInt64 = 2) -> CleanupCandidate {
    CleanupCandidate(url: URL(fileURLWithPath: path), displayName: URL(fileURLWithPath: path).lastPathComponent, category: .cache, bytes: 10, risk: risk, evidence: [Evidence(code: "fixture", summary: "fixture")], identity: FileIdentity(device: 1, inode: inode, size: 10, modificationTime: 3, kind: .file), source: .general, lastAccessDate: nil, isActive: false)
}

private actor ExecutionContractFileSystem: FileSystemAccess {
    private var entries: [URL: FileIdentity]
    private var writeLog: [String] = []
    private let failMoves: Bool
    init(entries: [URL: FileIdentity], failMoves: Bool = false) { self.entries = entries; self.failMoves = failMoves }
    func identity(at url: URL) throws -> FileIdentity { guard let value = entries[url] else { throw FileSystemError.missing(url) }; return value }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { entries[url] != nil }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func move(_ source: URL, to destination: URL) throws {
        if failMoves { writeLog.append("move-failed"); throw FileSystemError.trashUnavailable(source) }
        guard let value = entries.removeValue(forKey: source) else { throw FileSystemError.missing(source) }
        entries[destination] = value
        writeLog.append("move")
    }
    func createDirectory(_ url: URL) { writeLog.append("mkdir") }
    func removeEmptyDirectory(_ url: URL) { writeLog.append("rmdir") }
    func trash(_ url: URL) throws -> URL {
        guard let value = entries.removeValue(forKey: url) else { throw FileSystemError.missing(url) }
        let destination = URL(fileURLWithPath: "/tmp/.Trash").appendingPathComponent(url.lastPathComponent)
        entries[destination] = value
        writeLog.append("trash")
        return destination
    }
    func mutations() -> [String] { writeLog }
    func mutationCount() -> Int { writeLog.count }
    func put(_ identity: FileIdentity, at url: URL) { entries[url] = identity }
    func removePermanently(_ url: URL) throws {
        guard entries.removeValue(forKey: url) != nil else { throw FileSystemError.missing(url) }
        writeLog.append("permanent-remove")
    }
}
