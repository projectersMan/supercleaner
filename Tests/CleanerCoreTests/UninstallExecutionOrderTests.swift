import Foundation
import XCTest
@testable import CleanerCore

final class UninstallExecutionOrderTests: XCTestCase {
    func testSourceMetadataRemainsAvailableUntilAssociatedChecksFinish() throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let body = candidate("/Applications/Fixture.app", category: .application)
        let data = candidate(home.appendingPathComponent("Library/Application Support/org.example.fixture").path, category: .applicationSupport)
        let plan = try PlanBuilder(protectionPolicy: .init(homeDirectory: home)).build(
            candidates: [data, body], selectedIDs: [data.id, body.id])
        XCTAssertEqual(plan.selectedItems.map(\.candidate.id), [data.id, body.id],
            "Live ownership checks must retain their source app until the associated-data budget finishes")
    }

    func testDeclaredUserDataKeepsItsSourceAvailableForFinalValidation() throws {
        let body = candidate("/Applications/Fixture.app", category: .application)
        let original = candidate("/Users/tester/Library/Application Support/Fixture", category: .applicationSupport)
        let data = original.replacing(risk: .review, evidence: [.init(code: "data-declaration-source", summary: "verified source")])
        let plan = try PlanBuilder().build(candidates: [body, data], selectedIDs: [body.id, data.id])
        XCTAssertEqual(plan.selectedItems.map(\.candidate.id), [data.id, body.id])
    }

    private func candidate(_ path: String, category: CleanupCategory) -> CleanupCandidate {
        .init(url: URL(fileURLWithPath: path), displayName: "Fixture", category: category, bytes: 1,
            risk: .review, evidence: [], identity: .init(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .directory),
            source: .application, lastAccessDate: nil, isActive: false)
    }
}
