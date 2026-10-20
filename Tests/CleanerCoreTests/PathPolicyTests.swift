import Foundation
import XCTest
@testable import CleanerCore

final class PathPolicyTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testRejectsRootsTraversalAndControlCharacters() {
        let policy = PathPolicy(homeDirectory: home)
        for path in ["/", "/System", "/Users", "/tmp/../System", "/tmp/a\nb"] {
            XCTAssertThrowsError(try policy.validateCandidate(URL(fileURLWithPath: path)))
        }
        XCTAssertThrowsError(try policy.validateCandidate(home))
    }

    func testNeverAllowsAgentRootOrSensitiveAssets() {
        let policy = PathPolicy(homeDirectory: home)
        XCTAssertThrowsError(try policy.validateCandidate(home.appendingPathComponent(".codex")))
        XCTAssertThrowsError(try policy.validateCandidate(home.appendingPathComponent(".claude")))
        XCTAssertThrowsError(try policy.validateCandidate(home.appendingPathComponent(".codex/auth.json")))
        XCTAssertThrowsError(try policy.validateCandidate(home.appendingPathComponent(".claude/settings.json")))
    }

    func testAllowsNarrowCacheDescendant() throws {
        let policy = PathPolicy(homeDirectory: home)
        let cache = home.appendingPathComponent("Library/Caches/com.example/cache.db")
        let validated = try policy.validateCandidate(cache)
        XCTAssertEqual(validated.literal, cache.standardizedFileURL)
    }

    func testRejectsSymlinkResolvingIntoProtectedRoot() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let link = temporaryRoot.appendingPathComponent("looks-like-cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))

        XCTAssertThrowsError(try PathPolicy(homeDirectory: home).validateCandidate(link))
    }

    func testApplicationScopeAllowsOnlyDirectNonSystemBundles() throws {
        let policy = PathPolicy(homeDirectory: home)
        XCTAssertNoThrow(try policy.validateApplicationBundle(URL(fileURLWithPath: "/Applications/Example.app")))
        XCTAssertThrowsError(try policy.validateApplicationBundle(URL(fileURLWithPath: "/Applications/Nested/Example.app")))
        XCTAssertThrowsError(try policy.validateApplicationBundle(URL(fileURLWithPath: "/System/Applications/Example.app")))
        XCTAssertThrowsError(try policy.validateApplicationBundle(URL(fileURLWithPath: "/Applications/Example")))
    }
}
