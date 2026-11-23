import CleanerCore
import Foundation

func report(_ text: String) { try? FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8)) }
func measure<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
    let start = ContinuousClock.now
    let result = try await work()
    report("\(label): \(start.duration(to: .now))")
    return result
}

@main struct AgentPerformanceProfile {
    static func main() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "commit" {
            let destination = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("index.plist")
            let store = AgentOverlapStore(url: destination, descriptionSources: [])
            let index = try await measure("source_partition_upgrade") { try await store.load(resetAnalysis: false) }
            func references() throws -> [String: String] {
                let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: destination.appendingPathExtension("summary.plist")), format: nil) as! [String: Any]
                return value["partitions"] as! [String: String]
            }
            let before = try references()
            try await measure("source_unchanged_commit") { try await store.save(index) }
            guard try references() == before else { throw CocoaError(.fileReadCorruptFile) }
            var changed = index
            let id = index.entries.keys.sorted().first!
            changed.entries[id]?.title += " [isolated commit fixture]"
            let expected = Set([id] + (index.cachedRecommendations ?? []).filter { $0.targets.contains { $0.targetID == id } }.map(\.sourceID))
            try await measure("source_metadata_commit") { try await store.save(changed) }
            let after = try references()
            let touched = Set(after.keys.filter { after[$0] != before[$0] })
            guard touched == expected else { report("source_touched_mismatch: actual=\(touched.count) expected=\(expected.count)"); throw CocoaError(.fileReadCorruptFile) }
            let cold = try await measure("source_partition_cold_load") {
                try await AgentOverlapStore(url: destination, descriptionSources: []).load(resetAnalysis: false)
            }
            guard cold.matches == index.matches, cold.entries[id]?.title == changed.entries[id]?.title else { throw CocoaError(.fileReadCorruptFile) }
            let size = try Data(contentsOf: destination.appendingPathExtension("summary.plist")).count
            report("source_commit_verified: sources=\(index.entries.count) touched=\(touched.count) manifest_bytes=\(size); unrelated payloads and all coverage masks unchanged")
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "matrix" {
            let destination = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("index.plist")
            let store = AgentOverlapStore(url: destination, descriptionSources: [])
            let original = try await store.load(resetAnalysis: false)
            let active = original.completeIDs ?? Set(original.entries.keys)
            var hydrated = try await store.hydrating(original, ids: active)
            let inputs = active.sorted().compactMap { id -> AgentOverlapInput? in
                let entry = hydrated.entries[id]!
                guard let platform = entry.platform else { return nil }
                return AgentOverlapInput(id: id, kind: entry.kind, title: entry.title, description: "", features: entry.featureTexts, platform: platform)
            }
            guard inputs.count == active.count else {
                report("matrix_requires_platform_metadata: migrate an isolated copy with current discovery metadata first")
                throw CocoaError(.fileReadCorruptFile)
            }
            // Use the original extracted texts/vectors unchanged; only replace the
            // synthetic fingerprint so this exercises comparisons without inference.
            for input in inputs { hydrated.entries[input.id]?.inputFingerprint = input.fingerprint }
            hydrated.matches = [:]; hydrated.completeIDs = nil
            hydrated.cachedRecommendations = nil; hydrated.recommendationIDs = nil
            report("matrix_start: objects=\(inputs.count) vectors=\(hydrated.entries.values.reduce(0) { $0 + $1.featureVectors.count })")
            let analyzer = AgentOverlapAnalyzer(provider: NoInference(), modelVersion: original.modelVersion!, policy: try .load())
            let result = try await measure("matrix_all_pairs") { try await analyzer.analyze(inputs: inputs, index: hydrated) }
            let expected = original.matches.filter {
                guard active.contains($0.value.firstID), active.contains($0.value.secondID),
                      let first = original.entries[$0.value.firstID], let second = original.entries[$0.value.secondID] else { return false }
                return first.canCompare(with: second)
            }
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            try encoder.encode(result.index.matches).write(to: destination.deletingLastPathComponent().appendingPathComponent("matrix-result.plist"), options: .atomic)
            let mismatches = Set(result.index.matches.keys).union(expected.keys).filter { key in
                guard let actual = result.index.matches[key], let old = expected[key] else { return true }
                if actual.firstID == old.firstID { return actual != old }
                return actual.firstID != old.secondID || actual.secondID != old.firstID
                    || actual.firstCovered != old.secondCovered || actual.secondCovered != old.firstCovered
            }
            guard mismatches.isEmpty else {
                report("matrix_semantic_mismatches: \(mismatches.count)")
                for key in mismatches.prefix(3) { report("mismatch: \(key) actual=\(String(describing: result.index.matches[key])) old=\(String(describing: expected[key]))") }
                throw CocoaError(.fileReadCorruptFile)
            }
            report("matrix_verified: compared=\(result.calculatedPairCount) positive=\(result.index.matches.count); all directional masks identical")
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "replay" {
            let destination = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("index.plist")
            let store = AgentOverlapStore(url: destination, descriptionSources: [])
            let index = try await measure("optimized_cold_load") { try await store.load(resetAnalysis: false) }
            _ = try await measure("optimized_hydrate") { try await store.hydrating(index, ids: Set(index.entries.keys)) }
            _ = await measure("optimized_recommendations") {
                AgentOverlapAnalyzer.recommendations(in: index, activeIDs: index.completeIDs ?? Set(index.entries.keys))
            }
            return
        }
        if CommandLine.arguments.contains("scan") {
            let context = ScanContext(homeDirectory: home, enforcesEntryBudgets: false)
            let snapshot = AgentDirectorySnapshot()
            let scanner = AgentWorkspaceScanner(directorySnapshot: snapshot)
            for pass in 1...2 {
                let start = ContinuousClock.now
                let collector = CatalogCollector()
                let inventory = try await measure("scan_pass_\(pass)") {
                    try await scanner.scanAssetInventory(context: context) { catalog in
                        report("capabilities_pass_\(pass): \(start.duration(to: .now)); skills=\(catalog.skills.count) mcp=\(catalog.mcpConfigurations.count)")
                        await collector.set(catalog)
                    }
                }
                let catalog = await collector.catalog!
                // Match the exact input assembled by AppModel, including summary,
                // tags/triggers/tools/version/status and title, not only body text.
                func signature(_ skill: SkillCatalogEntry) throws -> String {
                    let version = String(data: try JSONEncoder().encode([skill.tags, skill.triggers, skill.tools,
                        [skill.pluginVersion ?? "", skill.parseStatus.rawValue]]), encoding: .utf8)
                    let input = AgentOverlapInput(id: "skill|" + skill.id, kind: .skill, title: skill.displayName,
                        description: skill.summary ?? "", features: skill.functionalSections, contentVersion: version, platform: skill.provider)
                    return skill.displayName + "|" + input.fingerprint
                }
                let earlySkills = try Dictionary(uniqueKeysWithValues: catalog.skills.map { ($0.id, try signature($0)) })
                let fullSkills = try Dictionary(uniqueKeysWithValues: inventory.skills.map { ($0.id, try signature($0)) })
                let earlyMCP = Dictionary(uniqueKeysWithValues: catalog.mcpConfigurations.map { ($0.id, $0) })
                let fullMCP = Dictionary(uniqueKeysWithValues: inventory.mcpConfigurations.map { ($0.id, $0) })
                guard earlySkills == fullSkills, earlyMCP == fullMCP else {
                    let earlyIDs = Set(earlySkills.keys), fullIDs = Set(fullSkills.keys)
                    report("catalog_mismatch: early=\(earlySkills.count) full=\(fullSkills.count) earlyMCP=\(catalog.mcpConfigurations.count) fullMCP=\(inventory.mcpConfigurations.count)")
                    report("missing_early: \(Array(fullIDs.subtracting(earlyIDs)).sorted().prefix(5))")
                    report("missing_full: \(Array(earlyIDs.subtracting(fullIDs)).sorted().prefix(5))")
                    report("input_differences: \(earlyIDs.intersection(fullIDs).filter { earlySkills[$0] != fullSkills[$0] }.sorted().prefix(5))")
                    report("mcp_differences: \(Set(earlyMCP.keys).union(fullMCP.keys).filter { earlyMCP[$0] != fullMCP[$0] }.sorted().prefix(5))")
                    throw CocoaError(.fileReadCorruptFile)
                }
                report("verified_pass_\(pass): assets=\(inventory.assets.count) skills=\(inventory.skills.count) mcp=\(inventory.mcpConfigurations.count) snapshot_hits=\(await snapshot.hits) misses=\(await snapshot.misses)")
            }
            return
        }
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "storage" else {
            report("Usage: agent-profile scan | storage <isolated-output-directory>"); return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let source = home.appendingPathComponent("Library/Application Support/SuperCleaner/agent-containment-index.plist")
        let index = try await measure("legacy_decode") {
            try PropertyListDecoder().decode(AgentOverlapIndex.self,
                from: Data(contentsOf: source.appendingPathExtension("summary.plist"), options: .mappedIfSafe))
        }
        report("legacy_shape: entries=\(index.entries.count) pairs=\(index.matches.count) features=\(index.entries.values.reduce(0) { $0 + $1.featureTexts.count })")
        let active = index.completeIDs ?? Set(index.entries.keys)
        let originalRecommendations = await measure("legacy_recommendations") {
            AgentOverlapAnalyzer.recommendations(in: index, activeIDs: active)
        }
        let readOnly = AgentOverlapStore(url: source, descriptionSources: [])
        let hydrated = try await measure("legacy_hydrate") { try await readOnly.hydrating(index, ids: Set(index.entries.keys)) }
        let destination = output.appendingPathComponent("index.plist")
        let store = AgentOverlapStore(url: destination, descriptionSources: [])
        try await measure("new_initial_save") { try await store.save(hydrated) }
        let coldStore = AgentOverlapStore(url: destination, descriptionSources: [])
        let cold = try await measure("new_cold_load") { try await coldStore.load(resetAnalysis: false) }
        let recommendations = await measure("new_recommendations") { AgentOverlapAnalyzer.recommendations(in: cold, activeIDs: active) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(recommendations) == encoder.encode(originalRecommendations) else { throw CocoaError(.fileReadCorruptFile) }
        let positive = index.matches.filter { $0.value.firstCovered.contains { $0 != 0 } || $0.value.secondCovered.contains { $0 != 0 } }
        guard cold.matches == positive else { throw CocoaError(.fileReadCorruptFile) }
        _ = try await measure("new_hydrate") { try await coldStore.hydrating(cold, ids: Set(cold.entries.keys)) }
        try await measure("new_unchanged_commit") { try await coldStore.save(cold) }
        report("verified: sparse_pairs=\(cold.matches.count) recommendation_objects=\(recommendations.count); directional masks and rankings identical")
    }
}

actor CatalogCollector {
    var catalog: AgentAssetInventory?
    func set(_ value: AgentAssetInventory) { catalog = value }
}

struct NoInference: AgentEmbeddingProvider {
    func embed(_ texts: [String]) async throws -> [[Float]] { throw AgentOverlapError.invalidEmbeddingOutput }
}
