import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationUninstallProtectionTests: XCTestCase {
    func testReadOnlyBundlesAreProtectedBeforeSelectionAndStayProtectedAfterQuit() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context,
            runningBundleIdentifiers: ["fixture.RunningAdmin"])
        let protected = ApplicationListFilter(query: "", scope: .systemProtected).apply(to: inventory.applications)
        XCTAssertEqual(Set(protected.map(\.name)), ["Admin", "RunningAdmin"])
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: inventory.applications).map(\.name), ["Normal"])
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .running).apply(to: inventory.applications).map(\.name), ["RunningAdmin"])
        let result = await ApplicationUninstallAnalyzer(scanner: fixture.scanner).analyze(inventory: inventory, context: fixture.context)
        for name in ["Admin", "RunningAdmin"] {
            let analysis = try XCTUnwrap(result.analyses.first { $0.application.name == name })
            XCTAssertEqual(analysis.state, .protected)
            XCTAssertNil(analysis.plan)
            XCTAssertNotNil(analysis.message)
            let stopped = analysis.withRunningState(false)
            XCTAssertNil(stopped.plan)
            XCTAssertEqual(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: [stopped.application]).count, 1)
        }
        XCTAssertNotNil(result.analyses.first { $0.application.name == "Normal" }?.plan)
    }

    func testPermissionChangeRequiresRefreshAndRestoresNormalClassification() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let before = await fixture.scanner.installedApplications(context: fixture.context)
        XCTAssertEqual(ApplicationListFilter(query: "Admin", scope: .uninstallable).apply(to: before.applications).count, 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.admin.path)
        let after = await fixture.scanner.installedApplications(context: fixture.context)
        XCTAssertEqual(ApplicationListFilter(query: "Admin", scope: .uninstallable).apply(to: after.applications).map(\.name), ["Admin"])
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .all).apply(to: after.applications).count, 3)
    }

    func testWritableBundleInReadOnlyParentIsAlsoProtected() async throws {
        let fixture = try ProtectionFixture()
        let parent = fixture.home.appendingPathComponent("Applications")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
            fixture.remove()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: inventory.applications).count, 3)
        XCTAssertTrue(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: inventory.applications).isEmpty)
    }

    func testStaleSelectionsCannotExecuteProtectedApplicationOrSelectItsReceipts() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        let app = try XCTUnwrap(inventory.applications.first { $0.name == "Admin" })
        let candidate = CleanupCandidate(url: app.bundleURL, displayName: app.name, category: .application,
            bytes: 1, risk: .review, evidence: [], identity: try await fixture.context.fileSystem.identity(at: app.bundleURL),
            source: .application, lastAccessDate: nil, isActive: false)
        let stalePlan = UninstallPlan(application: app, items: [.init(candidate: candidate, containsUserData: false, isShared: false)])
        var selection = UninstallBatchSelectionState(selectedItemIDs: [candidate.id])
        var receipts = PackageReceiptCleanupSelection()
        let receiptURL = URL(fileURLWithPath: "/private/var/db/receipts/fixture.Admin.plist")
        selection.toggle(plan: stalePlan, receipts: [receiptURL], receiptSelection: &receipts)
        XCTAssertTrue(stalePlan.selectableItemIDs.isEmpty)
        XCTAssertEqual(selection.selectionState(for: stalePlan, receipts: [receiptURL], receiptSelection: receipts), .none)
        XCTAssertFalse(receipts.isSelected("fixture.Admin"))
        XCTAssertTrue(selection.selectedItems(in: [stalePlan]).isEmpty)
        XCTAssertEqual(selection.summary(plans: [stalePlan]).itemCount, 0)
        XCTAssertEqual(selection.summary(plans: [stalePlan]).applicationCount, 0)
        selection.reconcile(plans: [stalePlan])
        XCTAssertTrue(selection.selectedItemIDs.isEmpty)
    }

    func testPermissionRequirementSurvivesSerializationAndLegacyInventoryIsRechecked() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        let app = try XCTUnwrap(inventory.applications.first { $0.name == "Admin" })
        let decoded = try JSONDecoder().decode(InstalledApplication.self, from: JSONEncoder().encode(app))
        XCTAssertEqual(decoded.uninstallRequiresAdministrator, true)
        XCTAssertEqual(decoded.withRunningState(true).withRunningState(false).uninstallRequiresAdministrator, true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any])
        legacy.removeValue(forKey: "uninstallRequiresAdministrator")
        let old = try JSONDecoder().decode(InstalledApplication.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.uninstallRequiresAdministrator)
        let analyzed = await ApplicationUninstallAnalyzer(scanner: fixture.scanner).analyze(
            inventory: .init(applications: [old], coverage: .init(), scannedAt: Date()), context: fixture.context)
        XCTAssertEqual(analyzed.applicationInventory.applications.first?.uninstallRequiresAdministrator, true)
        XCTAssertNil(analyzed.analyses.first?.plan)
    }

    func testPlannerAndExecutionRevalidationRejectPermissionChangesAfterScan() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        let normal = try XCTUnwrap(inventory.applications.first { $0.name == "Normal" })
        let planner = UninstallPlanner(scanner: fixture.scanner)
        let plan = try await planner.buildPlan(normal, associations: [], context: fixture.context).plan
        let body = try XCTUnwrap(plan.items.first?.candidate)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: normal.bundleURL.path)
        do {
            _ = try await planner.buildPlan(normal, associations: [], context: fixture.context)
            XCTFail("A stale writable snapshot cannot authorize a new plan")
        } catch UninstallPlanningError.administratorRequired { }
        do {
            try await ApplicationExecutionValidator(scanner: fixture.scanner).validate(body, context: fixture.context)
            XCTFail("Execution must refuse a newly protected application")
        } catch UninstallPlanningError.administratorRequired { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: normal.bundleURL.path))
    }
}

private struct ProtectionFixture: Sendable {
    let home: URL
    var admin: URL { home.appendingPathComponent("Applications/Admin.app") }
    var scanner: ApplicationScanner { .init(metadataProvider: ProtectionMetadata(), applicationRoots: [home.appendingPathComponent("Applications")]) }
    var context: ScanContext { .init(homeDirectory: home, enforcesEntryBudgets: false) }
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("app-protection-\(UUID())")
        for name in ["Normal", "Admin", "RunningAdmin"] {
            let app = home.appendingPathComponent("Applications/\(name).app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            if name != "Normal" { try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.path) }
        }
    }
    func remove() {
        for name in ["Normal", "Admin", "RunningAdmin"] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home.appendingPathComponent("Applications/\(name).app").path)
        }
        try? FileManager.default.removeItem(at: home)
    }
}

private struct ProtectionMetadata: ApplicationMetadataProviding {
    func metadata(for url: URL) -> ApplicationBundleMetadata? {
        let name = url.deletingPathExtension().lastPathComponent
        return .init(bundleIdentifier: "fixture.\(name)", name: name, version: "1", applicationGroups: [])
    }
}
