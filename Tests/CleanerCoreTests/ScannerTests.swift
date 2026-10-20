import Foundation
import XCTest
@testable import CleanerCore

final class ScannerTests: XCTestCase {
    func testRecentCacheIsReviewAndOldInactiveCacheIsSafe() async throws {
        let fixture = ScanFixture()
        let results = try await UserCacheScanner().scan(context: fixture.context)
        XCTAssertEqual(results.first { $0.displayName == "recent" }?.risk, .review)
        XCTAssertEqual(results.first { $0.displayName == "old" }?.risk, .safe)
        XCTAssertEqual(results.first { $0.displayName == "old-directory" }?.bytes, 500)
    }

    func testLargeFilesAreNeverSafeBySizeAlone() async throws {
        let fixture = ScanFixture()
        let results = try await LargeFileScanner(minimumBytes: 100).scan(context: fixture.context)
        XCTAssertTrue(results.allSatisfy { $0.risk != .safe })
        XCTAssertTrue(results.allSatisfy { $0.identity.kind == .file })
        XCTAssertEqual(results.map { $0.url.lastPathComponent }, ["archive.bin", "nested.bin"])
        XCTAssertFalse(results.contains { $0.url.lastPathComponent == "LargeProject" })
    }

    func testCoordinatorContainsScannerFailure() async {
        let fixture = ScanFixture()
        let scanners: [any CleanerCore.Scanner] = [UserCacheScanner(), FailingScanner()]
        let report = await ScanCoordinator(maxConcurrentScanners: 2).scan(
            using: scanners,
            context: fixture.context
        )
        XCTAssertFalse(report.candidates.isEmpty)
        XCTAssertEqual(report.failures.map(\.scannerID), ["fixture.failure"])
    }
}

private struct FailingScanner: CleanerCore.Scanner {
    let id = "fixture.failure"
    let category = CleanupCategory.cache
    func scan(context: ScanContext) async throws -> [CleanupCandidate] { throw CancellationError() }
}

private struct ScanFixture {
    let context: ScanContext

    init() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let now = Date(timeIntervalSince1970: 10_000_000)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let oldCacheDirectory = cacheRoot.appendingPathComponent("old-directory", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let project = downloads.appendingPathComponent("LargeProject", isDirectory: true)
        let entries = [
            cacheRoot: [
                FixtureEntry(url: cacheRoot.appendingPathComponent("recent"), size: 50, modified: now.addingTimeInterval(-86_400)),
                FixtureEntry(url: cacheRoot.appendingPathComponent("old"), size: 75, modified: now.addingTimeInterval(-86_400 * 45)),
                FixtureEntry(url: oldCacheDirectory, size: 75, modified: now.addingTimeInterval(-86_400 * 45), kind: .directory),
            ],
            oldCacheDirectory: [FixtureEntry(url: oldCacheDirectory.appendingPathComponent("payload.bin"), size: 500, modified: now)],
            downloads: [
                FixtureEntry(url: downloads.appendingPathComponent("archive.bin"), size: 1_000, modified: now),
                FixtureEntry(url: project, size: 1, modified: now, kind: .directory),
            ],
            project: [FixtureEntry(url: project.appendingPathComponent("nested.bin"), size: 600, modified: now)],
        ]
        context = ScanContext(homeDirectory: home, fileSystem: FixtureFileSystem(entries: entries), now: now)
    }
}

private struct FixtureEntry: Sendable {
    let url: URL
    let size: UInt64
    let modified: Date
    let kind: FileIdentity.Kind
    init(url: URL, size: UInt64, modified: Date, kind: FileIdentity.Kind = .file) { self.url = url; self.size = size; self.modified = modified; self.kind = kind }
}

private actor FixtureFileSystem: FileSystemAccess {
    let entries: [URL: [FixtureEntry]]
    init(entries: [URL: [FixtureEntry]]) { self.entries = entries }
    func identity(at url: URL) throws -> FileIdentity {
        let entry = entries.values.flatMap { $0 }.first { $0.url == url }!
        return FileIdentity(device: 1, inode: UInt64(abs(url.path.hashValue)), size: entry.size, modificationTime: Int64(entry.modified.timeIntervalSince1970), kind: entry.kind)
    }
    func children(of url: URL) -> [URL] {
        entries.first { $0.key.standardizedFileURL.path == url.standardizedFileURL.path }?.value.map(\.url) ?? []
    }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) throws { XCTFail("scanner attempted write") }
    func createDirectory(_ url: URL) throws { XCTFail("scanner attempted write") }
    func removeEmptyDirectory(_ url: URL) throws { XCTFail("scanner attempted write") }
    func trash(_ url: URL) throws -> URL { XCTFail("scanner attempted write"); return url }
}
