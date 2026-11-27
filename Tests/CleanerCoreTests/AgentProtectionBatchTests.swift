import Foundation
import XCTest
@testable import CleanerCore

final class AgentProtectionBatchTests: XCTestCase {
    func testProtectionAndEligibilityMatchScalarChecksAcrossBatchBoundaries() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let guarded = fixture.root.appendingPathComponent("guarded")
        try FileManager.default.createDirectory(at: guarded, withIntermediateDirectories: true)
        try Data([1]).write(to: guarded.appendingPathComponent("key"))
        let policy = ProtectionPolicy(entries: [ProtectedPath(url: guarded)], homeDirectory: fixture.home)
        let context = ScanContext(homeDirectory: fixture.home, activePaths: [fixture.root.appendingPathComponent("item-17")], protectionPolicy: policy)
        let inventory = try await scanner(fixture.root).scanAssetInventory(context: context)
        XCTAssertGreaterThan(inventory.assets.count, 256)
        XCTAssertTrue(inventory.isComplete)
        for asset in inventory.assets {
            let unprotected = asset.candidate.replacing(risk: .safe, evidence: BatchProtectionAdapter.evidence)
            XCTAssertEqual(asset.candidate, policy.applying(to: unprotected), asset.candidate.url.path)
            let expected: AgentCleanupEligibility = asset.candidate.risk == .blocked || asset.activity == .active ? .protected : .recommended
            XCTAssertEqual(asset.cleanupEligibility, expected, asset.candidate.url.path)
            XCTAssertEqual(asset.resourceKind, .buildCache)
        }
        XCTAssertTrue(inventory.assets.contains { $0.candidate.isActive && $0.cleanupEligibility == .protected })
    }

    func testUnavailableProtectionBlocksAllItemsIncludingFinalPartialBatch() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let context = ScanContext(homeDirectory: fixture.home, protectionPolicy: .init(homeDirectory: fixture.home, isAvailable: false))
        let inventory = try await scanner(fixture.root).scanAssetInventory(context: context)
        XCTAssertEqual(inventory.assets.count, 262)
        XCTAssertTrue(inventory.assets.allSatisfy {
            $0.candidate.risk == .blocked && $0.cleanupEligibility == .protected
                && $0.candidate.evidence.contains { $0.code == "protection-unavailable" }
        })
    }

    func testBudgetLimitedInventoryStillProtectsEveryPublishedItem() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let context = ScanContext(homeDirectory: fixture.home, protectionPolicy: .init(entries: [ProtectedPath(url: fixture.root)], homeDirectory: fixture.home))
        let inventory = try await AgentWorkspaceScanner(adapters: [BatchProtectionAdapter(root: fixture.root)], maximumAssets: 129)
            .scanAssetInventory(context: context)
        XCTAssertEqual(inventory.assets.count, 129)
        XCTAssertTrue(inventory.reachedBudget)
        XCTAssertFalse(inventory.isComplete)
        XCTAssertTrue(inventory.assets.allSatisfy { $0.candidate.risk == .blocked && $0.cleanupEligibility == .protected })
    }

    func testProtectionRootRedirectionDuringTraversalIsObservedBeforePublication() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let first = fixture.root.appendingPathComponent("item-0")
        let second = fixture.root.appendingPathComponent("item-1")
        let link = fixture.home.appendingPathComponent("protected-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let policy = ProtectionPolicy(entries: [ProtectedPath(url: link)], homeDirectory: fixture.home)
        let trigger = fixture.root.appendingPathComponent("zzz-trigger")
        try Data([1]).write(to: trigger)
        let mutation = BatchProtectionMutation(trigger: trigger, link: link, target: second)
        let inventory = try await scanner(fixture.root, mutation: mutation)
            .scanAssetInventory(context: .init(homeDirectory: fixture.home, fileSystem: OrderedBatchFileSystem(), protectionPolicy: policy))
        let applied = await mutation.applied
        XCTAssertTrue(applied)
        for path in [first, second] {
            let asset = try XCTUnwrap(inventory.assets.first { $0.candidate.url == path })
            XCTAssertEqual(asset.candidate.risk, .blocked, "Both the saved and current physical protection targets stay protected")
            XCTAssertEqual(asset.cleanupEligibility, .protected)
        }
    }

    func testCandidatePhysicalPathIsRecheckedAfterTraversal() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let secret = fixture.home.appendingPathComponent(".ssh/key")
        try FileManager.default.createDirectory(at: secret.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: secret)
        let earlyFile = fixture.root.appendingPathComponent("item-0")
        let trigger = fixture.root.appendingPathComponent("zzz-trigger")
        try Data([1]).write(to: trigger)
        let mutation = BatchProtectionMutation(trigger: trigger, link: earlyFile, target: secret)
        let inventory = try await scanner(fixture.root, mutation: mutation)
            .scanAssetInventory(context: .init(homeDirectory: fixture.home, fileSystem: OrderedBatchFileSystem()))
        let applied = await mutation.applied
        XCTAssertTrue(applied)
        let asset = try XCTUnwrap(inventory.assets.first { $0.candidate.url == earlyFile })
        XCTAssertEqual(asset.candidate.risk, .blocked)
        XCTAssertEqual(asset.cleanupEligibility, .protected)
        XCTAssertTrue(asset.candidate.evidence.contains { $0.code == "protected-by-policy" })
    }

    func testNewProtectionAfterScanStillRefusesExecution() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let file = fixture.root.appendingPathComponent("item-0")
        let inventory = try await scanner(fixture.root).scanAssetInventory(context: .init(homeDirectory: fixture.home))
        let candidate = try XCTUnwrap(inventory.assets.first { $0.candidate.url == file }?.candidate)
        XCTAssertEqual(candidate.risk, .safe)
        let plan = try PlanBuilder(ruleVersion: "fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
        let policy = ProtectionPolicy(entries: [ProtectedPath(url: file)], homeDirectory: fixture.home)
        let executor = CleanupExecutor(pathPolicy: .init(homeDirectory: fixture.home),
            quarantineRoot: fixture.home.appendingPathComponent("Quarantine"), currentRuleVersion: "fixture", loadProtection: { policy })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .skippedProtected)
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
    }

    private func fixture() throws -> (home: URL, root: URL) {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/agent-protection-batch/fixtures/" + UUID().uuidString)
        let root = home.appendingPathComponent("agent/completed-cache")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<261 { try Data([1]).write(to: root.appendingPathComponent("item-\(index)")) }
        return (home, root)
    }

    private func scanner(_ root: URL, mutation: BatchProtectionMutation? = nil) -> AgentWorkspaceScanner {
        AgentWorkspaceScanner(adapters: [BatchProtectionAdapter(root: root, mutation: mutation)], directorySnapshot: .init())
    }
}

