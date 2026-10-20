import CleanerCore
import CryptoKit
import Foundation

func runStoreContracts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let historyURL = root.appendingPathComponent("history.json")
    let receipt1 = OperationReceipt(planID: UUID(), startedAt: Date(timeIntervalSince1970: 1), completedAt: Date(timeIntervalSince1970: 2), results: [])
    let receipt2 = OperationReceipt(planID: UUID(), startedAt: Date(timeIntervalSince1970: 3), completedAt: Date(timeIntervalSince1970: 4), results: [])
    let history = HistoryStore(url: historyURL)
    try await history.append(receipt1)
    await history.failNextCommitForTesting()
    do {
        try await history.append(receipt2)
        require(false, "interrupted history write unexpectedly succeeded")
    } catch {
        // Expected.
    }
    let preservedReceipts = try await history.receipts()
    require(preservedReceipts == [receipt1], "failed write must preserve previous history")
    try await history.append(receipt2)
    let recoveredHistory = try await history.receipts()
    require(recoveredHistory == [receipt1, receipt2], "history store did not recover after interrupted commit")
    let updatedReceipt1 = OperationReceipt(
        id: receipt1.id,
        planID: receipt1.planID,
        startedAt: receipt1.startedAt,
        completedAt: receipt1.completedAt,
        results: [],
        overallStatus: .partial
    )
    try await history.upsert(updatedReceipt1)
    let persistedUpdate = try await history.receipt(id: receipt1.id)
    require(persistedUpdate == updatedReceipt1, "history upsert must replace quarantine lifecycle updates")

    let journal = ExecutionJournalStore(url: root.appendingPathComponent("execution-journal.json"))
    let journalPlan = CleanupPlan(
        createdAt: Date(timeIntervalSince1970: 1),
        expiresAt: Date(timeIntervalSince1970: 301),
        items: []
    )
    let journalEntry1 = ExecutionJournalEntry(
        id: UUID(),
        plan: journalPlan,
        startedAt: Date(timeIntervalSince1970: 1),
        retentionPolicy: .hours24
    )
    let journalEntry2 = ExecutionJournalEntry(
        id: UUID(),
        plan: journalPlan,
        startedAt: Date(timeIntervalSince1970: 2),
        retentionPolicy: .days2
    )
    try await journal.upsert(journalEntry1)
    await journal.failNextCommitForTesting()
    do {
        try await journal.upsert(journalEntry2)
        require(false, "interrupted execution journal write unexpectedly succeeded")
    } catch is ExecutionJournalStoreError {
        // Expected.
    }
    let preservedJournalEntries = try await journal.entries()
    require(
        preservedJournalEntries == [journalEntry1],
        "failed journal commit must preserve the previous durable entries"
    )

    let resolutionJournal = ResolutionJournalStore(
        url: root.appendingPathComponent("resolution-journal.json")
    )
    let resolutionEntry1 = ResolutionJournalEntry(
        id: UUID(),
        action: .restore,
        receipt: receipt1,
        startedAt: receipt1.completedAt,
        items: []
    )
    let resolutionEntry2 = ResolutionJournalEntry(
        id: UUID(),
        action: .purge,
        receipt: receipt2,
        startedAt: receipt2.completedAt,
        items: []
    )
    try await resolutionJournal.upsert(resolutionEntry1)
    await resolutionJournal.failNextCommitForTesting()
    do {
        try await resolutionJournal.upsert(resolutionEntry2)
        require(false, "interrupted resolution journal write unexpectedly succeeded")
    } catch is ExecutionJournalStoreError {
        // Expected.
    }
    let preservedResolutionEntries = try await resolutionJournal.entries()
    require(
        preservedResolutionEntries == [resolutionEntry1],
        "failed resolution journal commit must preserve durable recovery intent"
    )

    let scheduleURL = root.appendingPathComponent("quarantine-schedules.json")
    let scheduleStore = QuarantineScheduleStore(url: scheduleURL)
    let scheduledAt = Date(timeIntervalSince1970: 10_000)
    let defaultSchedule = QuarantineSchedule(
        receiptID: receipt1.id,
        policy: .hours24,
        scheduledAt: scheduledAt
    )
    require(
        defaultSchedule.scheduledDeletionAt == scheduledAt.addingTimeInterval(86_400),
        "the default quarantine retention must schedule permanent deletion after 24 hours"
    )
    require(
        QuarantineCountdown(schedule: defaultSchedule, now: scheduledAt).state == .scheduled
            && QuarantineCountdown(schedule: defaultSchedule, now: scheduledAt).remainingSeconds == 86_400,
        "quarantine countdown must expose a transparent remaining duration"
    )
    let immediateSchedule = QuarantineSchedule(
        receiptID: receipt2.id,
        policy: .immediate,
        scheduledAt: scheduledAt
    )
    require(
        immediateSchedule.scheduledDeletionAt == scheduledAt
            && QuarantineCountdown(schedule: immediateSchedule, now: scheduledAt).state == .due,
        "immediate retention must become due at the moment it is scheduled"
    )
    try await scheduleStore.upsert(defaultSchedule)
    let persistedSchedule = try await scheduleStore.schedule(receiptID: receipt1.id)
    require(
        persistedSchedule == defaultSchedule,
        "quarantine schedule store must persist a receipt schedule"
    )
    let manualSchedule = defaultSchedule.rescheduled(policy: .manual, at: scheduledAt)
    require(
        QuarantineCountdown(schedule: manualSchedule, now: scheduledAt).state == .manual,
        "manual retention must be visibly distinct from an automatic countdown"
    )
    try await scheduleStore.upsert(manualSchedule)
    let manualDueSchedules = try await scheduleStore.dueSchedules(at: scheduledAt.addingTimeInterval(365 * 86_400))
    require(
        manualDueSchedules.isEmpty,
        "manual retention must never become automatically due"
    )
    let dueSchedule = manualSchedule.rescheduled(policy: .days2, at: scheduledAt)
    try await scheduleStore.upsert(dueSchedule)
    let dueSchedules = try await scheduleStore.dueSchedules(at: scheduledAt.addingTimeInterval(2 * 86_400))
    require(
        dueSchedules.map(\.receiptID) == [receipt1.id],
        "elapsed quarantine schedules must become due exactly at their deadline"
    )
    let failureReason = AutomaticCleanupFailureReason(
        code: .itemDeletionFailed,
        message: "fixture deletion failed",
        failedItemCount: 2
    )
    let failedSchedule = dueSchedule.recordingAttempt(
        at: scheduledAt.addingTimeInterval(2 * 86_400),
        failureReason: failureReason
    )
    try await scheduleStore.upsert(failedSchedule)
    let persistedFailureReason = try await scheduleStore.schedule(receiptID: receipt1.id)?.failureReason
    require(
        persistedFailureReason == failureReason,
        "automatic cleanup failures must persist a structured reason"
    )
    try await scheduleStore.remove(receiptID: receipt1.id)
    let removedSchedule = try await scheduleStore.schedule(receiptID: receipt1.id)
    require(
        removedSchedule == nil,
        "resolved receipts must remove their automatic deletion schedule"
    )

    let privateKey = Curve25519.Signing.PrivateKey()
    let rulesDirectory = root.appendingPathComponent("rules", isDirectory: true)
    let bundledURL = BundledCleanupRules.url
    let bundledStore = RuleStore(directory: root.appendingPathComponent("bundled-rules"), publicKey: privateKey.publicKey.rawRepresentation, bundledURL: bundledURL)
    let bundledPack = try await bundledStore.loadBundled()
    require(!bundledPack.rules.isEmpty, "bundled rule pack is empty")
    require(bundledPack.rules.allSatisfy { $0.sourceReference != nil && $0.testFixture != nil }, "bundled rules lack source or fixture provenance")
    let store = RuleStore(directory: rulesDirectory, publicKey: privateKey.publicKey.rawRepresentation)
    let pack1 = RulePack(version: "1", issuedAt: Date(timeIntervalSince1970: 1), rules: [], revokedRuleIDs: [])
    let data1 = try JSONEncoder().encode(pack1)
    try await store.install(update: SignedRuleUpdate(packData: data1, signature: try privateKey.signature(for: data1)))
    let before = try await store.currentVersion()
    let pack2 = RulePack(version: "2", issuedAt: Date(timeIntervalSince1970: 2), rules: [], revokedRuleIDs: [])
    let tampered = try JSONEncoder().encode(pack2)
    do {
        try await store.install(update: SignedRuleUpdate(packData: tampered, signature: Data(repeating: 0, count: 64)))
        require(false, "invalid rule signature unexpectedly installed")
    } catch is RuleStoreError {
        // Expected.
    }
    let after = try await store.currentVersion()
    require(after == before, "invalid update must keep current rules")

    let locallyTampered = RulePack(version: "999", issuedAt: Date(), rules: [], revokedRuleIDs: [])
    let stateURL = rulesDirectory.appendingPathComponent("state.json")
    var state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
    state["current"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(locallyTampered))
    try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
    do {
        _ = try await store.currentVersion()
        require(false, "locally modified rule pack bypassed signature verification")
    } catch is RuleStoreError {
        // Expected.
    }
}
