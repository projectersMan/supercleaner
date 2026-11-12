import XCTest
@testable import CleanerCore

final class AgentOverlapPerformanceTests: XCTestCase {
    func testV1PartitionEnvelopeUpgradesToSourcePartitions() async throws {
        struct V1Manifest: Codable { let storageVersion: Int; let index: AgentOverlapIndex; let partitions: [String: String] }
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let relations = url.appendingPathExtension("relations")
        try FileManager.default.createDirectory(at: relations, withIntermediateDirectories: true)
        var header = AgentOverlapIndex()
        for i in 0..<2 { header.entries["\(i)"] = .init(id: "\(i)", cacheID: i, kind: .mcp, title: "\(i)", featureTexts: [], featureVectors: []) }
        header.completeIDs = ["0", "1"]
        let pair = AgentOverlapPair(firstID: "0", secondID: "1", firstCovered: Data(), secondCovered: Data())
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try encoder.encode(["0:1": pair]).write(to: relations.appendingPathComponent("legacy.plist"))
        try encoder.encode(V1Manifest(storageVersion: 1, index: header, partitions: ["0": "legacy.plist"]))
            .write(to: url.appendingPathExtension("summary.plist"))
        let migrated = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(migrated.entries.count, 2)
        XCTAssertTrue(migrated.matches.isEmpty)
        XCTAssertEqual(migrated.cachedRecommendations?.count, 2)
        let restored = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(restored.entries, migrated.entries)
        let manifest = try PropertyListSerialization.propertyList(from: Data(contentsOf: url.appendingPathExtension("summary.plist")), format: nil) as! [String: Any]
        XCTAssertEqual(manifest["storageVersion"] as? Int, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: relations.appendingPathComponent("legacy.plist").path))
    }
    func testBulkUnpackRejectsNonFiniteAndNonNormalizedVectors() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var index = AgentOverlapIndex()
        index.entries["a"] = .init(id: "a", cacheID: 0, kind: .mcp, title: "a", featureTexts: ["search"], featureVectors: [[1, 0]])
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(index)
        let summary = try await store.load(resetAnalysis: false)
        let slice = try XCTUnwrap(summary.vectorSlices?["a"])
        let block = url.appendingPathExtension("vectors").appendingPathComponent(slice.file)
        for invalid: Float in [.nan, .infinity, 2] {
            var values = [invalid, Float(0)]
            try values.withUnsafeMutableBytes { try Data($0).write(to: block, options: .atomic) }
            do {
                _ = try await AgentOverlapStore(url: url, descriptionSources: []).hydrating(summary, ids: ["a"])
                XCTFail("Corrupted vectors must not reach similarity calculations")
            } catch AgentOverlapError.invalidEmbeddingOutput { }
        }
    }
    func testTiledMatrixMatchesScalarCoverageAcrossTileBoundaries() async throws {
        let leftTexts = (0..<137).map { "left-\($0)" }
        let rightTexts = (0..<145).map { "right-\($0 + 1000)" }
        func vector(_ text: String) -> [Float] {
            let group = Int(text.split(separator: "-").last!)! % 29
            let raw = (0..<32).map { Float(sin(Double(group * 71 + $0 * 13))) }
            let norm = sqrt(raw.reduce(Float(0)) { $0 + $1 * $1 })
            return raw.map { $0 / norm }
        }
        let table = Dictionary(uniqueKeysWithValues: (leftTexts + rightTexts).map { ($0, vector($0)) })
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: TableEmbedding(table: table), modelVersion: "fixture", policy: policy)
        let inputs = [AgentOverlapInput(id: "left", kind: .mcp, title: "left", description: "", features: leftTexts),
                      AgentOverlapInput(id: "right", kind: .mcp, title: "right", description: "", features: rightTexts)]
        let result = try await analyzer.analyze(inputs: inputs, index: .init())
        var leftMask = AgentFeatureCoverage.empty(featureCount: leftTexts.count)
        var rightMask = AgentFeatureCoverage.empty(featureCount: rightTexts.count)
        for (row, left) in leftTexts.enumerated() {
            for (column, right) in rightTexts.enumerated() {
                let dot = zip(table[left]!, table[right]!).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                if dot >= policy.minimumFeatureSimilarity {
                    AgentFeatureCoverage.insert(row, into: &leftMask)
                    AgentFeatureCoverage.insert(column, into: &rightMask)
                }
            }
        }
        XCTAssertEqual(result.index.matches["0:1"]?.firstCovered, leftMask)
        XCTAssertEqual(result.index.matches["0:1"]?.secondCovered, rightMask)
        XCTAssertEqual(result.index.entries["left"]?.featureTexts.count, 137)
        XCTAssertEqual(result.index.entries["right"]?.featureTexts.count, 145)
    }
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("agent-performance-" + UUID().uuidString).appendingPathComponent("index.plist")
    }

    func testSparseZeroRelationshipsRemainCertifiedAfterRestart() async throws {
        let provider = OrthogonalEmbedding()
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: provider, modelVersion: "fixture", policy: policy)
        let inputs = (0..<32).map { AgentOverlapInput(id: "\($0)", kind: .mcp, title: "\($0)", description: "", features: ["\($0)"]) }
        let result = try await analyzer.analyze(inputs: inputs, index: .init())
        XCTAssertEqual(result.calculatedPairCount, 496)
        XCTAssertTrue(result.index.matches.isEmpty)
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try await AgentOverlapStore(url: url, descriptionSources: []).save(result.index)
        let cold = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertTrue(AgentOverlapAnalyzer.canReuse(inputs: inputs, index: cold))
        XCTAssertEqual(cold.cachedRecommendations?.count, 32)
        XCTAssertTrue(AgentOverlapAnalyzer.recommendations(in: cold, activeIDs: Set(inputs.map(\.id))).allSatisfy { $0.coverage == 0 })
        let replay = try await analyzer.analyze(inputs: inputs, index: cold)
        XCTAssertEqual(replay.calculatedPairCount, 0)
        let calls = await provider.calls
        XCTAssertEqual(calls, 32)
        let blocks = try FileManager.default.contentsOfDirectory(atPath: url.appendingPathExtension("vectors").path)
        XCTAssertEqual(blocks.count, 1, "One contiguous block replaces per-object vector files")
    }

    func testIncrementalCommitReusesUnchangedSourcePartitionsAndBlocks() async throws {
        var index = AgentOverlapIndex()
        for i in 0..<4 {
            index.entries["\(i)"] = .init(id: "\(i)", cacheID: i, kind: .skill, title: "\(i)", featureTexts: ["capability"], featureVectors: [[1, 0]])
        }
        index.matches["0:1"] = .init(firstID: "0", secondID: "1", firstCovered: Data([1]), secondCovered: Data([1]))
        index.matches["2:3"] = .init(firstID: "2", secondID: "3", firstCovered: Data([1]), secondCovered: Data([1]))
        index.completeIDs = Set(index.entries.keys)
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(index)
        let committed = try await store.load(resetAnalysis: false)
        let relations = url.appendingPathExtension("relations")
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: relations.path))
        let manifestURL = await store.summaryURL
        let oldHeader = try PropertyListSerialization.propertyList(from: Data(contentsOf: manifestURL), format: nil) as! [String: Any]
        let oldRefs = oldHeader["partitions"] as! [String: String]
        var changed = committed
        changed.matches["0:1"] = nil
        changed.matches["0:2"] = .init(firstID: "0", secondID: "2", firstCovered: Data([1]), secondCovered: Data([1]))
        try await store.save(changed)
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: relations.path))
        XCTAssertEqual(after.subtracting(before).count, 3, "Only changed edges and the two affected recommendations get new source partitions")
        let newHeader = try PropertyListSerialization.propertyList(from: Data(contentsOf: manifestURL), format: nil) as! [String: Any]
        let newRefs = newHeader["partitions"] as! [String: String]
        XCTAssertEqual(Set(newRefs.keys.filter { newRefs[$0] != oldRefs[$0] }), ["0", "1", "2"])
        XCTAssertEqual(newRefs["3"], oldRefs["3"], "Unrelated source metadata and recommendation remain immutable")
        XCTAssertTrue(((newHeader["index"] as? [String: Any])?["entries"] as? [String: Any])?.isEmpty == true, "The commit header must not duplicate all capability texts")
        try await store.save(try await store.load(resetAnalysis: false))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: relations.path)), after,
            "An unchanged commit never writes source text, edges, or recommendations again")
        let coldStore = AgentOverlapStore(url: url, descriptionSources: [])
        let restored = try await coldStore.load(resetAnalysis: false)
        XCTAssertNil(restored.matches["0:1"])
        XCTAssertNotNil(restored.matches["0:2"])
        XCTAssertNotNil(restored.matches["2:3"])
        let hydrated = try await coldStore.hydrating(restored, ids: Set(restored.entries.keys))
        XCTAssertTrue(hydrated.entries.values.allSatisfy { $0.featureVectors == [[1, 0]] })
        XCTAssertEqual(restored.vectorSlices?["0"]?.file, committed.vectorSlices?["0"]?.file)
        // Changing the active set must recompute unions, never use a cached Top 3 union.
        let removed = AgentOverlapAnalyzer.recommendations(in: restored, activeIDs: ["0", "1"])
        XCTAssertTrue(removed.allSatisfy { $0.coverage == 0 })
    }

    func testLegacySummaryMigratesWithoutLosingDirectionalCoverage() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var legacy = AgentOverlapIndex()
        for i in 0..<3 { legacy.entries["\(i)"] = .init(id: "\(i)", cacheID: i, kind: .mcp, title: "\(i)", featureTexts: ["search"], featureVectors: [[1, 0]]) }
        legacy.completeIDs = ["0", "1", "2"]
        legacy.matches["0:1"] = .init(firstID: "0", secondID: "1", firstCovered: Data([1]), secondCovered: Data([0]))
        legacy.matches["0:2"] = .init(firstID: "0", secondID: "2", firstCovered: Data([0]), secondCovered: Data([0]))
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try encoder.encode(legacy).write(to: url.appendingPathExtension("summary.plist"))
        let migrated = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(migrated.matches.count, 1)
        XCTAssertEqual(migrated.matches["0:1"]?.firstCovered, Data([1]))
        XCTAssertEqual(migrated.matches["0:1"]?.secondCovered, Data([0]))
        let cold = try await AgentOverlapStore(url: url, descriptionSources: []).load(resetAnalysis: false)
        XCTAssertEqual(cold.matches, migrated.matches)
        XCTAssertTrue(AgentOverlapAnalyzer.hasCompleteRelationships(in: cold, activeIDs: ["0", "1", "2"]))
    }
}

private struct TableEmbedding: AgentEmbeddingProvider {
    let table: [String: [Float]]
    func embed(_ texts: [String]) async throws -> [[Float]] { texts.map { table[$0]! } }
}

private actor OrthogonalEmbedding: AgentEmbeddingProvider {
    private(set) var calls = 0
    func embed(_ texts: [String]) async throws -> [[Float]] {
        calls += 1
        return texts.map { text in var vector = [Float](repeating: 0, count: 32); vector[Int(text)!] = 1; return vector }
    }
}
