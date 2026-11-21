import CleanerCore
import Foundation
import XCTest

final class SystemCleanupApplicationGroupTests: XCTestCase {
    func testSystemFallbackDoesNotMergeItsLabelWithApplications() throws {
        let system = candidate(name: "system", application: nil)
        let app = candidate(name: "app", application: CleanupApplication(
            bundleIdentifier: "example.app", name: "Example", kind: "Cache"))
        let groups = SystemCleanupApplicationGroup.groups([system, app])

        XCTAssertEqual(groups.count, 2)
        let fallback = try XCTUnwrap(groups.first { $0.candidates.contains(system) })
        XCTAssertEqual(fallback.title, L10n.text("系统"))
        XCTAssertEqual(fallback.candidates.map(\.id), [system.id])
        XCTAssertEqual(groups.first { $0.title == "Example" }?.candidates.map(\.id), [app.id])
    }

    private func candidate(name: String, application: CleanupApplication?) -> CleanupCandidate {
        CleanupCandidate(url: URL(fileURLWithPath: "/fixture/\(name)"), displayName: name,
            category: .cache, bytes: 10, risk: .safe, evidence: [],
            identity: FileIdentity(device: 1, inode: 1, size: 10, modificationTime: 1, kind: .directory),
            source: .general, lastAccessDate: nil, isActive: false, cleanupApplication: application)
    }

    func testFlatGroupsKeepSystemAndNamedApplicationsAtTheSameLevel() {
        let system = candidate(name: "system", application: nil)
        let app = candidate(name: "app", application: CleanupApplication(
            bundleIdentifier: "example.app", name: "Example", kind: "Cache"))
        let secondApp = candidate(name: "second-app", application: CleanupApplication(
            bundleIdentifier: "example.second", name: "Second App", kind: "Logs"))
        let residue = CleanupCandidate(url: URL(fileURLWithPath: "/fixture/residue"), displayName: "Residue",
            category: .applicationSupport, bytes: 30, risk: .review, evidence: [],
            identity: system.identity, source: .historicalApplicationResidue,
            lastAccessDate: nil, isActive: false, requiresExplicitSelection: true)
        let all = [system, app, residue, secondApp]
        let groups = SystemCleanupApplicationGroup.groups(all)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first?.id, "system-and-unassigned")
        XCTAssertEqual(Set(groups[0].candidates.map(\.id)), [system.id, residue.id])
        XCTAssertEqual(groups.first { $0.title == "Example" }?.candidates.map(\.id), [app.id])
        XCTAssertEqual(groups.first { $0.title == "Second App" }?.candidates.map(\.id), [secondApp.id])
        XCTAssertEqual(Set(groups.flatMap(\.candidates).map(\.id)), Set(all.map(\.id)))
        let policy = CleanupRecommendationPolicy()
        XCTAssertEqual(policy.defaultSelectedIDs(for: groups.flatMap(\.candidates)),
            policy.defaultSelectedIDs(for: all))
        XCTAssertFalse(policy.defaultSelectedIDs(for: groups.flatMap(\.candidates)).contains(residue.id))
    }

}
