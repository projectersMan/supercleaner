import XCTest
@testable import CleanerCore

final class CacheReferenceCleanupTests: XCTestCase {
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".managed-cache-\(UUID())")
    }
    private func put(_ data: Data, _ path: String, home: URL) throws {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    func testPlaywrightOnlyPreselectsUnusedVersionsAndRechecksNewReferences() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put(Data([1]), "Library/Caches/ms-playwright/chromium-100/payload", home: home)
        try put(Data([2]), "Library/Caches/ms-playwright/chromium-200/payload", home: home)
        let package = home.appendingPathComponent("project/node_modules/playwright-core")
        try put(Data(package.path.utf8), "Library/Caches/ms-playwright/.links/client", home: home)
        let json = #"{"browsers":[{"name":"chromium","revision":"200"}]}"#
        try put(Data(json.utf8), "project/node_modules/playwright-core/browsers.json", home: home)
        let rule = try XCTUnwrap(BundledCleanupRules.pack().rules.first { $0.ruleID == "developer.playwright-browsers" })
        let engine = CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: [rule], revokedRuleIDs: []))
        let context = ScanContext(homeDirectory: home, activeProcessNames: ["node"])
        let found = try await engine.scan(context: context)
        let old = try XCTUnwrap(found.first { $0.displayName == "chromium-100" })
        let selected = CleanupRecommendationPolicy().defaultSelectedIDs(for: found)
        XCTAssertEqual(selected, [old.id])
        try await engine.validateForExecution(old, context: context)
        try put(Data(json.replacingOccurrences(of: "200", with: "100").utf8), "project/node_modules/playwright-core/browsers.json", home: home)
        do { try await engine.validateForExecution(old, context: context); XCTFail("newly referenced browser must not be deleted automatically") }
        catch { }
    }
    func testCapabilitiesDoNotDependOnSoftwareOrRuleNames() async throws {
        let home = fixture(); defer { try? FileManager.default.removeItem(at: home) }
        try put(Data([1]), "GenericCache/toolchain-7/payload", home: home)
        try put(Data([2]), "GenericCache/toolchain-8/payload", home: home)
        let client = home.appendingPathComponent("Client")
        try put(Data(client.path.utf8), "GenericCache/registrations/client", home: home)
        try put(Data(#"{"artifacts":[{"component":"toolchain","version":"8"}]}"#.utf8), "Client/dependencies.json", home: home)
        let descriptor = try JSONDecoder().decode(CacheReferenceDescriptor.self, from: Data(#"{"registryDirectory":"registrations","manifestFile":"dependencies.json","entriesKey":"artifacts","nameKey":"component","revisionKey":"version","artifactPattern":"^[a-z]+-[0-9]+$","replaceNameHyphensWithUnderscores":false}"#.utf8))
        let rule = CleanupRule(ruleID: "generic-fixture", category: .developerCache, relativePaths: ["GenericCache"],
            minimumAgeDays: 0, defaultRisk: .safe, defaultSelection: true, referenceInventory: descriptor)
        let engine = CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: [rule], revokedRuleIDs: []))
        let context = ScanContext(homeDirectory: home)
        let found = try await engine.scan(context: context)
        XCTAssertEqual(found.count, 2, "reference metadata must not become a cleanup target")
        XCTAssertEqual(found.filter { CleanupRecommendationPolicy().defaultSelectedIDs(for: found).contains($0.id) }.map(\.displayName), ["toolchain-7"])
        try FileManager.default.removeItem(at: client.appendingPathComponent("dependencies.json"))
        let uncertain = try await engine.scan(context: context)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: uncertain).isEmpty)
        try FileManager.default.removeItem(at: client)
        let unreferenced = try await engine.scan(context: context)
        XCTAssertEqual(CleanupRecommendationPolicy().defaultSelectedIDs(for: unreferenced).count, 2,
            "a registration whose client no longer exists must not retain old artifacts")

        let cacheRule = CleanupRule(ruleID: "unrelated-rule-name", category: .developerCache, relativePaths: ["Rebuildable"],
            minimumAgeDays: 30, defaultRisk: .review, activeProcessNames: ["generic-worker"], regenerable: true)
        try put(Data([3]), "Rebuildable/content", home: home)
        let cacheEngine = CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: [cacheRule], revokedRuleIDs: []))
        let cache = try await cacheEngine.scan(context: .init(homeDirectory: home, activeProcessNames: ["generic-worker"]))
        XCTAssertEqual(CleanupRecommendationPolicy().defaultSelectedIDs(for: cache).count, 1)
    }

}
