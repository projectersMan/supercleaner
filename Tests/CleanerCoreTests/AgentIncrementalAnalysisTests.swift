import XCTest
@testable import CleanerCore

final class AgentIncrementalAnalysisTests: XCTestCase {
    private func input(_ id: String, _ text: String = "search source code", kind: AgentOverlapKind = .mcp) -> AgentOverlapInput {
        .init(id: id, kind: kind, title: id, description: text, features: [text])
    }
    private func temporaryIndex() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString).appendingPathComponent("index.plist")
    }

    func testUnchangedAddModifyRemoveAndReadd() async throws {
        let provider = CountingEmbedding()
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: "test", policy: policy)
        let inputs = [input("a"), input("b"), input("c")]
        let first = try await analyzer.analyze(inputs: inputs, index: .init())
        XCTAssertEqual(first.calculatedPairCount, 3)
        let callsBefore = await provider.calls
        XCTAssertEqual(callsBefore, 3)
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: inputs, index: first.index))
        let repeatResult = try await analyzer.analyze(inputs: inputs, index: first.index)
        XCTAssertEqual(repeatResult.calculatedPairCount, 0)
        let callsAfter = await provider.calls
        XCTAssertEqual(callsAfter, callsBefore)
        let added = try await analyzer.analyze(inputs: inputs + [input("d")], index: first.index)
        XCTAssertEqual(added.addedIDs, ["d"])
        XCTAssertEqual(added.calculatedPairCount, 3)
        let modified = try await analyzer.analyze(inputs: [input("a", "write reports"), inputs[1], inputs[2], input("d")], index: added.index)
        XCTAssertEqual(modified.changedIDs, ["a"])
        XCTAssertEqual(modified.calculatedPairCount, 3)
        XCTAssertEqual(modified.matches.first { $0.sourceID == "a" }?.coverage, 0)
        let beforeRemoval = await provider.calls
        let removed = try await analyzer.analyze(inputs: [inputs[1]], index: modified.index)
        XCTAssertEqual(removed.calculatedPairCount, 0)
        XCTAssertEqual(removed.matches.first?.coverage, 0)
        let afterRemoval = await provider.calls
        XCTAssertEqual(beforeRemoval, afterRemoval)
        let readded = try await analyzer.analyze(inputs: [inputs[1],inputs[2]], index: removed.index)
        XCTAssertEqual(readded.calculatedPairCount, 0)
        XCTAssertEqual(readded.matches.first?.coverage, 1)
    }

    func testSplitStoreColdLoadDoesNotReadVectorsAndHydratesForNewPairs() async throws {
        let url = temporaryIndex(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let provider = CountingEmbedding()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: "test", policy: try .load())
        let first = try await analyzer.analyze(inputs: [input("a"),input("b")], index: .init())
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(first.index)
        let cold = AgentOverlapStore(url: url, descriptionSources: [])
        let summary = try await cold.load(resetAnalysis: false)
        XCTAssertTrue(summary.entries.values.allSatisfy { $0.featureVectors.isEmpty })
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: [input("a"),input("b")], index: summary))
        let loaded = try await cold.hydrating(summary, ids: ["a","b"])
        XCTAssertEqual(loaded.entries["a"]?.featureVectors, first.index.entries["a"]?.featureVectors)
        let added = try await analyzer.analyze(inputs: [input("a"),input("b"),input("c")], index: loaded)
        XCTAssertEqual(added.calculatedPairCount, 2)
        try await cold.save(added.index)
        let next = try await cold.load(resetAnalysis: false)
        XCTAssertEqual(next.vectorSlices?["a"]?.file, summary.vectorSlices?["a"]?.file, "Unchanged blocks are not rewritten")
        XCTAssertEqual(next.vectorSlices?["a"]?.offset, summary.vectorSlices?["a"]?.offset)
        // Missing vector blobs cannot prevent summary-only reuse, even after restarting.
        try FileManager.default.removeItem(at: url.appendingPathExtension("vectors"))
        let summaryOnly = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: [input("a"),input("b"),input("c")], index: summaryOnly))
        do { _ = try await AgentOverlapStore(url: url, descriptionSources: []).hydrating(summaryOnly, ids: ["a"]); XCTFail("Missing vectors must not produce fabricated comparisons") } catch { }
    }

    func testLegacyMigrationKeepsOriginalAndAdoptsUnchangedFeatures() async throws {
        let url = temporaryIndex(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let provider = CountingEmbedding(); let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: "test", policy: policy)
        let inputs = [input("a"),input("b")]
        var old = try await analyzer.analyze(inputs: inputs, index: .init()).index
        old.completeIDs = nil; old.revision = nil
        for id in old.entries.keys { old.entries[id]?.inputFingerprint = nil }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let originalBytes = try encoder.encode(old); try originalBytes.write(to: url)
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        var migrated = try await store.load(resetAnalysis: false)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertTrue(migrated.entries.values.allSatisfy { $0.featureVectors.isEmpty })
        XCTAssertTrue(AgentOverlapAnalyzer.refreshMetadata(inputs: inputs, index: &migrated, policy: policy))
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: inputs, index: migrated))
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(AgentOverlapAnalyzer.canReuse(inputs: [input("a", "write reports"),inputs[1]], index: migrated))
    }

    func testFailedSaveLeavesCommittedSummaryUsableAndResetPreservesDescriptions() async throws {
        let url = temporaryIndex(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let analyzer = AgentOverlapAnalyzer(provider: CountingEmbedding(), modelVersion: "test", policy: try .load())
        var first = try await analyzer.analyze(inputs: [input("a")], index: .init()).index
        first.localMetadata["local"] = .init(description: "user description")
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(first)
        let before = try await store.load(resetAnalysis: false)
        var broken = before; broken.vectorFiles = [:]; broken.vectorSlices = [:]
        do { try await store.save(broken); XCTFail("Incomplete vector generation must fail") } catch { }
        let after = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(after.revision, before.revision)
        let reset = try await store.load(resetAnalysis: true)
        XCTAssertTrue(reset.entries.isEmpty)
        XCTAssertEqual(reset.localMetadata["local"]?.description, "user description")
    }

    func testMCPConfigurationChangesFingerprintEvenWithSameServerName() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".mcp-fixture-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(".agents/mcp.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"search":{"command":"old"}}}"#.utf8).write(to: file)
        let first = await MCPConfigurationCatalogSupport.makeRecord(provider: .codex, scope: .global, url: file,
            homeDirectory: root, fileSystem: LocalFileSystem())
        try Data(#"{"mcpServers":{"search":{"command":"new"}}}"#.utf8).write(to: file)
        let second = await MCPConfigurationCatalogSupport.makeRecord(provider: .codex, scope: .global, url: file,
            homeDirectory: root, fileSystem: LocalFileSystem())
        XCTAssertEqual(first?.servers, second?.servers)
        XCTAssertNotNil(first?.contentFingerprint)
        XCTAssertNotEqual(first?.contentFingerprint, second?.contentFingerprint)
    }

    func testSummaryExcludesBulkVectorData() async throws {
        let url = temporaryIndex(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var index = AgentOverlapIndex()
        for row in 0..<16 {
            var vector = (0..<2048).map { Float(sin(Double($0 + row * 2048))) }
            let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 }); vector = vector.map { $0 / norm }
            let id = "item-\(row)"
            index.entries[id] = .init(id: id, cacheID: row, kind: .mcp, title: id,
                featureTexts: ["search"], featureVectors: [vector], inputFingerprint: "fixture")
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let legacyBytes = try encoder.encode(index).count
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(index)
        let summaryURL = await store.summaryURL
        let summaryBytes = try Data(contentsOf: summaryURL).count
        XCTAssertLessThan(summaryBytes, legacyBytes / 10)
        print("Agent fixture: legacy=\(legacyBytes) bytes, summary=\(summaryBytes) bytes; vectors loaded only for changed relationships")
    }

    func testContentVersionAndModelPolicyInvalidateReuse() async throws {
        let provider = CountingEmbedding(); let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: "test", policy: policy)
        let original = AgentOverlapInput(id: "mcp", kind: .mcp, title: "MCP", description: "", features: ["search"], contentVersion: "config-1")
        let first = try await analyzer.analyze(inputs: [original], index: .init())
        let changed = AgentOverlapInput(id: "mcp", kind: .mcp, title: "MCP", description: "", features: ["search"], contentVersion: "config-2")
        XCTAssertFalse(AgentOverlapAnalyzer.canReuse(inputs: [changed], index: first.index))
        let result = try await analyzer.analyze(inputs: [changed], index: first.index)
        XCTAssertEqual(result.changedIDs, ["mcp"])
        do {
            _ = try await AgentOverlapAnalyzer(provider: provider, modelVersion: "other", policy: policy).analyze(inputs: [original], index: first.index)
            XCTFail("Different models must not reuse old vectors")
        } catch AgentOverlapError.requiresFullRecalculation { }
    }
}

private actor CountingEmbedding: AgentEmbeddingProvider {
    private(set) var calls = 0
    func embed(_ texts: [String]) async throws -> [[Float]] {
        calls += 1
        return texts.map { $0.contains("write") ? [0, 1] : [1, 0] }
    }
}