private struct BatchProtectionAdapter: AgentProviderAdapter {
    static let evidence = [Evidence(code: "fixture", summary: "Completed reproducible cache")]
    let provider = AgentProvider.codex
    let scope = AgentScope.global
    let rootRelativePaths: [String] = []
    let root: URL
    var mutation: BatchProtectionMutation? = nil
    func discoverRoots(context: ScanContext) async -> [AgentRoot] { [.init(provider: provider, scope: scope, url: root)] }
    func classify(url: URL, root: AgentRoot, context: ScanContext) async -> AgentClassification {
        try? await mutation?.visit(url)
        return .init(kind: .reproducibleCache, category: .cache, risk: .safe, evidence: Self.evidence)
    }
}

private actor BatchProtectionMutation {
    let trigger: URL
    let link: URL
    let target: URL
    private(set) var applied = false
    init(trigger: URL, link: URL, target: URL) { self.trigger = trigger; self.link = link; self.target = target }
    func visit(_ url: URL) throws {
        guard url == trigger else { return }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        applied = true
    }
}

private struct OrderedBatchFileSystem: FileSystemAccess {
    private let base = LocalFileSystem()
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func children(of url: URL) async throws -> [URL] { try await base.children(of: url).sorted { $0.path < $1.path } }
    func isReadable(_ url: URL) async -> Bool { await base.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
