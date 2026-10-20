import Foundation
import XCTest
@testable import CleanerCore

final class DiskUsageScannerTests: XCTestCase {
    func testDefaultScanCoversLargeFilesAnywhereUnderUserHome() async throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let customDirectory = home.appendingPathComponent("ResearchData", isDirectory: true)
        let largeFile = customDirectory.appendingPathComponent("model-weights.bin")
        let fileSystem = DiskUsageFixtureFileSystem(entries: [
            home: [DiskUsageFixtureEntry(url: customDirectory, size: 0, kind: .directory)],
            customDirectory: [DiskUsageFixtureEntry(url: largeFile, size: 1_000, kind: .file)],
        ])
        let context = ScanContext(homeDirectory: home, fileSystem: fileSystem, now: Date(timeIntervalSince1970: 100))

        let tree = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: context)

        XCTAssertEqual(tree.roots.map(\.url), [home])
        XCTAssertEqual(tree.largeFiles.map(\.url), [largeFile])
        XCTAssertEqual(tree.coverage.scannedRoots, [home])
    }

    func testDefaultScanHasNoEntryOrDepthLimit() async throws {
        let fixture = UnlimitedDiskUsageFixture(legacyEntryLimit: 20_000, legacyDepthLimit: 12)

        let tree = try await DiskUsageScanner(minimumFileBytes: 1).scan(context: fixture.context)

        XCTAssertEqual(tree.concreteFiles.count, 20_002)
        XCTAssertNotNil(tree.node(at: fixture.deepFile))
        XCTAssertFalse(tree.coverage.budgetLimitedModules.contains(.largeFiles))
    }

    func testExplicitFiniteCapsRemainAvailableAndReportLimitedCoverage() async throws {
        let fixture = UnlimitedDiskUsageFixture(legacyEntryLimit: 10, legacyDepthLimit: 3)

        let tree = try await DiskUsageScanner(
            minimumFileBytes: 1,
            maximumDepth: 3,
            maximumEntries: 10
        ).scan(context: fixture.context)

        XCTAssertLessThan(tree.concreteFiles.count, 12)
        XCTAssertNil(tree.node(at: fixture.deepFile))
        XCTAssertTrue(tree.coverage.budgetLimitedModules.contains(.largeFiles))
    }

    func testDirectoriesAggregateSizeButLargeResultsContainOnlyFiles() async throws {
        let fixture = DiskUsageFixture()
        let tree = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: fixture.context)

        XCTAssertEqual(tree.node(at: fixture.project)?.recursiveBytes, 600)
        XCTAssertEqual(tree.largeFiles.map(\.url), [fixture.archive, fixture.nestedFile])
        XCTAssertTrue(tree.largeFiles.allSatisfy { $0.kind == .file })
    }

    func testSymbolicLinksAreNotTraversed() async throws {
        let fixture = DiskUsageFixture()
        _ = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: fixture.context)

        let requested = await fixture.fileSystem.requestedChildren()
        XCTAssertFalse(requested.contains(fixture.symbolicLink.path))
    }
}

private struct UnlimitedDiskUsageFixture {
    let context: ScanContext
    let deepFile: URL

    init(legacyEntryLimit: Int, legacyDepthLimit: Int) {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        var entries: [URL: [DiskUsageFixtureEntry]] = [:]
        entries[home] = [DiskUsageFixtureEntry(url: downloads, size: 0, kind: .directory)]
        entries[downloads] = (0...legacyEntryLimit).map {
            DiskUsageFixtureEntry(url: downloads.appendingPathComponent("file-\($0).bin"), size: 1, kind: .file)
        }

        var parent = downloads
        for depth in 0...legacyDepthLimit {
            let directory = parent.appendingPathComponent("depth-\(depth)", isDirectory: true)
            entries[parent, default: []].append(DiskUsageFixtureEntry(url: directory, size: 0, kind: .directory))
            entries[directory] = []
            parent = directory
        }
        deepFile = parent.appendingPathComponent("deep.bin")
        entries[parent, default: []].append(DiskUsageFixtureEntry(url: deepFile, size: 1, kind: .file))

        context = ScanContext(
            homeDirectory: home,
            fileSystem: DiskUsageFixtureFileSystem(entries: entries),
            now: Date(timeIntervalSince1970: 100)
        )
    }
}

private struct DiskUsageFixture {
    let context: ScanContext
    let fileSystem: DiskUsageFixtureFileSystem
    let project: URL
    let archive: URL
    let nestedFile: URL
    let symbolicLink: URL

    init() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        project = downloads.appendingPathComponent("Project", isDirectory: true)
        archive = downloads.appendingPathComponent("archive.bin")
        nestedFile = project.appendingPathComponent("nested.bin")
        symbolicLink = project.appendingPathComponent("Linked", isDirectory: true)
        fileSystem = DiskUsageFixtureFileSystem(entries: [
            home: [
                DiskUsageFixtureEntry(url: downloads, size: 0, kind: .directory),
            ],
            downloads: [
                DiskUsageFixtureEntry(url: archive, size: 1_000, kind: .file),
                DiskUsageFixtureEntry(url: project, size: 1, kind: .directory),
            ],
            project: [
                DiskUsageFixtureEntry(url: nestedFile, size: 600, kind: .file),
                DiskUsageFixtureEntry(url: symbolicLink, size: 1, kind: .symbolicLink),
            ],
            symbolicLink: [DiskUsageFixtureEntry(url: symbolicLink.appendingPathComponent("hidden.bin"), size: 9_000, kind: .file)],
        ])
        context = ScanContext(homeDirectory: home, fileSystem: fileSystem, now: Date(timeIntervalSince1970: 100))
    }
}

private struct DiskUsageFixtureEntry: Sendable {
    let url: URL
    let size: UInt64
    let kind: FileIdentity.Kind
}

private actor DiskUsageFixtureFileSystem: FileSystemAccess {
    let entries: [URL: [DiskUsageFixtureEntry]]
    let identities: [URL: FileIdentity]
    var requests: [String] = []

    init(entries: [URL: [DiskUsageFixtureEntry]]) {
        self.entries = entries
        identities = Dictionary(uniqueKeysWithValues: entries.values.flatMap { $0 }.map { entry in
            (
                entry.url,
                FileIdentity(
                    device: 1,
                    inode: UInt64(bitPattern: Int64(entry.url.path.hashValue)),
                    size: entry.size,
                    modificationTime: 100,
                    kind: entry.kind
                )
            )
        })
    }
    func identity(at url: URL) throws -> FileIdentity {
        guard let identity = identities[url] else { throw CocoaError(.fileNoSuchFile) }
        return identity
    }
    func children(of url: URL) -> [URL] { requests.append(url.path); return entries[url, default: []].map(\.url) }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { entries[url] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
    func requestedChildren() -> [String] { requests }
}
