import CleanerCore
import Foundation

/// Real, isolated files reproduce logs that grow after scanning and remain open
/// across a rename. No installed application's actual logs are modified.
func runChangingLogExecutionContracts() async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("ChangingLogs-" + UUID().uuidString).standardizedFileURL.resolvingSymlinksInPath()
    try manager.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    let pack = try BundledCleanupRules.pack()
    let engine = CleanupRuleEngine(pack: pack)
    let local = LocalFileSystem()
    let context = ScanContext(homeDirectory: home)
    func fixture(_ name: String) async throws -> (URL, CleanupCandidate, CleanupPlan) {
        let url = home.appendingPathComponent("Library/Logs/" + name + ".log")
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("scanned\n".utf8).write(to: url)
        let candidates = try await engine.scan(context: context)
        guard let scanned = candidates.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) else {
            throw FileSystemError.missing(url)
        }
        // macOS may enumerate a /var fixture as /private/var. Keep the fixture
        // spelling canonical, like the user's /Users/.../Library/Logs path, so
        // this contract isolates content changes from path-alias handling.
        let candidate = CleanupCandidate(id: scanned.id, url: scanned.url.standardizedFileURL,
            displayName: scanned.displayName, category: scanned.category, bytes: scanned.bytes, risk: scanned.risk,
            evidence: scanned.evidence, identity: scanned.identity, source: scanned.source,
            lastAccessDate: scanned.lastAccessDate, isActive: scanned.isActive, ruleID: scanned.ruleID,
            defaultSelection: scanned.defaultSelection)
        require(candidate.ruleID == "general.logs" && candidate.category == .log && candidate.source == .general,
                "the regression must use an actual bundled log-rule candidate")
        let plan = try PlanBuilder(ruleVersion: pack.version, protectionPolicy: .init(homeDirectory: home))
            .build(candidates: [candidate], selectedIDs: [candidate.id])
        return (url, candidate, plan)
    }
    func executor(_ fs: any FileSystemAccess = LocalFileSystem(), now: @escaping @Sendable () -> Date = Date.init) -> CleanupExecutor {
        .init(fileSystem: fs, pathPolicy: .init(homeDirectory: home), quarantineRoot: home.appendingPathComponent("quarantine"),
              currentRuleVersion: pack.version, now: now, loadProtection: { ProtectionPolicy(homeDirectory: home) },
              validateCandidate: { try await engine.validateForExecution($0, context: context) })
    }

    let (url, candidate, plan) = try await fixture("appending")
    let writer = try FileHandle(forWritingTo: url)
    defer { try? writer.close() }
    try writer.seekToEnd()
    try writer.write(contentsOf: Data("appended after scan\n".utf8))
    let changed = try await local.identity(at: url)
    require(changed.inode == candidate.identity.inode && changed.size > candidate.identity.size,
            "the reproducer must change log contents while preserving the file object")
    let receipt = await executor().execute(plan: plan)
    require(receipt.results.first?.status == .succeeded,
            "a bundled regular log that only grew after scanning must be quarantined instead of repeatedly skippedIdentityChanged; result=\(String(describing: receipt.results.first)) rejection=\(String(describing: receipt.rejectionReason))")
    guard let destination = receipt.results.first?.destinationURL else { throw FileSystemError.missing(url) }
    require(receipt.results.first?.bytes == changed.size,
            "log cleanup records the actual moved file size, including post-scan writes")
    try writer.write(contentsOf: Data("written through the open descriptor after quarantine\n".utf8))
    let interrupted = ExecutionJournalEntry(id: receipt.id, plan: plan, startedAt: receipt.startedAt, retentionPolicy: .hours24)
    let recovered = await executor().recoverInterruptedExecution(interrupted)
    require(recovered.results.first?.status == .succeeded,
            "restart reconciliation must recognize the same quarantined log after continued writes")
    let restore = await executor().restore(receipt: receipt)
    require(restore.results.first?.status == .restored,
            "an appended quarantined log remains recoverable")
    let restoredContents = try String(contentsOf: url, encoding: .utf8)
    require(restoredContents.contains("appended after scan") && restoredContents.contains("open descriptor"),
            "recovery must retain writes made before and after quarantine")
    require(!manager.fileExists(atPath: destination.path), "recovery consumes the retained source")

    // Writing and creating a replacement immediately after rename are separate
    // from a pre-delete rotation: the old inode was successfully removed.
    let (liveURL, _, livePlan) = try await fixture("live")
    let liveWriter = try FileHandle(forWritingTo: liveURL)
    defer { try? liveWriter.close() }
    try liveWriter.seekToEnd()
    let writingFS = ChangingLogFileSystem(source: liveURL, writer: liveWriter, recreate: true)
    let liveExecutor = executor(writingFS)
    let liveReceipt = await liveExecutor.execute(plan: livePlan)
    require(liveReceipt.results.first?.status == .succeeded,
            "writes during rename and a newly generated log at the original path must not make the old log's move fail")
    let newLogContents = try String(contentsOf: liveURL, encoding: .utf8)
    require(newLogContents == "new log\n",
            "cleanup must preserve a log newly created after the selected inode moved")
    let liveRecovered = await liveExecutor.recoverInterruptedExecution(
        .init(id: liveReceipt.id, plan: livePlan, startedAt: liveReceipt.startedAt, retentionPolicy: .hours24))
    require(liveRecovered.results.first?.status == .succeeded,
            "recovery recognizes the old inode even if a different regular log now occupies the original path")
    let liveRestored = await liveExecutor.restore(receipt: liveReceipt)
    require(liveRestored.results.first?.status == .restoreConflict,
            "restoring an open log never overwrites the new original-path log")

    let (preparingURL, _, preparingPlan) = try await fixture("replaced-during-preparation")
    let preparingWriter = try FileHandle(forWritingTo: preparingURL)
    defer { try? preparingWriter.close() }
    let preparingFS = ChangingLogFileSystem(source: preparingURL, writer: preparingWriter, recreate: false, replaceDuringPreparation: true)
    let preparingReceipt = await executor(preparingFS).execute(plan: preparingPlan)
    require(preparingReceipt.results.first?.status == .skippedIdentityChanged,
            "replacement during asynchronous quarantine preparation must be caught before moving")
    let preparingContents = try String(contentsOf: preparingURL, encoding: .utf8)
    require(preparingContents == "replacement during preparation\n", "late replacement remains untouched")

    let (expiringURL, _, expiringPlan) = try await fixture("expiring")
    let expiringWriter = try FileHandle(forWritingTo: expiringURL)
    defer { try? expiringWriter.close() }
    let clock = ChangingLogClock(expiringPlan.createdAt)
    let expiringFS = ChangingLogFileSystem(source: expiringURL, writer: expiringWriter, recreate: false,
        onPreparedIdentity: { clock.set(expiringPlan.expiresAt.addingTimeInterval(1)) })
    let expiringReceipt = await executor(expiringFS, now: { clock.get() }).execute(plan: expiringPlan)
    require(expiringReceipt.results.first?.status == .skippedProtected && manager.fileExists(atPath: expiringURL.path),
            "expiry during the final mutable-log identity read must prevent movement")

    let (cancelURL, _, cancelPlan) = try await fixture("cancelled")
    let cancelWriter = try FileHandle(forWritingTo: cancelURL)
    defer { try? cancelWriter.close() }
    let cancelFS = ChangingLogFileSystem(source: cancelURL, writer: cancelWriter, recreate: false,
        onPreparedIdentity: { withUnsafeCurrentTask { $0?.cancel() } })
    let cancelExecutor = executor(cancelFS)
    let cancelled = await Task { await cancelExecutor.execute(plan: cancelPlan) }.value
    require(cancelled.results.first?.status == .skippedCancelled && manager.fileExists(atPath: cancelURL.path),
            "cancellation during the final mutable-log identity read must prevent movement")

    let (rotatedURL, _, rotatedPlan) = try await fixture("rotated")
    let oldURL = rotatedURL.appendingPathExtension("old")
    try manager.moveItem(at: rotatedURL, to: oldURL)
    try Data("replacement must stay\n".utf8).write(to: rotatedURL)
    let rotated = await executor().execute(plan: rotatedPlan)
    require(rotated.results.first?.status == .skippedIdentityChanged,
            "rotation before cleanup must reject the replacement inode")
    let rotatedContents = try String(contentsOf: rotatedURL, encoding: .utf8)
    require(rotatedContents == "replacement must stay\n",
            "the replacement log cannot be moved on the old scan's authority")

    let (linkURL, _, linkPlan) = try await fixture("linked")
    let target = home.appendingPathComponent("unselected-data")
    try Data("unselected".utf8).write(to: target)
    try manager.removeItem(at: linkURL)
    try manager.createSymbolicLink(at: linkURL, withDestinationURL: target)
    let linked = await executor().execute(plan: linkPlan)
    require(linked.results.first?.status != .succeeded && manager.fileExists(atPath: target.path),
            "a symlink substituted for a log cannot gain deletion eligibility")

    // Generic cache files and directories can change normally after scanning.
    // Reinspect directory contents, but never grant authority over a replacement.
    let cacheContext = ScanContext(homeDirectory: home, enforcesEntryBudgets: false)
    let runtime = CleanupRuntime(home: home)
    let cacheExecutor = CleanupExecutor(fileSystem: local, pathPolicy: .init(homeDirectory: home),
        quarantineRoot: home.appendingPathComponent("quarantine"), currentRuleVersion: pack.executionVersion,
        validateCandidate: { try await runtime.validateForExecution($0) },
        prepareValidationBatch: { try await runtime.prepareExecutionValidationBatch(candidates: $0) })
    for scenario in ["file", "directory", "protected", "replacement", "many"] {
        let cacheURL = home.appendingPathComponent("Library/Caches/" + scenario)
        try manager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if scenario == "file" { try Data("cache".utf8).write(to: cacheURL) }
        else { try manager.createDirectory(at: cacheURL, withIntermediateDirectories: true) }
        if scenario == "many" {
            // The GUI scan has no entry cap; execution must honor the same scope.
            for index in 0..<20_001 {
                _ = manager.createFile(atPath: cacheURL.appendingPathComponent(String(index)).path, contents: Data())
            }
        }
        let scanned = try await engine.scan(context: cacheContext)
        let found = scanned.first { $0.url.standardizedFileURL.path == cacheURL.standardizedFileURL.path }!
        let cache = CleanupCandidate(url: found.url.standardizedFileURL, displayName: found.displayName,
            category: found.category, bytes: found.bytes, risk: found.risk, evidence: found.evidence,
            identity: found.identity, source: found.source, lastAccessDate: found.lastAccessDate,
            isActive: found.isActive, ruleID: found.ruleID, defaultSelection: found.defaultSelection,
            requiresExplicitSelection: found.requiresExplicitSelection)
        require(cache.risk != .blocked, "complete cache scan must be selectable")
        let cachePlan = try PlanBuilder(ruleVersion: pack.executionVersion, protectionPolicy: .init(homeDirectory: home))
            .build(candidates: [cache], selectedIDs: [cache.id])
        if scenario == "file" {
            let handle = try FileHandle(forWritingTo: cacheURL)
            try handle.seekToEnd(); try handle.write(contentsOf: Data("updated".utf8)); try handle.close()
        } else if scenario == "replacement" {
            try manager.moveItem(at: cacheURL, to: cacheURL.appendingPathExtension("old"))
            try manager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        } else {
            try Data("new".utf8).write(to: cacheURL.appendingPathComponent(scenario == "protected" ? "auth.json" : "new-cache"))
        }
        let result = await cacheExecutor.execute(plan: cachePlan)
        let expected: OperationStatus = scenario == "protected" ? .skippedProtected
            : scenario == "replacement" ? .skippedIdentityChanged : .succeeded
        require(result.results.first?.status == expected, "cache \(scenario): \(String(describing: result.results.first))")
        if expected == .succeeded {
            let restored = await cacheExecutor.restore(receipt: result)
            require(restored.results.first?.status == .restored, "changed cache must remain recoverable")
        } else {
            require(manager.fileExists(atPath: cacheURL.path), "refused cache remains untouched")
        }
    }

    // Keep this identity regression inside the allowed personal-file scope so
    // runtime-directory protection does not reject it before the identity check.
    let ordinaryURL = home.appendingPathComponent("Downloads/ordinary.txt")
    try manager.createDirectory(at: ordinaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("scanned\n".utf8).write(to: ordinaryURL)
    let ordinaryIdentity = try await local.identity(at: ordinaryURL)
    let ordinary = CleanupCandidate(url: ordinaryURL, displayName: "ordinary", category: .largeFile, bytes: ordinaryIdentity.size,
        risk: .review, evidence: [], identity: ordinaryIdentity, source: .diskAnalysis, lastAccessDate: nil, isActive: false)
    let ordinaryPlan = try PlanBuilder(ruleVersion: pack.version, protectionPolicy: .init(homeDirectory: home))
        .build(candidates: [ordinary], selectedIDs: [ordinary.id])
    try Data("changed ordinary file\n".utf8).write(to: ordinaryURL)
    let strict = await executor().execute(plan: ordinaryPlan)
    require(strict.results.first?.status == .succeeded,
            "explicit ordinary large-file cleanup tolerates content changes on the same object")
    print("PASS: growing/open logs, changing caches, 20k+ directory execution, protected/replaced objects, restart reconciliation and recoverable cleanup")
}

