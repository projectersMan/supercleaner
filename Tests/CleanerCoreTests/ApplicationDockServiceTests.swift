import XCTest
@testable import CleanerCore

@MainActor final class ApplicationDockServiceTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Test App.app")
    private let copy = URL(fileURLWithPath: "/Users/test/Applications/Test App.app")

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dock-tests-\(UUID())")
    }
    private func candidate(_ url: URL, category: CleanupCategory = .application,
                           identity: FileIdentity = .init(device: 1, inode: 2, size: 1, modificationTime: 0, kind: .directory)) -> CleanupCandidate {
        .init(url: url, displayName: "Test", category: category, bytes: 1, risk: .review, evidence: [],
              identity: identity, source: .application, lastAccessDate: nil, isActive: false)
    }
    private func plan(_ candidates: [CleanupCandidate]) throws -> CleanupPlan {
        try PlanBuilder().build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
    }
    private func receipt(_ id: UUID, _ result: OperationResult) -> OperationReceipt {
        .init(id: id, planID: UUID(), startedAt: Date(), completedAt: Date(), results: [result])
    }
    private func removed(_ url: URL, status: OperationStatus = .succeeded, pending: Date? = nil) -> OperationResult {
        .init(candidateID: UUID(), originalURL: url, destinationURL: URL(fileURLWithPath: "/quarantine/Test App.app"),
              disposition: status == .succeeded ? .quarantined : .failed, status: status, bytes: 1, verificationNotBefore: pending)
    }
    private func restored(_ original: URL, destination: URL? = nil, status: OperationStatus = .restored) -> OperationResult {
        .init(candidateID: UUID(), originalURL: original, destinationURL: destination ?? original,
              disposition: .restored, status: status, bytes: 1)
    }

    func testExactPathOnlyAndFailedOrUnverifiedApplicationsKeepIcons() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences()
        try prefs.set("persistent-apps", [tile(app, 1), tile(copy, 2), spacer()])
        try prefs.set("recent-apps", [tile(app, 3), tile(copy, 4)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try await service.synchronize(receipt: receipt(id, removed(app, status: .failed)))
        try await service.synchronize(receipt: receipt(id, removed(app, pending: Date())))
        XCTAssertEqual(prefs.refreshes, 0)
        XCTAssertEqual(try prefs.tiles("persistent-apps").count, 3)
        try await service.synchronize(receipt: receipt(id, removed(app)))
        XCTAssertEqual(try prefs.paths("persistent-apps"), [copy.path])
        XCTAssertEqual(try prefs.tiles("persistent-apps").last?["tile-type"] as? String, "spacer-tile")
        XCTAssertEqual(try prefs.paths("recent-apps"), [copy.path])
        XCTAssertEqual(prefs.refreshes, 1)
        try await service.synchronize(receipt: receipt(id, removed(app)))
        XCTAssertEqual(prefs.refreshes, 1)
    }

    func testRelatedFilesOnlyAndReinstalledApplicationDoNotChangeDock() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences(); try prefs.set("persistent-apps", [tile(app, 1)])
        let related = candidate(URL(fileURLWithPath: "/Users/test/Library/Caches/Test"), category: .cache)
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in true })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([related]))
        try await service.synchronize(receipt: receipt(id, removed(related.url)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try await service.synchronize(receipt: receipt(id, removed(app)))
        XCTAssertEqual(prefs.refreshes, 0)
        XCTAssertEqual(try prefs.paths("persistent-apps"), [app.path])
    }

    func testRestoreAfterRestartMergesCurrentOrderAndDoesNotDuplicate() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences()
        let first = URL(fileURLWithPath: "/Applications/First.app")
        let new = URL(fileURLWithPath: "/Applications/New.app")
        try prefs.set("persistent-apps", [tile(first, 1), tile(app, 2), tile(copy, 3)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try await service.synchronize(receipt: receipt(id, removed(app)))
        try prefs.set("persistent-apps", [tile(new, 4), tile(copy, 3), tile(first, 1)])
        let reopened = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in true })
        try await reopened.synchronize(receipt: receipt(id, restored(app)))
        XCTAssertEqual(try prefs.paths("persistent-apps"), [new.path, app.path, copy.path, first.path])
        XCTAssertNil((try prefs.tiles("persistent-apps")[1]["tile-data"] as? [String: Any])?["book"])
        try await reopened.synchronize(receipt: receipt(id, restored(app)))
        XCTAssertEqual(prefs.refreshes, 2)
        XCTAssertEqual(try prefs.paths("persistent-apps").filter { $0 == app.path }.count, 1)
    }

    func testRestoreConflictRetargetsShortcutAndPreservesExistingCopy() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences(); try prefs.set("persistent-apps", [tile(app, 1)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try await service.synchronize(receipt: receipt(id, removed(app)))
        try prefs.set("persistent-apps", [tile(app, 1)])
        let destination = URL(fileURLWithPath: "/Applications/Test App-restored.app")
        let reopened = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in true })
        try await reopened.synchronize(receipt: receipt(id, restored(app, destination: destination, status: .restoreConflict)))
        XCTAssertEqual(Set(try prefs.paths("persistent-apps")), [app.path, destination.path])
        let guids = try prefs.tiles("persistent-apps").compactMap { ($0["GUID"] as? NSNumber)?.stringValue }
        XCTAssertEqual(Set(guids).count, 2)
    }

    func testFinderRetargetedTileIsRemovedBySavedIdentityOnly() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences(); try prefs.set("persistent-apps", [tile(app, 1)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID(), result = removed(app)
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try prefs.set("persistent-apps", [tile(result.destinationURL!, 1), tile(result.destinationURL!, 2)])
        try await service.synchronize(receipt: receipt(id, result))
        XCTAssertEqual(try prefs.tiles("persistent-apps").count, 1)
        XCTAssertEqual(try prefs.tiles("persistent-apps").first?["GUID"] as? Int, 2)
    }

    func testConcurrentChangeAndPartialWriteCanRetryWithoutLosingOtherTiles() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences()
        try prefs.set("persistent-apps", [tile(app, 1), tile(copy, 2)])
        try prefs.set("recent-apps", [tile(app, 3)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        prefs.setFailureKey("recent-apps")
        do { try await service.synchronize(receipt: receipt(id, removed(app))); XCTFail("must report failed write") }
        catch { XCTAssertTrue(error is ApplicationDockError) }
        XCTAssertEqual(try prefs.paths("persistent-apps"), [copy.path])
        XCTAssertEqual(try prefs.paths("recent-apps"), [app.path])
        prefs.setFailureKey(nil)
        let reopened = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        try await reopened.synchronize(receipt: receipt(id, removed(app)))
        XCTAssertEqual(try prefs.paths("persistent-apps"), [copy.path])
        XCTAssertEqual(try prefs.paths("recent-apps"), [])
        XCTAssertEqual(prefs.refreshes, 1)
    }

    func testFailedRestoreAndManuallyRestoredTileAreNotDuplicated() async throws {
        let folder = root(); defer { try? FileManager.default.removeItem(at: folder) }
        let prefs = FakeDockPreferences(); try prefs.set("persistent-apps", [tile(app, 1)])
        let service = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in false })
        let id = UUID()
        try await service.prepare(receiptID: id, plan: plan([candidate(app)]))
        try await service.synchronize(receipt: receipt(id, removed(app)))
        let reopened = ApplicationDockService(directory: folder, preferences: prefs, exists: { _ in true })
        try await reopened.synchronize(receipt: receipt(id, restored(app, status: .failed)))
        XCTAssertEqual(try prefs.paths("persistent-apps"), [])
        try prefs.set("persistent-apps", [tile(app, 99)])
        try await reopened.synchronize(receipt: receipt(id, restored(app)))
        XCTAssertEqual(try prefs.tiles("persistent-apps").count, 1)
        XCTAssertEqual(try prefs.tiles("persistent-apps")[0]["GUID"] as? Int, 99)
        XCTAssertEqual(prefs.refreshes, 1)
    }

    func testCoordinatorExecutesAndRestoresDockWithActualFileMove() async throws {
        try await coordinatorScenario(writeFails: false)
    }

    func testCoordinatorReportsDockFailureWithoutFailingFileOperationAndRetriesAfterRestart() async throws {
        try await coordinatorScenario(writeFails: true)
    }

    private func coordinatorScenario(writeFails: Bool) async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".dock-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let target = home.appendingPathComponent("Applications/Test.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: target.appendingPathComponent("test.txt"))
        let fs = LocalFileSystem()
        let item = candidate(target, identity: try await fs.identity(at: target))
        let cleanupPlan = try plan([item])
        let prefs = FakeDockPreferences(); try prefs.set("persistent-apps", [tile(target, 1)])
        let dock = ApplicationDockService(directory: home.appendingPathComponent("Dock"), preferences: prefs)
        let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: cleanupPlan.ruleVersion)
        let history = HistoryStore(url: home.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: home.appendingPathComponent("schedules.json"))
        let resolutions = ResolutionJournalStore(url: home.appendingPathComponent("resolutions.json"))
        let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules, executor: executor, resolutionJournalStore: resolutions)
        let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history,
            journalStore: ExecutionJournalStore(url: home.appendingPathComponent("journal.json")),
            resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance,
            now: Date.init, dockService: dock)
        if writeFails { prefs.setFailureKey("persistent-apps") }
        let receipt = try await coordinator.execute(plan: cleanupPlan, retentionPolicy: .manual)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        XCTAssertEqual(receipt.overallStatus, .completed)
        if writeFails {
            XCTAssertEqual(receipt.integrationWarnings?.count, 1)
            XCTAssertEqual(try prefs.paths("persistent-apps"), [target.path])
            prefs.setFailureKey(nil)
            _ = try await coordinator.recoverPendingExecutions()
        } else { XCTAssertNil(receipt.integrationWarnings) }
        XCTAssertEqual(try prefs.paths("persistent-apps"), [])
        if writeFails { prefs.setFailureKey("persistent-apps") }
        let result = try await coordinator.restore(receipt: receipt)
        XCTAssertEqual(result.results.first?.status, .restored)
        if writeFails {
            XCTAssertEqual(result.integrationWarnings?.count, 1)
            XCTAssertEqual(try prefs.paths("persistent-apps"), [])
            prefs.setFailureKey(nil)
            _ = try await coordinator.recoverPendingExecutions()
        } else { XCTAssertNil(result.integrationWarnings) }
        XCTAssertEqual(try prefs.paths("persistent-apps"), [target.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(prefs.refreshes, 2)
    }

    func testReceiptWarningsAreBackwardCompatibleAndSurviveResolution() throws {
        let result = removed(app)
        let receipt = receipt(UUID(), result)
        let legacy = try JSONEncoder().encode(receipt)
        XCTAssertNil(try JSONDecoder().decode(OperationReceipt.self, from: legacy).integrationWarnings)
        let warned = receipt.addingIntegrationWarning("warning").addingIntegrationWarning("warning")
        XCTAssertEqual(warned.integrationWarnings, ["warning"])
        XCTAssertEqual(warned.applying(resolutionResults: []).integrationWarnings, ["warning"])
    }

    private func tile(_ url: URL, _ guid: Int) -> [String: Any] {
        ["GUID": guid, "tile-type": "file-tile", "tile-data": [
            "file-data": ["_CFURLString": url.absoluteString + (url.absoluteString.hasSuffix("/") ? "" : "/"), "_CFURLStringType": 15],
            "file-label": "Test", "book": Data("old bookmark".utf8), "custom-field": "preserve"]]
    }
    private func spacer() -> [String: Any] { ["tile-type": "spacer-tile", "GUID": 999] }
}

private final class FakeDockPreferences: DockPreferencesAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [String: Data]()
    private var failureKey: String?
    private var refreshCount = 0
    var refreshes: Int { lock.withLock { refreshCount } }
    func setFailureKey(_ key: String?) { lock.withLock { failureKey = key } }
    func read(_ key: String) throws -> Data? { lock.withLock { values[key] } }
    func replace(_ key: String, expected: Data?, value: Data) throws {
        try lock.withLock {
            guard failureKey != key, values[key] == expected else { throw ApplicationDockError.preferencesChanged }
            values[key] = value
        }
    }
    func refresh() throws { lock.withLock { refreshCount += 1 } }
    func set(_ key: String, _ tiles: [[String: Any]]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: tiles, format: .binary, options: 0)
        lock.withLock { values[key] = data }
    }
    func tiles(_ key: String) throws -> [[String: Any]] {
        guard let data = try read(key) else { return [] }
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]])
    }
    func paths(_ key: String) throws -> [String] {
        try tiles(key).compactMap {
            guard let data = $0["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
                  let text = file["_CFURLString"] as? String else { return nil }
            return URL(string: text)?.standardizedFileURL.path
        }
    }
}
