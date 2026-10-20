import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationScannerTests: XCTestCase {
    func testBundleIDAssociationDoesNotMatchPrefixCollision() async throws {
        let fixture = ApplicationFixture()
        let associations = try await ApplicationScanner().associations(for: fixture.application, context: fixture.context)
        XCTAssertFalse(associations.contains { $0.url.lastPathComponent == "com.example.app2" })
        XCTAssertTrue(associations.contains { $0.url.lastPathComponent == "com.example.app" })
    }

    func testSharedOrUserContentIsBlocked() async throws {
        let fixture = ApplicationFixture()
        let plan = try await UninstallPlanner().planUninstall(fixture.application, context: fixture.context)
        XCTAssertTrue(plan.items.filter { $0.containsUserData || $0.isShared }.allSatisfy { $0.candidate.risk == .blocked })
        XCTAssertEqual(plan.items.first { $0.candidate.url == fixture.application.bundleURL }?.candidate.risk, .review)
    }

    func testDefaultDiscoveryFindsApplicationsBeyondLegacyDepthLimit() async {
        let fixture = DeepApplicationDiscoveryFixture()

        let inventory = await ApplicationScanner(metadataProvider: fixture.metadataProvider).installedApplications(context: fixture.context)

        XCTAssertEqual(inventory.applications.map(\.name), ["Deep"])
        XCTAssertTrue(inventory.coverage.budgetLimitedModules.isEmpty)
    }

    func testExplicitDepthLimitReportsLimitedCoverageWhenItTruncatesTraversal() async {
        let fixture = DeepApplicationDiscoveryFixture()

        let inventory = await ApplicationScanner(metadataProvider: fixture.metadataProvider).installedApplications(
            context: fixture.context,
            maximumDepth: 2
        )

        XCTAssertTrue(inventory.applications.isEmpty)
        XCTAssertTrue(inventory.coverage.budgetLimitedModules.contains(.applications))
    }

    func testExplicitEntryLimitReportsLimitedCoverageWhenItTruncatesTraversal() async {
        let fixture = DeepApplicationDiscoveryFixture()

        let inventory = await ApplicationScanner(metadataProvider: fixture.metadataProvider).installedApplications(
            context: fixture.context,
            maximumEntries: 2
        )

        XCTAssertTrue(inventory.applications.isEmpty)
        XCTAssertTrue(inventory.coverage.budgetLimitedModules.contains(.applications))
    }

    func testDefaultUninstallSizeMeasurementTraversesBeyondLegacyDepthLimit() async throws {
        let fixture = DeepUninstallSizeFixture(depth: 40, leafBytes: 4_096)

        let result = try await UninstallPlanner().buildPlan(
            fixture.application,
            associations: [],
            context: fixture.context
        )

        XCTAssertEqual(result.plan.items.first?.candidate.bytes, 4_096)
        XCTAssertFalse(result.reachedSizeBudget)
    }

    func testExplicitUninstallSizeEntryLimitReportsIncompleteMeasurement() async throws {
        let fixture = DeepUninstallSizeFixture(depth: 4, leafBytes: 4_096)

        let result = try await UninstallPlanner().buildPlan(
            fixture.application,
            associations: [],
            context: fixture.context,
            maximumSizeEntries: 2
        )

        XCTAssertTrue(result.reachedSizeBudget)
    }

    func testDefaultUninstallAnalyzerHasNoImplicitSizeCap() async {
        let fixture = DeepUninstallSizeFixture(depth: 40, leafBytes: 4_096)
        let inventory = ApplicationInventory(applications: [fixture.application], coverage: .init(), scannedAt: Date())

        let result = await ApplicationUninstallAnalyzer().analyze(inventory: inventory, context: fixture.context)

        XCTAssertEqual(result.analysis(for: fixture.application.id)?.state, .complete)
        XCTAssertEqual(result.analysis(for: fixture.application.id)?.plan?.items.first?.candidate.bytes, 4_096)
    }
}

private struct DeepUninstallSizeFixture {
    let application: InstalledApplication
    let context: ScanContext

