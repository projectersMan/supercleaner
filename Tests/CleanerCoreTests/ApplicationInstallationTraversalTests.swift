import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationInstallationTraversalTests: XCTestCase {
    func testCaskDiscoveryReadsMetadataWithoutWalkingInstalledPayload() async {
        let fs = CaskFileSystem()
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Fixture.app"),
            bundleIdentifier: "org.example.fixture", name: "Fixture", version: "1", isRunning: false, isSystem: false)
        let result = await LocalApplicationInstallationInspector(caskRoots: [fs.root], receiptRoots: [], steamRoots: [])
            .installations(for: [app], context: .init(homeDirectory: URL(fileURLWithPath: "/Users/tester"), fileSystem: fs,
                enforcesEntryBudgets: false))
        XCTAssertEqual(result.values[app.id]?.source, .homebrew)
        XCTAssertEqual(result.values[app.id]?.identifier, "fixture")
        let visited = await fs.visitedDirectories
        XCTAssertFalse(visited.contains { $0.path.hasPrefix(fs.payload.path) },
            "An uninstall ownership check must not enumerate the installed Cask payload")
        XCTAssertTrue(visited.contains { $0.path == fs.metadata.path })
    }

    func testLinkedCaskMetadataCannotEstablishManagedInstallation() async {
        let fs = CaskFileSystem(linkedMetadata: true)
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Fixture.app"),
            bundleIdentifier: "org.example.fixture", name: "Fixture", version: "1", isRunning: false, isSystem: false)
        let result = await LocalApplicationInstallationInspector(caskRoots: [fs.root], receiptRoots: [], steamRoots: [])
            .installations(for: [app], context: .init(homeDirectory: URL(fileURLWithPath: "/Users/tester"), fileSystem: fs))
        XCTAssertNotEqual(result.values[app.id]?.source, .homebrew)
        let visited = await fs.visitedDirectories
        XCTAssertFalse(visited.contains { $0.path == fs.metadata.path })
    }

    func testUnreadableCaskMetadataPreservesLimitedCoverage() async {
        let fs = CaskFileSystem(unreadableMetadata: true)
        let result = await LocalApplicationInstallationInspector(caskRoots: [fs.root], receiptRoots: [], steamRoots: [])
            .installations(for: [], context: .init(homeDirectory: URL(fileURLWithPath: "/Users/tester"), fileSystem: fs))
        XCTAssertTrue(result.coverage.unavailableRoots.contains { $0.path == fs.metadata.path })
    }
}

private actor CaskFileSystem: FileSystemAccess {
    nonisolated let root = URL(fileURLWithPath: "/fixtures/Caskroom")
    nonisolated var token: URL { root.appendingPathComponent("fixture") }
    nonisolated var metadata: URL { token.appendingPathComponent(".metadata") }
    nonisolated var payload: URL { token.appendingPathComponent("1.0") }
    private let linkedMetadata: Bool
    private let unreadableMetadata: Bool
    private(set) var visitedDirectories: [URL] = []
    init(linkedMetadata: Bool = false, unreadableMetadata: Bool = false) {
        self.linkedMetadata = linkedMetadata; self.unreadableMetadata = unreadableMetadata
    }
    private var receipt: URL { metadata.appendingPathComponent("1/2026/Casks/fixture.json") }
    func identity(at url: URL) throws -> FileIdentity {
        if url.path == metadata.path, unreadableMetadata { throw FileSystemError.unreadableContent(url) }
        return .init(device: 1, inode: UInt64(bitPattern: Int64(url.path.hashValue)), size: 1, modificationTime: 1,
            kind: url.path == receipt.path ? .file : url.path == metadata.path && linkedMetadata ? .symbolicLink : .directory)
    }
    func children(of url: URL) -> [URL] {
        visitedDirectories.append(url)
        if url.path == root.path { return [token] }
        if url.path == token.path { return [metadata, payload] }
        if url.path == metadata.path { return [metadata.appendingPathComponent("1")] }
        if url.path == metadata.appendingPathComponent("1").path { return [metadata.appendingPathComponent("1/2026")] }
        if url.path == metadata.appendingPathComponent("1/2026").path { return [receipt.deletingLastPathComponent()] }
        if url.path == receipt.deletingLastPathComponent().path { return [receipt] }
        if url.path == payload.path { return [payload.appendingPathComponent("sdk")] }
        return []
    }
    func fileExists(_ url: URL) -> Bool { url.path == root.path || url.path.hasPrefix(root.path + "/") }
    func readData(at url: URL, maximumBytes: Int) throws -> Data {
        guard url.path == receipt.path else { throw FileSystemError.missing(url) }
        return Data(#"{"token":"fixture","artifacts":[{"app":["Fixture.app"]}]}"#.utf8)
    }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
