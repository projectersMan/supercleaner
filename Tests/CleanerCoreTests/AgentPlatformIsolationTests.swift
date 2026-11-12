import Foundation
import XCTest
@testable import CleanerCore

final class AgentPlatformIsolationTests: XCTestCase {
    private func input(_ id: String, _ platform: AgentProvider, kind: AgentOverlapKind = .skill) -> AgentOverlapInput {
        .init(id: id, kind: kind, title: id, description: "Search source files", features: ["Search source files"], platform: platform)
    }

    func testOnlySamePlatformAndKindAreCalculatedOrRecommended() async throws {
        let inputs = [input("codex-a", .codex), input("codex-b", .codex), input("claude", .claude),
            input("mcp-a", .codex, kind: .mcp), input("mcp-b", .codex, kind: .mcp), input("mcp-claude", .claude, kind: .mcp)]
        let analyzer = AgentOverlapAnalyzer(provider: PlatformEmbedding(), modelVersion: "test", policy: try .load())
        let result = try await analyzer.analyze(inputs: inputs, index: .init())
        XCTAssertEqual(result.calculatedPairCount, 2)
        XCTAssertEqual(result.index.matches.count, 2)
        for pair in result.index.matches.values {
            XCTAssertTrue(result.index.entries[pair.firstID]!.canCompare(with: result.index.entries[pair.secondID]!))
        }
        XCTAssertEqual(result.matches.first { $0.sourceID == "claude" }?.coverage, 0)
        XCTAssertEqual(result.matches.first { $0.sourceID == "mcp-claude" }?.coverage, 0)
        let selected = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: Set(inputs.map(\.id)),
            eligibleIDs: Set(inputs.map(\.id)), cacheIDs: Set(inputs.map(\.id)), manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        XCTAssertEqual(selected.count, 2)
        XCTAssertFalse(selected.contains("claude"))
        XCTAssertFalse(selected.contains("mcp-claude"))
    }

    func testLegacyCrossPlatformPairsAndCachedUnionAreRemovedWithoutEmbeddingAgain() async throws {
        let embedding = PlatformEmbedding()
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: embedding, modelVersion: "test", policy: policy)
        let oldInputs = [input("a", .codex), input("b", .codex), input("c", .codex)]
        var legacy = try await analyzer.analyze(inputs: oldInputs, index: .init()).index
        for id in legacy.entries.keys { legacy.entries[id]?.platform = nil }
        legacy.comparisonPolicyVersion = nil
        let inputs = [input("a", .codex), input("b", .codex), input("c", .claude)]
        XCTAssertEqual(AgentOverlapAnalyzer.recommendations(in: legacy, activeIDs: ["a", "b", "c"]).first?.coverage, 0)
        XCTAssertTrue(AgentOverlapAnalyzer.refreshMetadata(inputs: inputs, index: &legacy, policy: policy))
        XCTAssertEqual(legacy.matches.count, 1)
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: inputs, index: legacy))
        let result = try await analyzer.analyze(inputs: inputs, index: legacy)
        XCTAssertEqual(result.calculatedPairCount, 0)
        XCTAssertEqual(result.matches.first { $0.sourceID == "c" }?.coverage, 0)
        let calls = await embedding.calls
        XCTAssertEqual(calls, 3)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentOverlapStore(url: root.appendingPathComponent("index.plist"), descriptionSources: [])
        try await store.save(result.index)
        let reloaded = try await AgentOverlapStore(url: store.url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(reloaded.entries["c"]?.platform, .claude)
        XCTAssertEqual(AgentOverlapAnalyzer.recommendations(in: reloaded, activeIDs: ["a", "b", "c"]).first { $0.sourceID == "c" }?.coverage, 0)
    }

    func testChangingPlatformInvalidatesPreviousCohortCertification() async throws {
        let analyzer = AgentOverlapAnalyzer(provider: PlatformEmbedding(), modelVersion: "test", policy: try .load())
        let first = try await analyzer.analyze(inputs: [input("a", .codex), input("b", .claude)], index: .init())
        XCTAssertEqual(first.calculatedPairCount, 0)
        let next = try await analyzer.analyze(inputs: [input("a", .codex), input("b", .codex)], index: first.index)
        XCTAssertEqual(next.calculatedPairCount, 1)
        XCTAssertEqual(next.matches.first?.coverage, 1)
    }
}

private actor PlatformEmbedding: AgentEmbeddingProvider {
    var calls = 0
    func embed(_ texts: [String]) async throws -> [[Float]] {
        calls += 1
        return texts.map { _ in [1, 0] }
    }
}
