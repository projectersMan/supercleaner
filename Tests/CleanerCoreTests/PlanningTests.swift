import Foundation
import XCTest
@testable import CleanerCore

final class PlanningTests: XCTestCase {
    func testBlockedCandidateCannotEnterPlan() {
        let blocked = executionFixtureCandidate(path: "/tmp/blocked", risk: .blocked)
        XCTAssertThrowsError(try PlanBuilder().build(candidates: [blocked], selectedIDs: [blocked.id], now: Date()))
    }

    func testPlanBindsVersionsAndExpires() throws {
        let now = Date(timeIntervalSince1970: 100)
        let safe = executionFixtureCandidate(path: "/tmp/safe", risk: .safe)
        let plan = try PlanBuilder(engineVersion: "1", ruleVersion: "rules-1", planTTL: 60).build(candidates: [safe], selectedIDs: [safe.id], now: now)
        XCTAssertEqual(plan.ruleVersion, "rules-1")
        XCTAssertFalse(plan.isExpired(at: now.addingTimeInterval(59)))
        XCTAssertTrue(plan.isExpired(at: now.addingTimeInterval(60)))
    }
}

func executionFixtureCandidate(path: String, risk: RiskLevel = .safe, inode: UInt64 = 2) -> CleanupCandidate {
    CleanupCandidate(url: URL(fileURLWithPath: path), displayName: URL(fileURLWithPath: path).lastPathComponent, category: .cache, bytes: 10, risk: risk, evidence: [Evidence(code: "fixture", summary: "fixture")], identity: FileIdentity(device: 1, inode: inode, size: 10, modificationTime: 3, kind: .file), source: .general, lastAccessDate: nil, isActive: false)
}
