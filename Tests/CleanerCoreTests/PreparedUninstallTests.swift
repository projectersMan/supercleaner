import XCTest
@testable import CleanerCore

final class PreparedUninstallTests: XCTestCase {
    func testRuntimeTransitionsPreserveSelectionIdentityAndProtection() throws {
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleIdentifier: "test.app", name: "Test", version: "1", isRunning: false, isSystem: false)
        let candidates: [CleanupCandidate] = [RiskLevel.review, .blocked].enumerated().map { index, risk in
            CleanupCandidate(url: URL(fileURLWithPath: "/tmp/item-\(index)"), displayName: "item", category: .applicationSupport,
                bytes: 10, risk: risk, evidence: [], identity: .init(device: 1, inode: UInt64(index + 1), size: 10, modificationTime: 1, kind: .file),
                source: .application, lastAccessDate: nil, isActive: false)
        }
        let plan = UninstallPlan(application: app, items: candidates.map { .init(candidate: $0, containsUserData: true, isShared: $0.risk == .blocked) })
        let original = ApplicationUninstallAnalysis(application: app, plan: plan, state: .limited, message: "partial coverage")
        let running = original.withRunningState(true)
        XCTAssertNil(running.plan)
        XCTAssertEqual(running.state, .running)
        let decoded = try JSONDecoder().decode(ApplicationUninstallAnalysis.self, from: JSONEncoder().encode(running))
        let stopped = decoded.withRunningState(false)
        XCTAssertEqual(stopped.plan, original.plan)
        XCTAssertEqual(stopped.state, .limited)
        XCTAssertEqual(stopped.message, "partial coverage")
        XCTAssertEqual(stopped.plan?.selectableItemIDs, [candidates[0].id])
        XCTAssertEqual(stopped.withRunningState(true).withRunningState(false).plan, plan)
    }

    func testMissingLegacyIndexDoesNotRestartDiscovery() async {
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/nonexistent/Test.app"),
            bundleIdentifier: "test.app", name: "Test", version: nil, isRunning: false, isSystem: false)
        let result = await ApplicationUninstallAnalyzer().analyzeStoppedApplications([app.id], in: [app],
            context: .init(homeDirectory: URL(fileURLWithPath: "/nonexistent")))
        XCTAssertEqual(result.first?.state, .unavailable)
        XCTAssertNil(result.first?.plan)
        XCTAssertEqual(result.first?.message, L10n.text("缺少关联扫描结果，请刷新应用列表。"))
    }

    func testSystemProtectionCannotBeLiftedByQuit() {
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/Test.app"),
            bundleIdentifier: "test.system", name: "System", version: nil, isRunning: true, isSystem: true)
        let analysis = ApplicationUninstallAnalysis(application: app, plan: nil, state: .protected)
        XCTAssertEqual(analysis.withRunningState(false), analysis)
    }
}
