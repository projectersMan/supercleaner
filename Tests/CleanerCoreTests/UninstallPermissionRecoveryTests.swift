import Foundation
import XCTest
@testable import CleanerCore

final class UninstallPermissionRecoveryTests: XCTestCase {
    func testActualReadOnlyBundleMoveDoesNotSendUserBackToAppManagement() async throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent("permission-real-move-\(UUID())")
        let app = home.appendingPathComponent("Applications/Permission-Fixture.app")
        try manager.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer {
            try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.path)
            try? manager.removeItem(at: home)
        }
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.path)
        let fs = LocalFileSystem()
        let candidate = CleanupCandidate(url: app, displayName: "Permission fixture", category: .application,
            bytes: 0, risk: .review, evidence: [], identity: try await fs.identity(at: app),
            source: .application, lastAccessDate: nil, isActive: false)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture")
        let receipt = await executor.execute(plan: plan, permissionRecovery: { request in
            XCTAssertNil(request.settingsURL, "EACCES cannot be fixed by opening App Management again")
            // Only this disposable user-owned fixture may have its mode changed.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.path)
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded])
        XCTAssertFalse(manager.fileExists(atPath: app.path))
    }

    func testPermissionClassificationDoesNotConfusePolicyOrConnectionFailuresWithAuthorization() {
        let wrapped = NSError(domain: "wrapper", code: 999,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
        XCTAssertTrue(UninstallPermissionRequest.isPermissionDenied(wrapped))
        XCTAssertTrue(UninstallPermissionRequest.isPermissionDenied(HelperClientError.rejected(.authorizationRequired)))
        XCTAssertFalse(UninstallPermissionRequest.isPermissionDenied(HelperClientError.unavailable))
        XCTAssertFalse(UninstallPermissionRequest.isPermissionDenied(HelperClientError.rejected(.identityMismatch)))
        XCTAssertFalse(UninstallPermissionRequest.isPermissionDenied(HelperMutationUncertain()))
    }

    func testStopWhilePromptedPersistsManualRetentionAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("permission-stop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let fs = PermissionFileSystem()
        let executor = CleanupExecutor(fileSystem: fs, quarantineRoot: root.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture")
        let fixture = PermissionFixture(fs: fs, executor: executor)
        let history = HistoryStore(url: root.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedule.json"))
        let resolutions = ResolutionJournalStore(url: root.appendingPathComponent("resolutions.json"))
        let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules,
            executor: executor, resolutionJournalStore: resolutions)
        let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history,
            journalStore: ExecutionJournalStore(url: root.appendingPathComponent("journal.json")),
            resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance, now: Date.init)
        let receipt = try await Task {
            try await coordinator.execute(plan: fixture.plan, retentionPolicy: .immediate,
                progress: { _ in }, permissionRecovery: { _ in .stop })
        }.value
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedCancelled, .skippedCancelled])
        let persisted = try await history.receipt(id: receipt.id)
        XCTAssertEqual(persisted, receipt)
        let schedule = try await schedules.schedule(receiptID: receipt.id)
        XCTAssertEqual(schedule?.policy, .manual)
        _ = try await coordinator.recoverPendingExecutions()
        _ = try await coordinator.processDue(at: Date().addingTimeInterval(86_400))
        let attempts = await fs.attempts
        XCTAssertEqual(attempts, [fixture.first.url, fixture.blocked.url])
        let afterRestart = try await history.receipt(id: receipt.id)
        XCTAssertEqual(afterRestart?.results.first?.disposition, .quarantined)
    }

    func testGrantResumesSamePlanWithoutRepeatingCompletedItems() async throws {
        let fixture = PermissionFixture()
        let receipt = await fixture.executor.execute(plan: fixture.plan, permissionRecovery: { request in
            XCTAssertEqual(request.url, fixture.blocked.url)
            XCTAssertEqual(request.attempt, 1)
            XCTAssertTrue(request.isApplicationBundle)
            XCTAssertEqual(request.settingsURL, PermissionStatusService.appManagementSettingsURL)
            let attempts = await fixture.fs.attempts
            XCTAssertEqual(attempts, [fixture.first.url, fixture.blocked.url])
            await fixture.fs.allow()
            return .retry
        })
        XCTAssertEqual(receipt.planID, fixture.plan.id)
        XCTAssertEqual(receipt.results.count, 3)
        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .succeeded })
        let attempts = await fixture.fs.attempts
        XCTAssertEqual(attempts, [fixture.first.url, fixture.blocked.url, fixture.blocked.url, fixture.last.url])
    }

    func testStillDeniedWaitsForAnotherUserDecisionThenStopRetainsRemainder() async {
        let fixture = PermissionFixture()
        let receipt = await Task {
            await fixture.executor.execute(plan: fixture.plan, permissionRecovery: { request in
                request.attempt == 1 ? .retry : .stop
            })
        }.value
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedCancelled, .skippedCancelled])
        let attempts = await fixture.fs.attempts
        XCTAssertEqual(attempts, [fixture.first.url, fixture.blocked.url, fixture.blocked.url])
    }

    func testReplacementWhileSettingsOpenIsNeverDeleted() async {
        let fixture = PermissionFixture()
        let receipt = await fixture.executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            await fixture.fs.replaceBlocked()
            await fixture.fs.allow()
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedIdentityChanged, .succeeded])
        let attempts = await fixture.fs.attempts
        XCTAssertEqual(attempts.filter { $0 == fixture.blocked.url }.count, 1)
    }

    func testApplicationStartedWhileSettingsOpenIsNeverDeleted() async {
        let fs = PermissionFileSystem()
        let executor = CleanupExecutor(fileSystem: fs, quarantineRoot: URL(fileURLWithPath: "/fixture-quarantine"),
            currentRuleVersion: "fixture", isActive: { await fs.active($0) })
        let fixture = PermissionFixture(fs: fs, executor: executor)
        let receipt = await executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            await fs.startBlockedApplication()
            await fs.allow()
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedActive, .succeeded])
        let attempts = await fs.attempts
        XCTAssertEqual(attempts.filter { $0 == fixture.blocked.url }.count, 1)
    }

    func testExpiredPlanAfterPermissionChangeDoesNotResumeMoves() async {
        let clock = PermissionClock()
        let fs = PermissionFileSystem()
        let executor = CleanupExecutor(fileSystem: fs, quarantineRoot: URL(fileURLWithPath: "/fixture-quarantine"),
            currentRuleVersion: "fixture", now: { clock.date })
        let fixture = PermissionFixture(fs: fs, executor: executor)
        let receipt = await executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            clock.expire()
            await fs.allow()
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedProtected, .skippedProtected])
        let attempts = await fs.attempts
        XCTAssertEqual(attempts.count, 2)
    }

    func testAmbiguousPartialMoveDoesNotOfferRetry() async {
        let fixture = PermissionFixture()
        await fixture.fs.leavePartialDestination()
        let receipt = await fixture.executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            XCTFail("A partial destination requires reconciliation, never blind replay")
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .failed, .succeeded])
    }

    func testNonPermissionErrorsAndHeadlessExecutionNeverWait() async {
        let fixture = PermissionFixture()
        await fixture.fs.useNonPermissionError()
        let receipt = await fixture.executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            XCTFail("Only permission failures may ask for permission")
            return .retry
        })
        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .failed, .succeeded])
        let headless = PermissionFixture()
        let headlessReceipt = await headless.executor.execute(plan: headless.plan)
        XCTAssertEqual(headlessReceipt.results.map(\.status), [.succeeded, .failed, .succeeded])
    }

    func testValidationPermissionDenialCanResumeAndIsRevalidated() async {
        let fs = PermissionFileSystem()
        let executor = CleanupExecutor(fileSystem: fs, quarantineRoot: URL(fileURLWithPath: "/fixture-quarantine"),
            currentRuleVersion: "fixture", validateCandidate: { candidate in
                try await fs.validate(candidate.url)
            })
        let fixture = PermissionFixture(fs: fs, executor: executor)
        let receipt = await executor.execute(plan: fixture.plan, permissionRecovery: { _ in
            await fs.allow(); return .retry
        })
        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .succeeded })
        let validations = await fs.blockedValidations
        XCTAssertEqual(validations, 3, "retry repeats validation and the final pre-move check")
    }
}

