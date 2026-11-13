import XCTest
@testable import CleanerCore

@MainActor final class PackageReceiptCleanupTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Example.app")
    private let other = URL(fileURLWithPath: "/Applications/Another.app")
    private func manifest(_ paths: [URL]) -> PackageReceiptManifest {
        .init(packageID: "org.example.product", fingerprint: "fingerprint", paths: paths)
    }
    private func candidate(_ path: URL) -> CleanupCandidate {
        .init(url: path, displayName: "Example", category: .application, bytes: 1, risk: .review,
              evidence: [.init(code: "package-receipt-id", summary: "org.example.product"),
                         .init(code: "package-receipt-selected", summary: "org.example.product")],
              identity: .init(device: 1, inode: 1, size: 1, modificationTime: 0, kind: .directory),
              source: .application, lastAccessDate: nil, isActive: false)
    }
    func testReceiptCheckboxesStartUncheckedAndPairSelectionControlsExecution() async throws {
        let plist = URL(fileURLWithPath: "/var/db/receipts/org.example.product.plist")
        let bom = URL(fileURLWithPath: "/private/var/db/receipts/org.example.product.bom")
        let packageID = try XCTUnwrap(PackageReceiptCleanupSelection.packageID(for: plist))
        XCTAssertEqual(PackageReceiptCleanupSelection.packageID(for: bom), packageID)
        XCTAssertNil(PackageReceiptCleanupSelection.packageID(for: URL(fileURLWithPath: "/var/db/other.plist")))
        var selection = PackageReceiptCleanupSelection()
        XCTAssertFalse(selection.isSelected(packageID))
        let candidates = [candidate(app), candidate(other)]
        let input = manifest([app, other])
        let calls = ReceiptCalls()
        let service = PackageReceiptCleanupService(load: { id in await calls.record(id); return input }, forget: { _, _ in XCTFail("Not an execution test") })
        selection.setSelected(false, packageID: packageID)
        XCTAssertFalse(selection.isSelected(try XCTUnwrap(PackageReceiptCleanupSelection.packageID(for: bom))))
        let optedOut = candidates.map { selection.applying(to: $0) }
        let plan = try PlanBuilder().build(candidates: optedOut, selectedIDs: Set(optedOut.map(\.id)))
        let proofs = await service.prepare(plan: plan)
        XCTAssertTrue(proofs.isEmpty)
        let loads = await calls.ids
        XCTAssertTrue(loads.isEmpty)
        XCTAssertEqual(plan.selectedItems.count, 2)
        selection.setSelected(true, packageID: packageID)
        let optedIn = candidates.map { selection.applying(to: $0) }
        let enabled = try PlanBuilder().build(candidates: optedIn, selectedIDs: Set(optedIn.map(\.id)))
        let enabledProofs = await service.prepare(plan: enabled)
        XCTAssertEqual(enabledProofs.count, 1)
    }

    func testWholePackageRequiredAndStructuralParentsAreAllowed() {
        let paths = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Applications"), app, app.appendingPathComponent("Contents/MacOS/executable")]
        XCTAssertNotNil(manifest(paths).proof(selectedApplications: [app]))
        XCTAssertNil(manifest(paths + [other]).proof(selectedApplications: [app]))
        XCTAssertNotNil(manifest(paths + [other]).proof(selectedApplications: [app, other]))
        XCTAssertNil(manifest(paths + [URL(fileURLWithPath: "/Library/LaunchDaemons/org.example.plist")]).proof(selectedApplications: [app]))
        XCTAssertNil(manifest([]).proof(selectedApplications: [app]))
        XCTAssertNil(manifest([app]).proof(selectedApplications: []))
    }
    func testEmbeddedAppDoesNotBecomeSeparateUninstallRequirement() {
        let proof = manifest([app, app.appendingPathComponent("Contents/Library/LoginItems/Worker.app/Contents/Info.plist")]).proof(selectedApplications: [app])
        XCTAssertEqual(proof?.applications, [app])
    }
    func testFailedPartialAndPendingUninstallNeverForgetAndCleanupFailureIsReported() async throws {
        let calls = ReceiptCalls()
        let input = manifest([app, other])
        let service = PackageReceiptCleanupService(load: { _ in input }, forget: { proof, _ in
            await calls.record(proof.packageID)
            throw HelperClientError.notAuthorized
        })
        let candidates = [candidate(app), candidate(other)]
        let plan = try PlanBuilder().build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        let proofs = await service.prepare(plan: plan)
        XCTAssertEqual(proofs.count, 1)
        func result(_ index: Int, status: OperationStatus = .succeeded, pending: Date? = nil) -> OperationResult {
            .init(candidateID: candidates[index].id, originalURL: candidates[index].url, disposition: status == .succeeded ? .quarantined : .failed,
                  status: status, bytes: 1, verificationNotBefore: pending)
        }
        func receipt(_ results: [OperationResult]) -> OperationReceipt {
            .init(planID: plan.id, startedAt: Date(), completedAt: Date(), results: results)
        }
        await service.finish(proofs: proofs, receipt: receipt([result(0)]))
        await service.finish(proofs: proofs, receipt: receipt([result(0), result(1, status: .failed)]))
        await service.finish(proofs: proofs, receipt: receipt([result(0), result(1, pending: Date())]))
        let before = await calls.ids
        XCTAssertTrue(before.isEmpty)
        let success = receipt([result(0), result(1)])
        let metadata = await service.finish(proofs: proofs, receipt: success)
        XCTAssertEqual(metadata.count, 2)
        XCTAssertTrue(metadata.allSatisfy { $0.status == .failed && $0.message != nil })
        let after = await calls.ids
        XCTAssertEqual(after, ["org.example.product"])
        XCTAssertEqual(success.overallStatus, .completed)
        XCTAssertNil(success.integrationWarnings)
    }
    func testReceiptAuthorizationResumesOnlyMetadataCleanup() async throws {
        let input = manifest([app])
        let gate = ReceiptPermissionGate()
        let service = PackageReceiptCleanupService(load: { _ in input }, forget: { _, _ in try await gate.forget() })
        let body = candidate(app)
        let plan = try PlanBuilder().build(candidates: [body], selectedIDs: [body.id])
        let proofs = await service.prepare(plan: plan)
        let files = [OperationResult(candidateID: body.id, originalURL: app, disposition: .quarantined, bytes: 1)]
        let receipt = OperationReceipt(planID: plan.id, startedAt: Date(), completedAt: Date(), results: files)
        let metadata = await service.finish(proofs: proofs, receipt: receipt, permissionRecovery: { request in
            XCTAssertEqual(request.resource, .installationReceipts)
            XCTAssertEqual(request.attempt, 1)
            await gate.authorize()
            return .retry
        })
        XCTAssertEqual(metadata.count, 2)
        XCTAssertTrue(metadata.allSatisfy { $0.status == .succeeded })
        let calls = await gate.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(receipt.results, files)
    }

    func testStopDuringReceiptAuthorizationKeepsBothReceiptRows() async throws {
        let input = manifest([app])
        let gate = ReceiptPermissionGate()
        let service = PackageReceiptCleanupService(load: { _ in input }, forget: { _, _ in try await gate.forget() })
        let body = candidate(app)
        let plan = try PlanBuilder().build(candidates: [body], selectedIDs: [body.id])
        let proofs = await service.prepare(plan: plan)
        let receipt = OperationReceipt(planID: plan.id, startedAt: Date(), completedAt: Date(),
            results: [.init(candidateID: body.id, originalURL: app, disposition: .quarantined, bytes: 1)])
        let metadata = await Task {
            await service.finish(proofs: proofs, receipt: receipt, permissionRecovery: { _ in .stop })
        }.value
        XCTAssertEqual(metadata.count, 2)
        XCTAssertTrue(metadata.allSatisfy { $0.status == .skippedCancelled })
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
    }

    func testInvalidPackageIDsCannotBecomeCommandOptionsOrPaths() {
        for id in ["", "-v", "../other", "one/two", "hello\nworld", ".", ".."] {
            XCTAssertFalse(PackageReceiptStore.validIdentifier(id))
        }
        XCTAssertTrue(PackageReceiptStore.validIdentifier("org.example.product-1_2"))
    }

    func testSevenSelectedRowsKeepTheSameTotalThroughTrashAndHistory() async throws {
        let result = try await runSevenRowUninstall(failing: false)
        XCTAssertEqual(result.receipt.results.count, 5, "installer metadata must stay outside generic file deletion")
        XCTAssertEqual(result.receipt.installationReceiptResults?.count, 2)
        XCTAssertEqual(result.receipt.displayResults.count, 7)
        XCTAssertTrue(result.receipt.displayResults.allSatisfy { $0.status == .succeeded })
        XCTAssertEqual(result.receipt.overallStatus, .completed)
        XCTAssertTrue(result.progress.allSatisfy { $0.total == 7 }, "never change the denominator from seven visible rows to five file moves")
        XCTAssertEqual(result.progress.last?.completed, 7)
        XCTAssertEqual(result.forgetCount, 1, "both receipt rows must use one verified pkgutil operation")
        XCTAssertEqual(result.persisted, result.receipt, "Trash resolution must preserve the installer outcomes")
    }

    func testFailedBundleAndTimedOutContainerReportAllFourRetainedRows() async throws {
        let result = try await runSevenRowUninstall(failing: true)
        let presentation = DeletionResultPresentation(receipt: result.receipt)
        XCTAssertEqual(result.receipt.displayResults.count, 7)
        XCTAssertEqual(presentation.deletedCount, 3)
        XCTAssertEqual(presentation.incompleteCount, 4)
        XCTAssertFalse(presentation.isComplete)
        XCTAssertEqual(result.receipt.overallStatus, .partial)
        XCTAssertEqual(result.forgetCount, 0, "receipt cleanup must not run when the app bundle failed to move")
        XCTAssertTrue(result.receipt.installationReceiptResults?.allSatisfy { $0.status == .skippedProtected && $0.message != nil } == true)
        XCTAssertTrue(result.receipt.results.contains { $0.originalURL == app && $0.message == L10n.text("权限不足，应用本体仍在原位。请检查 App 管理权限，或在 Finder 中完成需要管理员确认的移除。") })
        XCTAssertTrue(result.progress.allSatisfy { $0.total == 7 })
        XCTAssertEqual(result.persisted, result.receipt)
    }

    func testMetadataFailureAndLegacyReceiptsRemainVisibleAndDecodable() throws {
        let failed = OperationResult(candidateID: UUID(), originalURL: app, disposition: .failed, status: .failed, bytes: 1)
        let original = OperationReceipt(planID: UUID(), startedAt: Date(), completedAt: Date(), results: [failed], overallStatus: .failed)
        let legacy = try JSONDecoder().decode(OperationReceipt.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.installationReceiptResults)
        let metadata = OperationResult(candidateID: UUID(), originalURL: URL(fileURLWithPath: "/private/var/db/receipts/org.example.product.plist"),
            disposition: .skipped, status: .skippedProtected, bytes: 0, message: "retained")
        let receipt = original.recordingInstallationReceipts([metadata]).addingIntegrationWarning("warning")
        XCTAssertEqual(receipt.applying(resolutionResults: []).installationReceiptResults, [metadata])
        XCTAssertEqual(try JSONDecoder().decode(OperationReceipt.self, from: JSONEncoder().encode(receipt)), receipt)
        XCTAssertEqual(DeletionResultPresentation(receipt: receipt).incompleteCount, 2)
    }

    private func runSevenRowUninstall(failing: Bool) async throws -> (receipt: OperationReceipt, persisted: OperationReceipt?, progress: [ExecutionProgress], forgetCount: Int) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("seven-row-uninstall-\(UUID())").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let body = candidate(app)
        let associated = (1...4).map { index in
            CleanupCandidate(url: root.appendingPathComponent("data-\(index)"), displayName: "data", category: .applicationSupport,
                bytes: 1, risk: .review, evidence: [], identity: body.identity, source: .application, lastAccessDate: nil, isActive: false)
        }
        let candidates = [body] + associated
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        XCTAssertEqual(plan.selectedDisplayItemCount, 7)
        let fs = ReceiptProgressFileSystem(candidates: candidates, failingBody: failing ? app : nil)
        let executor = CleanupExecutor(fileSystem: fs, quarantineRoot: root.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture",
            validateCandidate: { candidate in
                if failing && candidate.url.lastPathComponent == "data-4" { throw ApplicationValidationDeadlineError.timedOut }
            })
        let history = HistoryStore(url: root.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedules.json"))
        let resolutions = ResolutionJournalStore(url: root.appendingPathComponent("resolutions.json"))
        let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules,
            executor: executor, resolutionJournalStore: resolutions)
        let calls = ReceiptCalls()
        let manifest = self.manifest([app])
        let service = PackageReceiptCleanupService(load: { _ in manifest }, forget: { proof, _ in await calls.record(proof.packageID) })
        let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history,
            journalStore: ExecutionJournalStore(url: root.appendingPathComponent("execution.json")),
            resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance, now: Date.init,
            packageReceipts: service)
        let captured = ReceiptProgressCapture()
        let receipt = try await coordinator.execute(plan: plan, retentionPolicy: .immediate) { captured.append($0) }
        return (receipt, try await history.receipt(id: receipt.id), captured.values, await calls.ids.count)
    }
    func testReceiptHelperRequiresAuthorizationBeforeReadingOrExecuting() async throws {
        let proof = PackageReceiptCleanupProof(packageID: "org.example.absent", fingerprint: "not-real", applications: [app])
        let operation = HelperOperation.forgetInstallationReceipt(proof)
        let token = CapabilityToken(planID: UUID(), operationDigest: operation.digest, expiresAt: Date().addingTimeInterval(60),
            callerRequirement: "fixture-caller", identity: .init(device: 0, inode: 0, size: 0, modificationTime: 0, kind: .file), callerUserID: getuid())
        let handler = HelperRequestHandler(authorizer: .init(expectedCallerRequirement: "fixture-caller"), authorizationCheck: { _ in false })
        let scope = try HelperFileScope(userID: getuid(), homePath: "/Users/fixture")
        let result = await handler.handle(try JSONEncoder().encode(HelperRequest(operation: operation, token: token)), scope: scope)
        XCTAssertEqual(result.authorization, .rejected(.authorizationRequired))
    }

    func testRealBOMParsingFingerprintAndReinstalledAppChecks() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("pkg-receipt-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = root.appendingPathComponent("payload")
        let applications = root.appendingPathComponent("Applications")
        let installed = applications.appendingPathComponent("Sample.app")
        let receipts = root.appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: payload.appendingPathComponent("Sample.app/Contents"), withIntermediateDirectories: true)
        try Data("data".utf8).write(to: payload.appendingPathComponent("Sample.app/Contents/file"))
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let id = "org.example.fixture"
        let plist = try PropertyListSerialization.data(fromPropertyList: ["PackageIdentifier": id, "InstallPrefixPath": String(applications.path.dropFirst())], format: .binary, options: 0)
        try plist.write(to: receipts.appendingPathComponent(id + ".plist"))
        let process = try await BoundedProcess.run("/usr/bin/mkbom", arguments: [payload.path, receipts.appendingPathComponent(id + ".bom").path], timeout: 5, maximumOutputBytes: 4096)
        XCTAssertEqual(process.status, 0)
        let calls = ReceiptCalls()
        let store = PackageReceiptStore(root: receipts, requireRootOwnership: false, forgetCommand: { id, _ in await calls.record(id) })
        let loaded = try await store.load(id)
        let proof = try XCTUnwrap(loaded.proof(selectedApplications: [installed]))
        let scope = try HelperFileScope(userID: getuid(), homePath: root.path, applicationsPath: applications.path)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        do { try await store.forget(proof, scope: scope, expiresAt: Date().addingTimeInterval(60)); XCTFail("Existing app accepted") } catch {}
        try FileManager.default.removeItem(at: installed)
        try await store.forget(proof, scope: scope, expiresAt: Date().addingTimeInterval(60))
        let recorded = await calls.ids
        XCTAssertEqual(recorded, [id])
        let changed = PackageReceiptCleanupProof(packageID: id, fingerprint: "changed", applications: [installed])
        do { try await store.forget(changed, scope: scope, expiresAt: Date().addingTimeInterval(60)); XCTFail("Changed receipt accepted") } catch {}
        do { try await store.forget(proof, scope: scope, expiresAt: Date().addingTimeInterval(-1)); XCTFail("Expired capability accepted") } catch {}
        let final = await calls.ids
        XCTAssertEqual(final.count, 1)
    }
}

