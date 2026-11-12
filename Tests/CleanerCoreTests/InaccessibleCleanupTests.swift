import XCTest
@testable import CleanerCore

final class InaccessibleCleanupTests: XCTestCase {
    func testDeniedEntriesAreNotCleanupCandidatesAndCannotBePlanned() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".access-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches")
        for name in ["read-denied", "delete-denied", "available"] {
            let folder = cache.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1]).write(to: folder.appendingPathComponent("payload"))
        }
        let context = ScanContext(homeDirectory: home, fileSystem: AccessFixtureFileSystem())
        let scanner = SystemCleanupScanner(applicationScanner: .init(applicationRoots: []))
        let report = await scanner.scan(context: context, pack: try BundledCleanupRules.pack())
        XCTAssertEqual(report.candidates.map(\.displayName), ["available"])
        XCTAssertTrue(report.failures.contains { $0.reason == .access }, "internal diagnostics are preserved without showing denied locations in cleanup")
        let denied = cache.appendingPathComponent("read-denied")
        let old = CleanupCandidate(url: denied, displayName: "old", category: .cache, bytes: 99, risk: .safe,
            evidence: [.init(code: "scan-incomplete-access", summary: "denied")], identity: try await LocalFileSystem().identity(at: denied),
            source: .general, lastAccessDate: nil, isActive: false)
        XCTAssertTrue(CleanupCandidateVisibility.remaining(candidates: [old], cleanedCandidateIDs: []).isEmpty)
        XCTAssertThrowsError(try PlanBuilder().build(candidates: [old], selectedIDs: [old.id]))
        let plan = CleanupPlan(createdAt: Date(), expiresAt: Date().addingTimeInterval(60), items: [.init(candidate: old, isSelected: true, evidenceDigest: "fixture")])
        let receipt = await CleanupExecutor(pathPolicy: .init(homeDirectory: home), quarantineRoot: home.appendingPathComponent("Recovery"),
            currentRuleVersion: plan.ruleVersion).execute(plan: plan)
        XCTAssertNotNil(receipt.rejectionReason)
        XCTAssertTrue(FileManager.default.fileExists(atPath: denied.appendingPathComponent("payload").path))
    }

    func testUnprovenRuntimeCachesUseTheSameManualRuleForEveryName() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".generic-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let rules = ["Alpha", "Beta"].map { name in
            CleanupRule(ruleID: "fixture.\(name)", category: .developerCache, relativePaths: [name], minimumAgeDays: 0,
                defaultRisk: .review, granularity: .root)
        }
        for name in ["Alpha", "Beta"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true) }
        let candidates = try await CleanupRuleEngine(pack: .init(version: "fixture", issuedAt: Date(), rules: rules, revokedRuleIDs: [])).scan(context: .init(homeDirectory: home))
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.requiresExplicitSelection == true })
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: candidates).isEmpty)
    }
}

private struct AccessFixtureFileSystem: FileSystemAccess {
    let base = LocalFileSystem()
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func children(of url: URL) async throws -> [URL] {
        if url.lastPathComponent == "read-denied" { throw NSError(domain: NSPOSIXErrorDomain, code: 1) }
        return try await base.children(of: url)
    }
    func isReadable(_ url: URL) async -> Bool { true }
    func isWritable(_ url: URL) async -> Bool { true }
    func isDeletable(_ url: URL) async -> Bool { url.lastPathComponent != "delete-denied" }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