private struct PermissionFixture: Sendable {
    let first: CleanupCandidate
    let blocked: CleanupCandidate
    let last: CleanupCandidate
    let plan: CleanupPlan
    let fs: PermissionFileSystem
    let executor: CleanupExecutor

    init(fs: PermissionFileSystem = PermissionFileSystem(), executor: CleanupExecutor? = nil) {
        self.fs = fs
        let candidates = (0..<3).map { index in
            CleanupCandidate(url: PermissionFileSystem.urls[index], displayName: "permission fixture", category: .application,
                bytes: 1, risk: .review, evidence: [], identity: PermissionFileSystem.identity(index),
                source: .application, lastAccessDate: nil, isActive: false)
        }
        first = candidates[0]; blocked = candidates[1]; last = candidates[2]
        plan = CleanupPlan(createdAt: Date(), expiresAt: Date().addingTimeInterval(3600),
            items: candidates.map { PlanItem(candidate: $0, isSelected: true) }, ruleVersion: "fixture")
        self.executor = executor ?? CleanupExecutor(fileSystem: fs, quarantineRoot: URL(fileURLWithPath: "/fixture-quarantine"), currentRuleVersion: "fixture")
    }
}

private actor PermissionFileSystem: FileSystemAccess {
    static let urls = (0..<3).map { URL(fileURLWithPath: "/Applications/Permission-Fixture-\($0).app") }
    static func identity(_ index: Int) -> FileIdentity {
        .init(device: 1, inode: UInt64(index + 1), size: 1, modificationTime: 1, kind: .directory)
    }
    private var entries = Dictionary(uniqueKeysWithValues: (0..<3).map { (urls[$0], identity($0)) })
    private var denied = true
    private var partial = false
    private var nonPermission = false
    private var running = false
    private(set) var attempts: [URL] = []
    private(set) var blockedValidations = 0
    func allow() { denied = false }
    func replaceBlocked() { entries[Self.urls[1]] = Self.identity(99) }
    func startBlockedApplication() { running = true }
    func active(_ url: URL) -> Bool { running && url == Self.urls[1] }
    func leavePartialDestination() { partial = true }
    func useNonPermissionError() { nonPermission = true }
    func validate(_ url: URL) throws {
        if url == Self.urls[1] {
            blockedValidations += 1
            if denied { throw NSError(domain: NSPOSIXErrorDomain, code: 13) }
        }
    }
    func identity(at url: URL) throws -> FileIdentity {
        guard let entry = entries[url] else { throw FileSystemError.missing(url) }; return entry
    }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { entries.removeValue(forKey: url); return url }
    func move(_ source: URL, to destination: URL) throws {
        attempts.append(source)
        if source == Self.urls[1], denied {
            if partial { entries[destination] = Self.identity(1) }
            throw NSError(domain: nonPermission ? "fixture IO failure" : NSCocoaErrorDomain,
                code: nonPermission ? 42 : NSFileWriteNoPermissionError)
        }
        entries[destination] = try identity(at: source)
        entries.removeValue(forKey: source)
    }
}

private final class PermissionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var date: Date { lock.withLock { value } }
    func expire() { lock.withLock { value = value.addingTimeInterval(7200) } }
}
