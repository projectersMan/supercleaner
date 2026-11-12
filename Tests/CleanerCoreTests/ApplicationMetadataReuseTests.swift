import XCTest
@testable import CleanerCore

final class ApplicationMetadataReuseTests: XCTestCase {
    func testNewAndRemovedApplicationsRemainVisibleToFreshInventory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-inventory-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First.app"), second = root.appendingPathComponent("Second.app")
        try makeBundle(first, identifier: "test.first")
        let scanner = ApplicationScanner(metadataProvider: MemoizingApplicationMetadataProvider(base: CountingApplicationMetadata()),
            applicationRoots: [root])
        let context = ScanContext(homeDirectory: root)
        let initial = await scanner.installedApplications(context: context)
        XCTAssertEqual(initial.applications.map(\.bundleIdentifier), ["test.first"])
        try makeBundle(second, identifier: "test.second")
        let added = await scanner.installedApplications(context: context)
        XCTAssertEqual(Set(added.applications.map(\.bundleIdentifier)), ["test.first", "test.second"])
        try FileManager.default.removeItem(at: first)
        let removed = await scanner.installedApplications(context: context)
        XCTAssertEqual(removed.applications.map(\.bundleIdentifier), ["test.second"])
    }

    func testReusesUnchangedMetadataAndInvalidatesEveryCodeInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-reuse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Main.app")
        try makeBundle(app, identifier: "test.main")
        let base = CountingApplicationMetadata()
        let provider = MemoizingApplicationMetadataProvider(base: base)
        _ = provider.metadata(for: app)
        for _ in 0..<20 { _ = provider.metadata(for: app) }
        XCTAssertEqual(base.count, 1, "unchanged apps must not repeat signature and metadata inspection for each cleanup item")
        try makeBundle(app, identifier: "test.changed")
        XCTAssertEqual(provider.metadata(for: app)?.bundleIdentifier, "test.changed")
        XCTAssertEqual(base.count, 2)
        let child = app.appendingPathComponent("Contents/Extensions/Share.appex")
        try makeBundle(child, identifier: "com.extension.independent")
        _ = provider.metadata(for: app)
        XCTAssertEqual(base.count, 3, "new extension directories invalidate the ownership metadata")
        try Data([2]).write(to: child.appendingPathComponent("Contents/MacOS/Main"))
        _ = provider.metadata(for: app)
        XCTAssertEqual(base.count, 4, "nested executable changes must invalidate signature reuse")
        let signature = app.appendingPathComponent("Contents/_CodeSignature")
        try FileManager.default.createDirectory(at: signature, withIntermediateDirectories: true)
        try Data([3]).write(to: signature.appendingPathComponent("CodeResources"))
        _ = provider.metadata(for: app)
        XCTAssertEqual(base.count, 5)
    }

    private func makeBundle(_ bundle: URL, identifier: String) throws {
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Main"],
            format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data([1]).write(to: contents.appendingPathComponent("MacOS/Main"))
    }
}

private final class CountingApplicationMetadata: ApplicationMetadataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }
    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        lock.withLock { calls += 1 }
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let identifier = info["CFBundleIdentifier"] else { return nil }
        return .init(bundleIdentifier: identifier, name: "Main", version: nil)
    }
}
