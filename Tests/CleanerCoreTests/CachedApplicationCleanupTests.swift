import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class CachedApplicationCleanupTests: XCTestCase {
    func testSignedUpdateCacheIsManualAndSupportsCleanupAndRestore() async throws {
        let fixture = try fixture(suffix: ".ShipIt")
        let context = ScanContext(homeDirectory: fixture.home, activePaths: [fixture.cache],
            runningBundleIdentifiers: [fixture.owner.bundleIdentifier])
        let scanner = ApplicationCleanupScanner()
        let candidate = try await candidate(fixture, context: context)
        XCTAssertTrue(candidate.risk.isSelectable)
        XCTAssertTrue(candidate.requiresExplicitSelection == true)
        XCTAssertFalse(candidate.defaultSelection == true)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: candidate), .retain)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: [candidate]).isEmpty)
        try await scanner.validateForExecution(candidate, context: context, applications: [fixture.owner])
        let plan = try PlanBuilder(ruleVersion: "cache-fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: fixture.home),
            quarantineRoot: fixture.home.appendingPathComponent("quarantine"), currentRuleVersion: "cache-fixture",
            validateCandidate: { try await scanner.validateForExecution($0, context: context, applications: [fixture.owner]) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.disposition, .quarantined)
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.disposition, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.bundle.appendingPathComponent("Contents/Resources/python/.env").path))
    }

    func testUnsignedUnrelatedAndTamperedBundlesDoNotBypassSensitiveChecks() async throws {
        for mode in ["unsigned", "unrelated", "tampered", "different-team"] {
            let fixture = try fixture(cachedIdentifier: mode == "unrelated" ? "example.other" : nil, signCache: mode != "unsigned", ownerTeam: mode == "different-team" ? "OTHERTEAM" : nil)
            if mode == "tampered" {
                try write("changed", to: fixture.bundle.appendingPathComponent("Contents/Resources/python/.env"))
            }
            let candidate = try await candidate(fixture)
            XCTAssertEqual(candidate.risk, .blocked, mode)
        }
    }

    func testSecretsEscapingLinksAndUserProtectionsRemainBlocked() async throws {
        for mode in ["secret", "link", "protection"] {
            let fixture = try fixture()
            var policy = ProtectionPolicy(homeDirectory: fixture.home)
            if mode == "secret" { try write("fixture", to: fixture.cache.appendingPathComponent("credentials.json")) }
            if mode == "link" {
                let outside = fixture.home.appendingPathComponent("outside.txt")
                try write("fixture", to: outside)
                try FileManager.default.createSymbolicLink(at: fixture.cache.appendingPathComponent("escape"), withDestinationURL: outside)
            }
            if mode == "protection" {
                policy = ProtectionPolicy(entries: [.init(url: fixture.bundle)], homeDirectory: fixture.home)
            }
            let candidate = try await candidate(fixture, context: ScanContext(homeDirectory: fixture.home, protectionPolicy: policy))
            XCTAssertEqual(candidate.risk, .blocked, mode)
        }
    }

    func testChangesAfterScanningAreRevalidatedBeforeCleanup() async throws {
        for mode in ["tampered", "link"] {
            let fixture = try fixture()
            let candidate = try await candidate(fixture)
            XCTAssertTrue(candidate.risk.isSelectable)
            if mode == "tampered" {
                try write("changed", to: fixture.bundle.appendingPathComponent("Contents/Resources/python/.env"))
            } else {
                let outside = fixture.home.appendingPathComponent("outside.txt")
                try write("fixture", to: outside)
                try FileManager.default.createSymbolicLink(at: fixture.cache.appendingPathComponent("escape"), withDestinationURL: outside)
            }
            do {
                try await ApplicationCleanupScanner().validateForExecution(candidate,
                    context: ScanContext(homeDirectory: fixture.home), applications: [fixture.owner])
                XCTFail("Changed update cache must be revalidated: \(mode)")
            } catch {}
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.cache.path))
        }
    }

    func testExactCacheIsIncludedInThePreparedUninstallListWhileAppRuns() async throws {
        let fixture = try fixture()
        let scanner = ApplicationScanner(applicationRoots: [fixture.home.appendingPathComponent("Applications")])
        let analyzer = ApplicationUninstallAnalyzer(scanner: scanner, planner: UninstallPlanner(scanner: scanner))
        let inventory = ApplicationInventory(applications: [fixture.owner], coverage: .init(), scannedAt: Date())
        let result = await analyzer.analyze(inventory: inventory, context: ScanContext(homeDirectory: fixture.home))
        let analysis = try XCTUnwrap(result.analysis(for: fixture.owner.id))
        XCTAssertNil(analysis.plan)
        XCTAssertTrue(analysis.preparedPlan?.items.contains { $0.candidate.url.path == fixture.cache.path } == true)
    }

    private struct Fixture {
        let home, cache, bundle: URL
        let owner: InstalledApplication
    }
    private func fixture(suffix: String = "", cachedIdentifier: String? = nil, signCache: Bool = true, ownerTeam: String? = nil) throws -> Fixture {
        let root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true).appendingPathComponent("CachedApp-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let home = root.standardizedFileURL
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let identifier = "example.CachedApp"
        let installed = home.appendingPathComponent("Applications/Fixture.app")
        try bundle(at: installed, identifier: identifier, sign: true)
        let cache = home.appendingPathComponent("Library/Caches/" + identifier + suffix)
        let cached = cache.appendingPathComponent("update/Fixture.app")
        try bundle(at: cached, identifier: cachedIdentifier ?? identifier, sign: signCache)
        let owner = InstalledApplication(bundleURL: installed, bundleIdentifier: identifier, name: "Fixture", version: "1",
            isRunning: true, isSystem: false, teamIdentifier: ownerTeam, applicationGroups: [], associatedBundleIdentifiers: [], applicationGroupsComplete: true)
        return Fixture(home: home, cache: cache, bundle: cached, owner: owner)
    }
    private func candidate(_ fixture: Fixture, context: ScanContext? = nil) async throws -> CleanupCandidate {
        let scanner = ApplicationCleanupScanner()
        let context = context ?? ScanContext(homeDirectory: fixture.home)
        let discovery = await scanner.discover(applications: [fixture.owner], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        return try XCTUnwrap(result.candidates.first { $0.url.path == fixture.cache.path },
            "targets=\(discovery.targets.map { $0.url.path }); discovery=\(discovery.failures); candidates=\(result.candidates.map { $0.url.path }); failures=\(result.failures)")
    }
    private func bundle(at url: URL, identifier: String, sign: Bool) throws {
        let executable = url.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": "Fixture",
            "CFBundleExecutable": "Fixture", "CFBundleVersion": "1", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        try write("public code", to: url.appendingPathComponent("Contents/Resources/messages/schema.json"))
        try write("public code", to: url.appendingPathComponent("Contents/Resources/cookies/index.js"))
        try write("EXAMPLE=1", to: url.appendingPathComponent("Contents/Resources/python/.env"))
        try FileManager.default.createSymbolicLink(atPath: url.appendingPathComponent("Contents/Resources/current").path,
            withDestinationPath: "messages")
        if sign {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--force", "--sign", "-", "--timestamp=none", url.path]
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
    }
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
