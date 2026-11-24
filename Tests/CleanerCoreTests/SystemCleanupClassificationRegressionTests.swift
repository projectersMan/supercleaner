import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class SystemCleanupClassificationRegressionTests: XCTestCase {
    func testBundledDownloadCachesJoinRecommendedDefaults() async throws {
        let home = try fixture()
        for path in ["Library/Caches/pip/http-v2/payload", ".npm/_cacache/content/payload",
                     "Library/Caches/org.swift.swiftpm/repositories/payload", "Library/Caches/Homebrew/downloads/payload"] {
            try put(path, home: home)
        }
        let context = ScanContext(homeDirectory: home, activeProcessNames: ["python", "node", "swift", "brew"])
        let result = await SystemCleanupScanner(applicationScanner: ApplicationScanner(
            applicationRoots: [home.appendingPathComponent("Applications")])).scan(context: context, pack: try BundledCleanupRules.pack())
        let policy = CleanupRecommendationPolicy()
        XCTAssertEqual(result.candidates.count, 4)
        XCTAssertTrue(result.candidates.allSatisfy { policy.disposition(for: $0) == .deepClean })
        XCTAssertEqual(policy.breakdown(for: result.candidates).recommendedGroupCandidates.count, 4)
        XCTAssertTrue(policy.breakdown(for: result.candidates).deepReviewCandidates.isEmpty)
        XCTAssertEqual(policy.defaultSelectedIDs(for: result.candidates), Set(result.candidates.map(\.id)))
        XCTAssertEqual(policy.selectedIDs(for: result.candidates, mode: .smart, currentSelection: []), Set(result.candidates.map(\.id)))
        XCTAssertEqual(policy.selectedIDs(for: result.candidates, mode: .deep, currentSelection: []), Set(result.candidates.map(\.id)))
        XCTAssertEqual(Set(DefaultCleanupPolicy().selection(for: report(result.candidates)).systemCleanup.map(\.id)), Set(result.candidates.map(\.id)))
    }

    func testUnknownCacheAndActualOrphanedUserDataAreRetained() async throws {
        let home = try fixture()
        for path in ["Library/Caches/example.unknown/offline.sqlite", "Library/Application Support/example.removed/documents.sqlite",
                     "Library/Containers/example.removed/Data/Documents/document.txt", "Library/Preferences/example.removed.plist"] {
            try put(path, home: home)
        }
        let result = await SystemCleanupScanner(applicationScanner: ApplicationScanner(
            applicationRoots: [home.appendingPathComponent("Applications")])).scan(context: .init(homeDirectory: home), pack: try BundledCleanupRules.pack())
        let policy = CleanupRecommendationPolicy()
        XCTAssertEqual(result.candidates.count, 4)
        XCTAssertTrue(result.candidates.allSatisfy { policy.disposition(for: $0) == .retain })
        XCTAssertEqual(policy.breakdown(for: result.candidates).deepReviewCandidates.count, 4)
        XCTAssertTrue(policy.selectedIDs(for: result.candidates, mode: .deep, currentSelection: []).isEmpty)
        XCTAssertTrue(policy.defaultSelectedIDs(for: result.candidates).isEmpty)
    }

    func testApplicationNetworkCacheIsDeepButLocalGPUCacheAndLogsAreRecommended() async throws {
        let home = try fixture()
        for path in ["Library/Application Support/Example/Cache/download", "Library/Application Support/Example/GPUCache/shader",
                     "Library/Logs/example.fixture/session.log"] {
            try put(path, home: home)
        }
        let app = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Example.app"),
            bundleIdentifier: "example.fixture", name: "Example", version: nil, isRunning: false, isSystem: false)
        let scanner = ApplicationCleanupScanner()
        let context = ScanContext(homeDirectory: home)
        let discovery = await scanner.discover(applications: [app], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        let policy = CleanupRecommendationPolicy()
        let network = try XCTUnwrap(result.candidates.first { $0.url.lastPathComponent == "Cache" })
        let gpu = try XCTUnwrap(result.candidates.first { $0.url.lastPathComponent == "GPUCache" })
        let log = try XCTUnwrap(result.candidates.first { $0.url.lastPathComponent == "session.log" })
        XCTAssertEqual(policy.disposition(for: network), .deepClean)
        XCTAssertEqual(policy.disposition(for: gpu), .recommended)
        XCTAssertEqual(policy.disposition(for: log), .recommended)
        XCTAssertEqual(policy.defaultSelectedIDs(for: result.candidates), [network.id, gpu.id, log.id])
    }

    func testReviewCategoryAloneDoesNotProveDeepCleanupSafety() {
        let candidate = CleanupCandidate(url: URL(fileURLWithPath: "/fixture/unknown"), displayName: "Unknown",
            category: .developerCache, bytes: 10, risk: .review, evidence: [],
            identity: .init(device: 1, inode: 1, size: 10, modificationTime: 1, kind: .directory),
            source: .general, lastAccessDate: nil, isActive: false, defaultSelection: false)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: candidate), .retain)
        XCTAssertTrue(CleanupRecommendationPolicy().selectedIDs(for: [candidate], mode: .deep, currentSelection: []).isEmpty)
    }

    func testSafeRiskWithoutAnExplicitLowImpactRecommendationIsRetained() {
        let candidate = CleanupCandidate(url: URL(fileURLWithPath: "/fixture/unclassified"), displayName: "Unclassified",
            category: .cache, bytes: 10, risk: .safe, evidence: [],
            identity: .init(device: 1, inode: 1, size: 10, modificationTime: 1, kind: .directory),
            source: .general, lastAccessDate: nil, isActive: false)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: candidate), .retain)
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: [candidate]).isEmpty)
    }

    func testCredentialsInsideHistoricalUserDataRemainProtected() async throws {
        let home = try fixture()
        try put("Library/Application Support/example.removed/credentials.json", home: home)
        let found = await HistoricalResidueScanner().scan(context: .init(homeDirectory: home),
            inventory: .init(applications: [], coverage: .init(), scannedAt: Date()))
        let candidate = try XCTUnwrap(found.first)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: candidate), .protected)
        XCTAssertFalse(candidate.risk.isSelectable)
        XCTAssertEqual(CleanupRecommendationPolicy().breakdown(for: found).deepReviewCandidates.map(\.id), [candidate.id])
        XCTAssertTrue(CleanupRecommendationPolicy().defaultSelectedIDs(for: found).isEmpty)
    }

    func testDefaultModeIsRecommendedAndDeepRequiresAnExplicitChoice() {
        XCTAssertEqual(CleanupMode.defaultMode, .smart)
        XCTAssertTrue(CleanupMode.userFacingCases.contains(.smart))
        XCTAssertTrue(CleanupMode.userFacingCases.contains(.deep))
    }

    private func fixture() throws -> URL {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/system-cleanup-classification/\(UUID())")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Applications"), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return home
    }

    private func put(_ path: String, home: URL) throws {
        let file = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
    }

    private func report(_ candidates: [CleanupCandidate]) -> SystemScanReport {
        SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [:], generalCandidates: candidates,
            applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: [])
    }
}