    init(depth: Int, leafBytes: UInt64) {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Applications/DeepSize.app", isDirectory: true)
        application = InstalledApplication(bundleURL: appURL, bundleIdentifier: "com.example.deepsize", name: "DeepSize", version: "1", isRunning: false, isSystem: false)
        context = ScanContext(homeDirectory: home, fileSystem: DeepUninstallSizeFileSystem(appURL: appURL, depth: depth, leafBytes: leafBytes))
    }
}

private actor DeepUninstallSizeFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]

    init(appURL: URL, depth: Int, leafBytes: UInt64) {
        var directories = [appURL]
        for level in 1...depth {
            directories.append(directories.last!.appendingPathComponent("Level\(level)", isDirectory: true))
        }
        let leaf = directories.last!.appendingPathComponent("payload.bin")
        var children: [String: [URL]] = [:]
        for (parent, child) in zip(directories, directories.dropFirst()) {
            children[parent.path] = [child]
        }
        children[directories.last!.path] = [leaf]
        childrenByPath = children
        var values = Dictionary(uniqueKeysWithValues: directories.map {
            ($0.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64($0.path.hashValue)), size: 0, modificationTime: 1, kind: .directory))
        })
        values[leaf.path] = FileIdentity(device: 1, inode: 99_999, size: leafBytes, modificationTime: 1, kind: .file)
        identities = values
    }

    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private struct DeepApplicationDiscoveryFixture {
    let context: ScanContext
    let metadataProvider: DeepApplicationMetadataProvider

    init() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let root = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let levels = (1...6).reduce(into: [root]) { paths, level in
            paths.append(paths.last!.appendingPathComponent("Level\(level)", isDirectory: true))
        }
        let app = levels.last!.appendingPathComponent("Deep.app", isDirectory: true)
        var childrenByPath: [String: [URL]] = [:]
        for (parent, child) in zip(levels, levels.dropFirst()) {
            childrenByPath[parent.path] = [child]
        }
        childrenByPath[levels.last!.path] = [app]
        context = ScanContext(
            homeDirectory: home,
            fileSystem: DeepApplicationDiscoveryFileSystem(
                childrenByPath: childrenByPath,
                directoryPaths: Set(levels.map(\.path) + [app.path])
            )
        )
        metadataProvider = DeepApplicationMetadataProvider(
            appURL: app,
            metadata: ApplicationBundleMetadata(bundleIdentifier: "com.example.deep", name: "Deep", version: "1")
        )
    }
}

private struct DeepApplicationMetadataProvider: ApplicationMetadataProviding {
    let appURL: URL
    let metadata: ApplicationBundleMetadata

    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        bundleURL.standardizedFileURL == appURL.standardizedFileURL ? metadata : nil
    }
}

private actor DeepApplicationDiscoveryFileSystem: FileSystemAccess {
    let childrenByPath: [String: [URL]]
    let directoryPaths: Set<String>

    func identity(at url: URL) throws -> FileIdentity {
        FileIdentity(
            device: 1,
            inode: UInt64(bitPattern: Int64(url.path.hashValue)),
            size: 1,
            modificationTime: 1,
            kind: directoryPaths.contains(url.path) ? .directory : .file
        )
    }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { childrenByPath[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private struct ApplicationFixture {
    let application: InstalledApplication
    let context: ScanContext

    init() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true)
        application = InstalledApplication(bundleURL: appURL, bundleIdentifier: "com.example.app", name: "Example", version: "1.0", isRunning: false, isSystem: false)
        context = ScanContext(homeDirectory: home, fileSystem: ApplicationFixtureFileSystem(home: home, appURL: appURL))
    }
}

private actor ApplicationFixtureFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]
    init(home: URL, appURL: URL) {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let urls = [appURL, caches.appendingPathComponent("com.example.app"), caches.appendingPathComponent("com.example.app2"), support.appendingPathComponent("Example"), groups.appendingPathComponent("group.com.example.app")]
        childrenByPath = [caches.path: Array(urls[1...2]), support.path: [urls[3]], groups.path: [urls[4]]]
        identities = Dictionary(uniqueKeysWithValues: urls.map { ($0.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64($0.path.hashValue)), size: 100, modificationTime: 1, kind: .directory)) })
    }
    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil || childrenByPath[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