private actor ChangingLogFileSystem: FileSystemAccess {
    private let local = LocalFileSystem()
    let source: URL
    let writer: FileHandle
    let recreate: Bool
    private var replaceDuringPreparation: Bool
    private let onPreparedIdentity: @Sendable () -> Void
    private var prepared = false
    init(source: URL, writer: FileHandle, recreate: Bool, replaceDuringPreparation: Bool = false,
         onPreparedIdentity: @escaping @Sendable () -> Void = {}) {
        self.source = source; self.writer = writer; self.recreate = recreate
        self.replaceDuringPreparation = replaceDuringPreparation
        self.onPreparedIdentity = onPreparedIdentity
    }
    func identity(at url: URL) async throws -> FileIdentity {
        if prepared && url.standardizedFileURL.path == source.standardizedFileURL.path { onPreparedIdentity() }
        return try await local.identity(at: url)
    }
    func children(of url: URL) async throws -> [URL] { try await local.children(of: url) }
    func isReadable(_ url: URL) async -> Bool { await local.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await local.isWritable(url) }
    func fileExists(_ url: URL) async -> Bool { await local.fileExists(url) }
    func readData(at url: URL, maximumBytes: Int) async throws -> Data { try await local.readData(at: url, maximumBytes: maximumBytes) }
    func createDirectory(_ url: URL) async throws {
        try await local.createDirectory(url)
        prepared = true
        if replaceDuringPreparation {
            replaceDuringPreparation = false
            try FileManager.default.moveItem(at: source, to: source.appendingPathExtension("old"))
            try Data("replacement during preparation\n".utf8).write(to: source)
        }
    }
    func removeEmptyDirectory(_ url: URL) async throws { try await local.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await local.trash(url) }
    func move(_ source: URL, to destination: URL) async throws {
        try await local.move(source, to: destination)
        try writer.write(contentsOf: Data("appended during move\n".utf8))
        if recreate && source.standardizedFileURL.path == self.source.standardizedFileURL.path {
            try Data("new log\n".utf8).write(to: source)
        }
    }
}

private final class ChangingLogClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func get() -> Date { lock.withLock { value } }
    func set(_ date: Date) { lock.withLock { value = date } }
}
