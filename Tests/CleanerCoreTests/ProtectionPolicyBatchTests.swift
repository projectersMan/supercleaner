import Foundation
import XCTest
@testable import CleanerCore

final class ProtectionPolicyBatchTests: XCTestCase {
    func testBatchMatchesIndividualProtectionIncludingAncestorsAndPhysicalPaths() throws {
        let home = Self.home()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let first = home.appendingPathComponent("first")
        let second = home.appendingPathComponent("second")
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let link = home.appendingPathComponent("protected-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let items = [first.appendingPathComponent("key"), second.appendingPathComponent("key"), home,
            link.appendingPathComponent("key"), home.appendingPathComponent(".ssh/key"), home.appendingPathComponent("safe")].map(Self.candidate)
        let policy = ProtectionPolicy(entries: [ProtectedPath(url: link)], homeDirectory: home)
        XCTAssertEqual(policy.applying(to: items), items.map { policy.applying(to: $0) })
        XCTAssertEqual(policy.applying(to: items).map(\.risk), [.blocked, .review, .blocked, .blocked, .blocked, .review])
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        XCTAssertEqual(policy.applying(to: items), items.map { policy.applying(to: $0) })
        XCTAssertEqual(policy.applying(to: items)[1].risk, .blocked, "Each batch must resolve the current target again")
        XCTAssertThrowsError(try policy.validate(second.appendingPathComponent("key")))
    }

    func testUnavailablePolicyBlocksEveryBatchItemLikeIndividualValidation() {
        let policy = ProtectionPolicy(homeDirectory: Self.home(), isAvailable: false)
        let items = [Self.candidate(Self.home().appendingPathComponent("safe"))]
        XCTAssertEqual(policy.applying(to: items), items.map { policy.applying(to: $0) })
        XCTAssertEqual(policy.applying(to: items)[0].risk, .blocked)
        XCTAssertTrue(policy.applying(to: [CleanupCandidate]()).isEmpty)
    }

    private static func home() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/application-first-entry/fixtures/\(UUID())")
    }

    private static func candidate(_ url: URL) -> CleanupCandidate {
        CleanupCandidate(url: url, displayName: url.lastPathComponent, category: .cache, bytes: 1, risk: .review,
            evidence: [], identity: .init(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .file),
            source: .application, lastAccessDate: nil, isActive: false)
    }
}
