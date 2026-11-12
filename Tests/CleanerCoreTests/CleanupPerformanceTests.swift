import XCTest
@testable import CleanerCore

final class CleanupPerformanceTests: XCTestCase {
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".cleanup-performance-\(UUID())")
    }
    func testRuleEntryLimitDoesNotBlockCompleteCache() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Test")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for i in 0..<12 { try Data([1]).write(to: cache.appendingPathComponent("\(i)")) }
        let rule = CleanupRule(ruleID: "cache-test", category: .cache, relativePaths: ["Library/Caches"], minimumAgeDays: 0,
            defaultRisk: .safe, maximumDepth: 8, maximumEntries: 1)
        let found = try await CleanupRuleEngine(pack: .init(version: "test", issuedAt: Date(), rules: [rule], revokedRuleIDs: []))
            .scan(context: .init(homeDirectory: home))
        XCTAssertEqual(found.first?.risk, .safe)
        XCTAssertEqual(found.first?.bytes, 12)
    }
    func testDeepRegenerableCacheIsRecommendedAndCredentialsStayBlocked() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Test")
        let leaf = (0..<80).reduce(cache) { $0.appendingPathComponent("level-\($1)") }
        try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
        try Data([1]).write(to: leaf.appendingPathComponent("cache.bin"))
        let engine = CleanupRuleEngine(pack: try BundledCleanupRules.pack())
        let context = ScanContext(homeDirectory: home, activePaths: [cache])
        let found = try await engine.scan(context: context)
        let candidate = try XCTUnwrap(found.first { $0.url.path == cache.path })
        XCTAssertNotEqual(candidate.risk, .blocked)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: candidate), .recommended)
        try Data([2]).write(to: leaf.appendingPathComponent("credentials.json"))
        let protected = try await engine.scan(context: context)
        XCTAssertEqual(protected.first { $0.url.path == cache.path }?.risk, .blocked)
    }
    func testScannedCacheExecutionDoesNotWalkContentsAgain() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Test")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for i in 0..<30 { try Data([1]).write(to: cache.appendingPathComponent("\(i)")) }
        let fs = CountingCleanupFileSystem()
        let context = ScanContext(homeDirectory: home, fileSystem: fs)
        let engine = CleanupRuleEngine(pack: try BundledCleanupRules.pack())
        let found = try await engine.scan(context: context)
        let candidate = try XCTUnwrap(found.first { $0.url.path == cache.path })
        await fs.reset()
        try await engine.validateForExecution(candidate, context: context)
        let reads = await fs.directoryReads
        XCTAssertEqual(reads, 0, "a verified cache requires no recursive inspection at deletion")
        try Data([2]).write(to: cache.appendingPathComponent("auth.json"))
        do { try await engine.validateForExecution(candidate, context: context); XCTFail("new top-level credential must stay protected") }
        catch { }
    }
    func testFullExecutionReusesScanAndPreservesRecovery() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/Test")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: cache.appendingPathComponent("payload"))
        let fs = CountingCleanupFileSystem()
        let runtime = CleanupRuntime(home: home, fileSystem: fs)
        let configuration = try await runtime.configuration(includeProcessActivity: false)
        let scanned = try await CleanupRuleEngine(pack: configuration.pack).scan(context: configuration.context)
        let candidate = try XCTUnwrap(scanned.first { $0.url.path == cache.path })
        let plan = try PlanBuilder(ruleVersion: configuration.pack.executionVersion).build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: plan.ruleVersion,
            validateCandidate: { try await runtime.validateForExecution($0) },
            prepareValidationBatch: { try await runtime.prepareExecutionValidationBatch(candidates: $0) },
            finalCandidateCheck: { try await runtime.validateImmediatelyBeforeMove($0) })
        await fs.reset()
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        let reads = await fs.directoryReadURLs
        XCTAssertFalse(reads.contains { $0.path == cache.path || $0.path.hasPrefix(cache.path + "/") },
            "live checks may inspect input-method installation roots, never the scanned cache contents again")
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent("payload")), Data([1, 2, 3]))
    }

    func testAppBodyValidationDoesNotRediscoverInstalledApplications() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/Fast.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.fast", "CFBundleName": "Fast"],
            format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let fs = CountingCleanupFileSystem()
        let candidate = CleanupCandidate(url: app, displayName: "Fast", category: .application, bytes: 1, risk: .review,
            evidence: [.init(code: "owner-bundle", summary: app.path), .init(code: "owner-bundle-id", summary: "test.fast"),
                       .init(code: "owner-name", summary: "Fast")], identity: try await fs.identity(at: app),
            source: .application, lastAccessDate: nil, isActive: false)
        try await ApplicationExecutionValidator().validate(candidate, context: .init(homeDirectory: home, fileSystem: fs))
        let reads = await fs.directoryReads
        XCTAssertEqual(reads, 0)
        do {
            try await ApplicationExecutionValidator().validate(candidate,
                context: .init(homeDirectory: home, fileSystem: fs, runningBundleIdentifiers: ["test.fast"]))
            XCTFail("a restarted app must remain blocked")
        } catch ApplicationExecutionRejection.ownershipChanged { }
    }

    func testReconciliationPerformanceAndPathBoundaries() {
        let now = Date(), base = "/Users/test/Library/Caches/Cache"
        let candidates = (0..<2500).map { i in CleanupCandidate(url: URL(fileURLWithPath: base + "\(i)/file"),
            displayName: "item", category: .cache, bytes: 1, risk: .review, evidence: [],
            identity: .init(device: 1, inode: UInt64(i+1), size: 1, modificationTime: 0, kind: .file), source: .general, lastAccessDate: nil, isActive: false) }
        let report = SystemScanReport(metadata: .init(startedAt: now, completedAt: now, rulesetVersion: "test"), modules: [:],
            generalCandidates: candidates, applicationInventory: .init(applications: [], coverage: .init(), scannedAt: now),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: now), largeFileCandidates: [], agentAssets: [])
        let results = (0..<40).map { i in OperationResult(candidateID: UUID(), originalURL: URL(fileURLWithPath: base + "\(i)"), disposition: .quarantined, bytes: 1) }
        let start = Date()
        let updated = report.reconcilingCleanup(results)
        let elapsed = Date().timeIntervalSince(start)
        print("Cleanup reconciliation: 2500 rows / 40 removals = \(elapsed)s")
        XCTAssertEqual(updated.generalCandidates.count, 2460)
        XCTAssertTrue(updated.generalCandidates.contains { $0.url.path == base + "400/file" })
        XCTAssertLessThan(elapsed, 1.0, "UI reconciliation should finish without file-system path checks for every pair")
    }
}

private actor CountingCleanupFileSystem: FileSystemAccess {
    private let base = LocalFileSystem()
    private(set) var directoryReads = 0
    private(set) var directoryReadURLs: [URL] = []
    func reset() { directoryReads = 0; directoryReadURLs = [] }
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func children(of url: URL) async throws -> [URL] { directoryReads += 1; directoryReadURLs.append(url); return try await base.children(of: url) }
    func isReadable(_ url: URL) async -> Bool { await base.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
