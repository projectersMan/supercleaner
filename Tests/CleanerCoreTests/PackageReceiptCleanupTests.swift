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
    func testFailedPartialAndPendingUninstallNeverForgetAndCleanupFailureIsSilent() async throws {
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
        await service.finish(proofs: proofs, receipt: success)
        let after = await calls.ids
        XCTAssertEqual(after, ["org.example.product"])
        XCTAssertEqual(success.overallStatus, .completed)
        XCTAssertNil(success.integrationWarnings)
    }
    func testInvalidPackageIDsCannotBecomeCommandOptionsOrPaths() {
        for id in ["", "-v", "../other", "one/two", "hello\nworld", ".", ".."] {
            XCTAssertFalse(PackageReceiptStore.validIdentifier(id))
        }
        XCTAssertTrue(PackageReceiptStore.validIdentifier("org.example.product-1_2"))
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
