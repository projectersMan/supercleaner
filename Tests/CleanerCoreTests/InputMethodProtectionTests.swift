import XCTest
@testable import CleanerCore

final class InputMethodProtectionTests: XCTestCase {
    func testInputMethodInventoryPreventsCacheAndResidueCleanup() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("input-method-protection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let inputRoot = home.appendingPathComponent("Library/Input Methods")
        let app = inputRoot.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "TEST.INPUT.Example", "CFBundleName": "Example"],
            format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let cache = home.appendingPathComponent("Library/Caches/test.input.example")
        let other = home.appendingPathComponent("Library/Caches/test.other")
        for directory in [cache, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("payload"))
        }
        let context = ScanContext(homeDirectory: home)
        let scanner = ApplicationScanner(applicationRoots: [inputRoot])
        let inventory = await scanner.installedApplications(context: context)
        XCTAssertEqual(inventory.applications.map(\.bundleIdentifier), ["TEST.INPUT.Example"])
        XCTAssertEqual(inventory.applications.first?.isSystem, false)
        XCTAssertEqual(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: inventory.applications).count, 1)
        let installed = try XCTUnwrap(inventory.applications.first)
        let plan = try await UninstallPlanner(scanner: scanner).buildPlan(installed, associations: [
            .init(url: cache, kind: .cache, ownershipEvidence: "fixture", containsUserData: false, isShared: false, risk: .safe)
        ], context: context).plan
        let body = try XCTUnwrap(plan.items.first { $0.candidate.url.path == installed.bundleURL.path })
        XCTAssertEqual(body.candidate.risk, .review)
        XCTAssertTrue(plan.items.first { $0.candidate.url.path == cache.path }?.candidate.risk.isSelectable == false,
            "input-method caches rejected at execution must not be selectable in the uninstall plan")
        let report = await SystemCleanupScanner(applicationScanner: scanner).scan(context: context, pack: nil)
        XCTAssertFalse(report.candidates.contains { $0.url.path == cache.path || $0.url.path.hasPrefix(cache.path + "/") })
        XCTAssertTrue(report.candidates.contains { $0.url.path == other.path })
        let candidate = CleanupCandidate(url: cache, displayName: "input cache", category: .cache, bytes: 1, risk: .safe,
            evidence: [], identity: try await LocalFileSystem().identity(at: cache), source: .general,
            lastAccessDate: nil, isActive: false)
        do { try await InputMethodProtection.validate(candidate, context: context); XCTFail("legacy cache plans must also be refused") }
        catch is PathPolicyError { }
        let broken = inputRoot.appendingPathComponent("Unknown.app/Contents")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: broken.appendingPathComponent("Info.plist"))
        let unknown = await SystemCleanupScanner(applicationScanner: scanner).scan(context: context, pack: nil)
        XCTAssertFalse(unknown.candidates.contains { $0.url.path == other.path },
            "incomplete input-method identity must not grant cleanup eligibility to an unknown cache")
        let legacyOther = CleanupCandidate(url: other, displayName: "unknown cache", category: .cache, bytes: 1, risk: .safe,
            evidence: [], identity: try await LocalFileSystem().identity(at: other), source: .general,
            lastAccessDate: nil, isActive: false)
        do { try await InputMethodProtection.validate(legacyOther, context: context); XCTFail("incomplete inventory must refuse old cache plans") }
        catch is PathPolicyError { }
    }
}
