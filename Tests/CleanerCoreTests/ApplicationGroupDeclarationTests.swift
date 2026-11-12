import XCTest
@testable import CleanerCore

final class ApplicationGroupDeclarationTests: XCTestCase {
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".group-declarations-\(UUID())")
    }

    func testNestedExtensionDeclarationCountsEvenWhenMainAppHasNone() throws {
        let root = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Main.app")
        let child = app.appendingPathComponent("Contents/PlugIns/Share.appex")
        try makeSignedBundle(child, identifier: "com.example.extension", group: "group.example.shared")
        try makeSignedBundle(app, identifier: "com.example.main", group: nil)
        let metadata = try XCTUnwrap(BundleApplicationMetadataProvider(includeSharedDeclarations: true).metadata(for: app))
        XCTAssertEqual(metadata.applicationGroups, ["group.example.shared"])
        XCTAssertEqual(metadata.applicationGroupsComplete, true)
    }

    func testUnknownExtensionAndExternalCodeLinkKeepCoverageIncomplete() throws {
        let root = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Main.app")
        let child = app.appendingPathComponent("Contents/Frameworks/Nested/Share.appex")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let scanner = ApplicationGroupDeclarationScanner { url in
            .init(groups: url.path == child.path ? ["group.example.shared"] : [], complete: url.path != child.path)
        }
        let result = scanner.scan(app)
        XCTAssertEqual(result.groups, ["group.example.shared"])
        XCTAssertFalse(result.complete)
        let external = root.appendingPathComponent("External.app")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("Contents/External.app"), withDestinationURL: external)
        let links = ApplicationGroupDeclarationScanner { _ in .init(groups: [], complete: true) }.scan(app)
        XCTAssertFalse(links.complete)
    }

    func testExtensionWithIndependentIdentifierInExtensionsDirectoryStaysOwned() throws {
        let root = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Main.app")
        let child = app.appendingPathComponent("Contents/Extensions/Share.appex")
        try makeSignedBundle(child, identifier: "com.extension.independent.share", group: nil)
        try makeSignedBundle(app, identifier: "com.example.main", group: nil)
        let metadata = try XCTUnwrap(BundleApplicationMetadataProvider(includeSharedDeclarations: true).metadata(for: app))
        XCTAssertTrue(metadata.associatedBundleIdentifiers?.contains("com.extension.independent.share") == true,
            "a bundled extension's data must stay owned even when its identifier is not prefixed by the main app")
    }

    func testCoverageSurvivesRunningStateAndLegacyReportsStayUnverified() throws {
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Example.app"), bundleIdentifier: "com.example.app",
            name: "Example", version: nil, isRunning: false, isSystem: false, applicationGroups: [], applicationGroupsComplete: true)
        XCTAssertEqual(app.withRunningState(true).applicationGroupsComplete, true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any])
        object.removeValue(forKey: "applicationGroupsComplete")
        let old = try JSONDecoder().decode(InstalledApplication.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.applicationGroupsComplete)
    }

    func testNoSharedContainersDoesNotInspectNestedApplicationCode() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let app = InstalledApplication(bundleURL: home.appendingPathComponent("Absent.app"), bundleIdentifier: "example.app",
            name: "Example", version: nil, isRunning: false, isSystem: false)
        let inventory = ApplicationInventory(applications: [app], coverage: .init(), scannedAt: Date())
        let context = ScanContext(homeDirectory: home)
        let absent = await inventory.completingSharedGroupDeclarations(ifNeededFor: context)
        XCTAssertNil(absent.applications.first?.applicationGroups, "no directory means no declaration scan")
        let containers = home.appendingPathComponent("Library/Group Containers")
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
        let empty = await inventory.completingSharedGroupDeclarations(ifNeededFor: context)
        XCTAssertNil(empty.applications.first?.applicationGroups, "empty directory means no declaration scan")
        try FileManager.default.createDirectory(at: containers.appendingPathComponent("group.example"), withIntermediateDirectories: true)
        let relevant = await inventory.completingSharedGroupDeclarations(ifNeededFor: context)
        XCTAssertEqual(relevant.applications.first?.applicationGroups, [])
        XCTAssertEqual(relevant.applications.first?.applicationGroupsComplete, false, "unreadable app cannot prove an unowned container")
    }

    func testExpiredDeclarationBudgetStopsTraversalAndKeepsCoverageIncomplete() throws {
        let root = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Main.app")
        let resource = app.appendingPathComponent("Contents/Resources/large/payload")
        try FileManager.default.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: resource)
        var inspected: [URL] = []
        let scanner = ApplicationGroupDeclarationScanner { url in
            inspected.append(url)
            return .init(groups: [], complete: true)
        }

        let result = scanner.scan(app, deadline: .distantPast, maximumEntries: 1)

        XCTAssertFalse(result.complete)
        XCTAssertEqual(inspected, [app.resolvingSymlinksInPath().standardizedFileURL],
                       "an exhausted budget must not continue walking application resources")
    }

    private func makeSignedBundle(_ url: URL, identifier: String, group: String?) throws {
        let contents = url.appendingPathComponent("Contents")
        let binary = contents.appendingPathComponent("MacOS/Main")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Main", "CFBundlePackageType": url.pathExtension == "app" ? "APPL" : "XPC!"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let entitlements = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: entitlements) }
        let claims: [String: Any] = group.map { ["com.apple.security.application-groups": [$0]] } ?? [:]
        try PropertyListSerialization.data(fromPropertyList: claims, format: .xml, options: 0).write(to: entitlements)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--entitlements", entitlements.path, url.path]
        let output = Pipe(); process.standardError = output
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