private actor ReceiptCalls {
    private(set) var ids = [String]()
    func record(_ id: String) { ids.append(id) }
}

private actor ReceiptProgressFileSystem: FileSystemAccess {
    private var entries: [URL: FileIdentity]
    private let failingBody: URL?
    init(candidates: [CleanupCandidate], failingBody: URL?) {
        entries = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url, $0.identity) })
        self.failingBody = failingBody
    }
    func identity(at url: URL) throws -> FileIdentity {
        guard let value = entries[url] else { throw FileSystemError.missing(url) }; return value
    }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func move(_ source: URL, to destination: URL) throws {
        if source == failingBody { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
        entries[destination] = try identity(at: source)
        entries.removeValue(forKey: source)
    }
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) throws -> URL {
        _ = try identity(at: url)
        entries.removeValue(forKey: url)
        return URL(fileURLWithPath: "/fixture-trash/\(url.lastPathComponent)")
    }
}

private final class ReceiptProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExecutionProgress] = []
    var values: [ExecutionProgress] { lock.withLock { storage } }
    func append(_ value: ExecutionProgress) { lock.withLock { storage.append(value) } }
}

private actor ReceiptPermissionGate {
    private var authorized = false
    private(set) var calls = 0
    func authorize() { authorized = true }
    func forget() throws {
        calls += 1
        if !authorized { throw HelperClientError.notAuthorized }
    }
}
