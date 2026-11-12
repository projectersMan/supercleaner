import XCTest
@testable import CleanerCore

final class CleanupClassificationTests: XCTestCase {
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".classification-\(UUID())")
    }
    private func put(_ path: String, home: URL) throws {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
    }
    func testUnrelatedToolProcessesDoNotRetainVerifiedDownloadCaches() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        for path in [".npm/_cacache/content/payload", "Library/Caches/pip/http-v2/payload", "Library/Caches/org.swift.swiftpm/repositories/payload"] {
            try put(path, home: home)
        }
        let pack = try BundledCleanupRules.pack()
        let rules = pack.rules.filter { ["developer.npm-cache", "developer.python-cache", "developer.package-cache"].contains($0.ruleID) }
        let found = try await CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: rules, revokedRuleIDs: []))
            .scan(context: .init(homeDirectory: home, activeProcessNames: ["node", "python", "swift"]))
        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(found.allSatisfy { CleanupRecommendationPolicy().disposition(for: $0) == .recommended })
    }
    func testReinstallableBrowserInternalLinkIsSelectableButNeverAutomatic() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let relative = "Library/Caches/ms-playwright/chromium/Chrome.app/Contents/Frameworks/Test.framework/Versions"
        try put(relative + "/A/payload", home: home)
        try FileManager.default.createSymbolicLink(atPath: home.appendingPathComponent(relative + "/Current").path, withDestinationPath: "A")
        let rule = try XCTUnwrap(BundledCleanupRules.pack().rules.first { $0.ruleID == "developer.playwright-browsers" })
        let engine = CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: [rule], revokedRuleIDs: []))
        let found = try await engine.scan(context: .init(homeDirectory: home))
        XCTAssertEqual(found.first?.risk, .review)
        XCTAssertEqual(found.first.map { CleanupRecommendationPolicy().disposition(for: $0) }, .retain)
        let external = home.appendingPathComponent("Documents/payload")
        try put("Documents/payload", home: home)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(relative + "/outside"), withDestinationURL: external)
        let protected = try await engine.scan(context: .init(homeDirectory: home))
        XCTAssertEqual(protected.first?.risk, .blocked)
    }
    func testArchivesNeverEnterAutomaticCleanup() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Developer/Xcode/Archives/release.xcarchive/payload", home: home)
        let found = try await CleanupRuleEngine(pack: BundledCleanupRules.pack()).scan(context: .init(homeDirectory: home))
        let archive = try XCTUnwrap(found.first { $0.displayName == "release.xcarchive" })
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: archive), .retain)
        XCTAssertEqual(archive.requiresExplicitSelection, true)
    }

    func testConfirmedResidueIsRecommendedAndPreselected() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        for path in ["Library/Application Support/com.removed.example/payload", "Library/Containers/com.removed.example/payload", "Library/Preferences/com.removed.example.plist"] { try put(path, home: home) }
        let found = await HistoricalResidueScanner().scan(context: .init(homeDirectory: home), inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(found.allSatisfy { $0.defaultSelection == true && $0.requiresExplicitSelection != true })
        XCTAssertEqual(CleanupRecommendationPolicy().defaultSelectedIDs(for: found), Set(found.map(\.id)))
        XCTAssertTrue(found.allSatisfy { CleanupRecommendationPolicy().disposition(for: $0) == .recommended })
    }

    func testUncertainInventoryIsRetainedButConfirmedSharedResidueIsPreselected() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Containers/com.removed.example/payload", home: home)
        try put("Library/Group Containers/TEAM.com.removed.example/payload", home: home)
        let scanner = HistoricalResidueScanner()
        let incomplete = await scanner.scan(context: .init(homeDirectory: home), inventory: .init(applications: [], coverage: .init(unavailableRoots: [home.appendingPathComponent("Applications")]), scannedAt: Date()))
        XCTAssertEqual(incomplete.count, 2)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: incomplete).isEmpty)
        let complete = await scanner.scan(context: .init(homeDirectory: home), inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(complete.first { $0.url.path.contains("Group Containers") }?.defaultSelection, true)
    }

    func testSharedGroupIdentifiersRequireCompleteDeclarationsAndExcludeOwners() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Group Containers/group.example.shared/payload", home: home)
        try put("Library/Group Containers/group.com.apple.shared/payload", home: home)
        let scanner = HistoricalResidueScanner()
        func app(groups: [String]?, complete: Bool) -> InstalledApplication {
            .init(bundleURL: home.appendingPathComponent("Applications/Other.app"), bundleIdentifier: "com.other.app",
                name: "Other", version: nil, isRunning: false, isSystem: false, applicationGroups: groups, applicationGroupsComplete: complete)
        }
        let unknown = await scanner.scan(context: .init(homeDirectory: home), inventory: .init(applications: [app(groups: [], complete: false)], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(unknown.count, 1)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: unknown).isEmpty)
        let known = await scanner.scan(context: .init(homeDirectory: home), inventory: .init(applications: [app(groups: [], complete: true)], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(known.count, 1)
        XCTAssertEqual(known.first?.defaultSelection, true)
        let owned = await scanner.scan(context: .init(homeDirectory: home), inventory: .init(applications: [app(groups: ["group.example.shared"], complete: true)], coverage: .init(), scannedAt: Date()))
        XCTAssertTrue(owned.isEmpty)
        let runningUnknown = await scanner.scan(context: .init(homeDirectory: home, runningBundleIdentifiers: ["com.external.app"]), inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: runningUnknown).isEmpty)
    }

    func testRunningAndProtectedResidueCannotBecomeDefaultSelection() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let relative = "Library/Containers/com.removed.example"
        try put(relative + "/payload", home: home)
        let inventory = ApplicationInventory(applications: [], coverage: .init(), scannedAt: Date())
        let scanner = HistoricalResidueScanner()
        let running = await scanner.scan(context: .init(homeDirectory: home, runningBundleIdentifiers: ["com.removed.example"]), inventory: inventory)
        XCTAssertTrue(running.isEmpty)
        let protected = await scanner.scan(context: .init(homeDirectory: home, protectionPolicy: .init(entries: [.init(url: home.appendingPathComponent(relative + "/payload"))], homeDirectory: home)), inventory: inventory)
        XCTAssertEqual(protected.first?.risk, .blocked)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: protected).isEmpty)
    }

    func testContainerWithIncompleteExtensionOwnershipIsNotPreselected() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Containers/com.extension.independent/payload", home: home)
        let app = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Parent.app"),
            bundleIdentifier: "com.example.parent", name: "Parent", version: nil, isRunning: false, isSystem: false,
            applicationGroups: [], applicationGroupsComplete: false)
        let found = await HistoricalResidueScanner().scan(context: .init(homeDirectory: home),
            inventory: .init(applications: [app], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(found.first?.defaultSelection, false)
        XCTAssertEqual(found.first?.requiresExplicitSelection, true)
    }

    func testUnreadablePayloadDoesNotRequireReadingContainerMetadata() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Containers/com.removed.example/.com.apple.containermanagerd.metadata.plist", home: home)
        let fs = ClassificationFileSystem(home: home, unreadableNames: [".com.apple.containermanagerd.metadata.plist"])
        let found = await HistoricalResidueScanner().scan(context: .init(homeDirectory: home, fileSystem: fs), inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.defaultSelection, true)
    }

    func testContainerLinksDoNotPreventCleanupOrTouchTheirTargets() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put("Library/Containers/com.removed.example/payload", home: home)
        try put("Documents/keep", home: home)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Library/Containers/com.removed.example/link"), withDestinationURL: home.appendingPathComponent("Documents"))
        let context = ScanContext(homeDirectory: home, fileSystem: ClassificationFileSystem(home: home))
        let found = await HistoricalResidueScanner().scan(context: context, inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        let candidate = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(candidate.bytes, 1, "must not count files outside the container")
        XCTAssertEqual(CleanupRecommendationPolicy().defaultSelectedIDs(for: found), [candidate.id])
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: found, selectedIDs: [candidate.id])
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: plan.ruleVersion,
            validateCandidate: { try await HistoricalResidueExecutionValidator().validate($0, context: context) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("Documents/keep")), Data([1]))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("Documents/keep")), Data([1]))
        let secondPlan = try PlanBuilder(ruleVersion: "fixture").build(candidates: found, selectedIDs: [candidate.id])
        let secondReceipt = await executor.execute(plan: secondPlan)
        XCTAssertEqual(secondReceipt.results.first?.status, .succeeded)
        let purged = await executor.purge(receipt: secondReceipt)
        XCTAssertEqual(purged.results.first?.status, .succeeded)
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("Documents/keep")), Data([1]))

    }

    func testInstalledAppPrefSuffixesAndExtensionsAreNotOrphaned() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/Photo.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.photo", "CFBundleName": "Photo"], format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
        for path in ["Library/Preferences/com.example.photo.flags.123.plist", "Library/Containers/com.example.photo.Share/payload",
                     "Library/Application Support/com.example.photo2/payload"] { try put(path, home: home) }
        let found = await HistoricalResidueScanner().scan(context: .init(homeDirectory: home, fileSystem: ClassificationFileSystem(home: home)))
        XCTAssertFalse(found.contains { $0.displayName == "com.example.photo.flags.123.plist" })
        XCTAssertFalse(found.contains { $0.displayName == "com.example.photo.Share" })
        XCTAssertEqual(found.first { $0.displayName == "com.example.photo2" }?.risk, .safe)
    }
}

private struct ClassificationFileSystem: FileSystemAccess {
    let home: URL
    var unreadableNames: Set<String> = []
    private let base = LocalFileSystem()
    private func allowed(_ url: URL) -> Bool { url.path == home.path || url.path.hasPrefix(home.path + "/") }
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func children(of url: URL) async throws -> [URL] { allowed(url) ? try await base.children(of: url) : [] }
    func fileExists(_ url: URL) async -> Bool { allowed(url) ? await base.fileExists(url) : false }
    func isReadable(_ url: URL) async -> Bool { unreadableNames.contains(url.lastPathComponent) ? false : await base.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
