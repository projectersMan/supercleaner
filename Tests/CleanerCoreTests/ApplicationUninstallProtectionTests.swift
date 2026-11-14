import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationUninstallProtectionTests: XCTestCase {
    func testReadOnlyThirdPartyAppsAreSeparatedByRunningState() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context,
            runningBundleIdentifiers: ["fixture.RunningAdmin"])
        XCTAssertTrue(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: inventory.applications).isEmpty)
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: inventory.applications).map(\.name),
            ["Admin", "Normal"])
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .running).apply(to: inventory.applications).map(\.name), ["RunningAdmin"])
        let result = await ApplicationUninstallAnalyzer(scanner: fixture.scanner).analyze(inventory: inventory, context: fixture.context)
        let stopped = try XCTUnwrap(result.analyses.first { $0.application.name == "Admin" })
        XCTAssertFalse(try XCTUnwrap(stopped.plan).selectableItemIDs.isEmpty)
        let running = try XCTUnwrap(result.analyses.first { $0.application.name == "RunningAdmin" })
        XCTAssertNotEqual(running.state, .protected)
        XCTAssertNil(running.plan)
        XCTAssertNotNil(running.withRunningState(false).plan)
        XCTAssertTrue(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: [running.application]).isEmpty)
    }

    func testReadOnlyParentDoesNotBecomePermanentProtection() async throws {
        let fixture = try ProtectionFixture()
        let parent = fixture.home.appendingPathComponent("Applications")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
            fixture.remove()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        XCTAssertTrue(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: inventory.applications).isEmpty)
        let analyzed = await ApplicationUninstallAnalyzer(scanner: fixture.scanner).analyze(inventory: inventory, context: fixture.context)
        XCTAssertEqual(analyzed.plans.count, 3)
    }

    func testPermissionChangeDoesNotPreventPlanningOrLiveIdentityValidation() async throws {
        let fixture = try ProtectionFixture()
        defer { fixture.remove() }
        let inventory = await fixture.scanner.installedApplications(context: fixture.context)
        let app = try XCTUnwrap(inventory.applications.first { $0.name == "Normal" })
        let planner = UninstallPlanner(scanner: fixture.scanner)
        let plan = try await planner.buildPlan(app, associations: [], context: fixture.context).plan
        let body = try XCTUnwrap(plan.items.first?.candidate)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.bundleURL.path)
        let refreshed = try await planner.buildPlan(app, associations: [], context: fixture.context)
        XCTAssertFalse(refreshed.plan.selectableItemIDs.isEmpty)
        try await ApplicationExecutionValidator(scanner: fixture.scanner).validate(body, context: fixture.context)
        let running = try await planner.buildPlan(app.withRunningState(true), associations: [], context: fixture.context)
        XCTAssertTrue(running.plan.selectableItemIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.bundleURL.path))
    }

    func testSystemAppsStayProtectedWhileAppleIdentifierAloneDoesNotProtectApps() {
        let system = InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/System.app"),
            bundleIdentifier: "com.apple.system", name: "System", version: nil, isRunning: true, isSystem: true)
        let installed = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode", version: nil, isRunning: true, isSystem: false)
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: [system, installed]), [system])
        XCTAssertTrue(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: [system, installed]).isEmpty)
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .running).apply(to: [system, installed]), [installed])
        let analysis = ApplicationUninstallAnalysis(application: system, plan: nil, state: .protected)
        XCTAssertNil(analysis.withRunningState(false).plan)
    }

    func testScopesPartitionAllAppsBeforeAndAfterRunningStateChanges() {
        let applications = [
            InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/Siri AI.app"),
                bundleIdentifier: "com.apple.campo", name: "Siri AI", version: nil, isRunning: true, isSystem: true),
            InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/Script Editor.app"),
                bundleIdentifier: "com.apple.ScriptEditor2", name: "Script Editor", version: nil, isRunning: false, isSystem: true),
            InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Chrome.app"),
                bundleIdentifier: "com.google.Chrome", name: "Chrome", version: nil, isRunning: true, isSystem: false),
            InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/XApp.app"),
                bundleIdentifier: "fixture.XApp", name: "XApp", version: nil, isRunning: false, isSystem: false)
        ]
        for inventory in [applications, applications.map { $0.withRunningState(!$0.isRunning) }] {
            let stopped = ApplicationListFilter(query: "", scope: .uninstallable).apply(to: inventory)
            let running = ApplicationListFilter(query: "", scope: .running).apply(to: inventory)
            let protected = ApplicationListFilter(query: "", scope: .systemProtected).apply(to: inventory)
            XCTAssertEqual(protected.map(\.name), ["Script Editor", "Siri AI"])
            XCTAssertEqual(stopped.count, 1)
            XCTAssertEqual(running.count, 1)
            XCTAssertTrue(stopped.allSatisfy { !$0.isRunning && !$0.isSystem })
            XCTAssertTrue(running.allSatisfy { $0.isRunning && !$0.isSystem })
            let partition = stopped + running + protected
            XCTAssertEqual(partition.count, inventory.count, "each app must appear once across the three scopes")
            XCTAssertEqual(Set(partition.map(\.id)), Set(inventory.map(\.id)), "no app may be omitted")
            XCTAssertEqual(ApplicationListFilter(query: "", scope: .all).apply(to: inventory).count, inventory.count)
        }
    }
}

private struct ProtectionFixture: Sendable {
    let home: URL
    var scanner: ApplicationScanner { .init(metadataProvider: ProtectionMetadata(), applicationRoots: [home.appendingPathComponent("Applications")]) }
    var context: ScanContext { .init(homeDirectory: home, enforcesEntryBudgets: false) }
    init() throws {
        home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("application-uninstall-eligibility/fixtures/\(UUID())")
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
