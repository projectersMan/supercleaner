import CleanerCore
import AgentOverlapAI
import Foundation

actor RejectEmbedding: AgentEmbeddingProvider {
    func embed(_ texts: [String]) throws -> [[Float]] { throw AgentOverlapError.invalidEmbeddingOutput }
}

@main struct AnalysisContract {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let model = root.appendingPathComponent("Sources/AgentOverlapAI/Resources/Models/embeddinggemma-2-Q8_0.gguf")
        let executable = root.appendingPathComponent("build/SuperCleaner.app/Contents/MacOS/AgentInference")
        let embedder = GemmaTextEmbedder(modelURL: model, executableURL: executable)
        let policy = try AgentOverlapPolicy.load()
        var inputs: [AgentOverlapInput] = []
        for number in 0..<7 {
            inputs.append(.init(id: "skill|/fixture/skill-\(number)", kind: .skill, title: "Skill \(number)", description: "", features: ["Create and edit spreadsheet workbooks with formulas and charts."]))
        }
        for number in 0..<2 {
            inputs.append(.init(id: "mcp|/fixture/mcp-\(number)", kind: .mcp, title: "MCP \(number)", description: "", features: ["Read project tasks and their current status."]))
        }
        let analyzer = AgentOverlapAnalyzer(provider: embedder, modelVersion: GemmaTextEmbedder.modelVersion, policy: policy)
        let result = try await analyzer.analyze(inputs: inputs, index: .init())
        await embedder.shutdown()
        let active = Set(inputs.map(\.id))
        let recommendations = AgentOverlapAnalyzer.recommendations(in: result.index, activeIDs: active)
        let selected = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: active, eligibleIDs: active, cacheIDs: [], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        let skills = recommendations.filter { $0.sourceID.hasPrefix("skill|") }
        precondition(skills.count == 7 && skills.allSatisfy { $0.targets.count == 3 && $0.coverage == 1 })
        precondition(skills.allSatisfy { match in match.targets.allSatisfy { $0.targetID != match.sourceID && $0.coverage == 1 } })
        precondition(selected.filter { $0.hasPrefix("skill|") }.count == 6)
        precondition(selected.filter { $0.hasPrefix("mcp|") }.count == 1)
        let retained = inputs[0].id
        let preserved = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: active, eligibleIDs: active, cacheIDs: [], manuallySelectedIDs: [], retainedIDs: [retained], threshold: 0.85)
        precondition(!preserved.contains(retained))
        let cache = inputs[1].id
        let cacheOnly = AgentOverlapAnalyzer.preselectedSourceIDs(index: .init(), activeIDs: [cache], eligibleIDs: [cache], cacheIDs: [cache], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        precondition(cacheOnly.isEmpty, "A unique cache without verified retained coverage is not preselected")
        let cacheKept = AgentOverlapAnalyzer.preselectedSourceIDs(index: .init(), activeIDs: [cache], eligibleIDs: [cache], cacheIDs: [cache], manuallySelectedIDs: [], retainedIDs: [cache], threshold: 0.85)
        precondition(cacheKept.isEmpty, "An explicit keep overrides cache preselection")
        let protectedCache = AgentOverlapAnalyzer.preselectedSourceIDs(index: .init(), activeIDs: [cache], eligibleIDs: [], cacheIDs: [cache], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        precondition(protectedCache.isEmpty, "Cache preselection never bypasses eligibility")
        let cachedSupport = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: [retained, cache], eligibleIDs: [retained, cache], cacheIDs: [cache], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        precondition(cachedSupport == [cache], "A cache scheduled for deletion cannot justify deleting its only counterpart")
        let sharedFirst = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: active, eligibleIDs: active, cacheIDs: [cache], manuallySelectedIDs: [], retainedIDs: [retained], threshold: 0.85)
        precondition(!sharedFirst.contains(retained) && sharedFirst.contains(cache))
        precondition(sharedFirst.filter { $0.hasPrefix("skill|") }.count == 6, "Keep the shared source and select the independent covered copies")
        let cached = try await AgentOverlapAnalyzer(provider: RejectEmbedding(), modelVersion: GemmaTextEmbedder.modelVersion, policy: policy).analyze(inputs: inputs, index: result.index)
        precondition(cached.addedIDs.isEmpty && cached.calculatedPairCount == 0)
        let url = root.appendingPathComponent("Tests/agent-overlap-diagnosis/fixtures/index.plist")
        let store = AgentOverlapStore(url: url, descriptionSources: [])
        try await store.save(result.index)
        let restored = try await store.load(resetAnalysis: false)
        precondition(restored.entries.count == 9)
        print("PASS: real Gemma embeddings; Top 3; retained shared source; unique caches kept; cache cannot provide retained coverage; explicit keep, protection and zero-new-work reuse")
    }
}
