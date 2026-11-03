import Accelerate
import Foundation

public actor AgentOverlapAnalyzer {
    public let provider: any AgentEmbeddingProvider
    public let modelVersion: String
    public let policy: AgentOverlapPolicy

    public init(provider: any AgentEmbeddingProvider, modelVersion: String, policy: AgentOverlapPolicy) {
        self.provider = provider; self.modelVersion = modelVersion; self.policy = policy
    }

    public func analyze(inputs: [AgentOverlapInput], index original: AgentOverlapIndex) async throws -> AgentOverlapAnalysisResult {
        var index = original
        if !index.entries.isEmpty {
            guard index.modelVersion == modelVersion, index.analysisVersion == policy.fingerprint else {
                throw AgentOverlapError.requiresFullRecalculation
            }
        }
        var added = Set<String>()
        var nextCacheID = (index.entries.values.map(\.cacheID).max() ?? -1) + 1
        for input in inputs {
            try Task.checkCancellation()
            if var known = index.entries[input.id] {
                // Stable identity is authoritative until the user explicitly recalculates all.
                known.title = input.title
                index.entries[input.id] = known
                continue
            }
            index.entries[input.id] = try await makeEntry(input, cacheID: nextCacheID)
            nextCacheID += 1
            added.insert(input.id)
        }
        let activeIDs = inputs.map(\.id).sorted()
        var calculatedPairs = 0
        for (position, sourceID) in activeIDs.enumerated() {
            let source = index.entries[sourceID]!
            for targetID in activeIDs.dropFirst(position + 1) {
                try Task.checkCancellation()
                let target = index.entries[targetID]!
                guard source.kind == target.kind else { continue }
                let key = Self.pairKey(source, target)
                guard index.matches[key] == nil else { continue }
                index.matches[key] = try Self.comparePair(source, target, minimumSimilarity: policy.minimumFeatureSimilarity)
                calculatedPairs += 1
            }
        }
        index.modelVersion = modelVersion
        index.analysisVersion = policy.fingerprint
        return AgentOverlapAnalysisResult(
            index: index, matches: Self.recommendations(in: index, activeIDs: Set(inputs.map(\.id))),
            addedIDs: added, calculatedPairCount: calculatedPairs
        )
    }

    public static func hasCompleteRelationships(in index: AgentOverlapIndex, activeIDs: Set<String>) -> Bool {
        let entries = activeIDs.sorted().compactMap { index.entries[$0] }
        guard entries.count == activeIDs.count else { return false }
        for (position, source) in entries.enumerated() {
            for target in entries.dropFirst(position + 1) where source.kind == target.kind {
                guard index.matches[pairKey(source, target)] != nil else { return false }
            }
        }
        return true
    }

    private func makeEntry(_ input: AgentOverlapInput, cacheID: Int) async throws -> AgentOverlapMemoryEntry {
        let candidates = AgentCapabilityExtraction.candidates(for: input, policy: policy)
        guard !candidates.isEmpty else {
            return AgentOverlapMemoryEntry(id: input.id, cacheID: cacheID, kind: input.kind, title: input.title, featureTexts: [], featureVectors: [])
        }
        let vectors = try await provider.embed(candidates)
        try Self.validate(vectors, expectedCount: candidates.count)
        return AgentOverlapMemoryEntry(
            id: input.id, cacheID: cacheID, kind: input.kind, title: input.title,
            featureTexts: candidates, featureVectors: vectors
        )
    }

    private static func comparePair(_ first: AgentOverlapMemoryEntry, _ second: AgentOverlapMemoryEntry, minimumSimilarity: Float) throws -> AgentOverlapPair {
        var firstMask = AgentFeatureCoverage.empty(featureCount: first.featureTexts.count)
        var secondMask = AgentFeatureCoverage.empty(featureCount: second.featureTexts.count)
        if !first.featureVectors.isEmpty, !second.featureVectors.isEmpty {
            let width = first.featureVectors[0].count
            guard first.featureVectors.allSatisfy({ $0.count == width }),
                  second.featureVectors.allSatisfy({ $0.count == width }), width > 0 else { throw AgentOverlapError.invalidEmbeddingOutput }
            let left = first.featureVectors.flatMap(\.self)
            let right = second.featureVectors.flatMap(\.self)
            let rows = first.featureVectors.count
            let columns = second.featureVectors.count
            var transposed = [Float](repeating: 0, count: right.count)
            vDSP_mtrans(right, 1, &transposed, 1, vDSP_Length(width), vDSP_Length(columns))
            var scores = [Float](repeating: 0, count: rows * columns)
            vDSP_mmul(left, 1, transposed, 1, &scores, 1, vDSP_Length(rows), vDSP_Length(columns), vDSP_Length(width))
            for row in 0..<rows {
                for column in 0..<columns where scores[row * columns + column] >= minimumSimilarity {
                    AgentFeatureCoverage.insert(row, into: &firstMask)
                    AgentFeatureCoverage.insert(column, into: &secondMask)
                }
            }
        }
        return AgentOverlapPair(firstID: first.id, secondID: second.id, firstCovered: firstMask, secondCovered: secondMask)
    }

    public static func recommendations(in index: AgentOverlapIndex, activeIDs: Set<String>) -> [AgentOverlapMatch] {
        var unions = [String: Data]()
        var targets = [String: [AgentOverlapTarget]]()
        for id in activeIDs {
            guard let entry = index.entries[id] else { continue }
            unions[id] = AgentFeatureCoverage.empty(featureCount: entry.featureTexts.count)
        }
        for pair in index.matches.values where pair.firstID != pair.secondID && activeIDs.contains(pair.firstID) && activeIDs.contains(pair.secondID) {
            accumulate(sourceID: pair.firstID, targetID: pair.secondID, mask: pair.firstCovered, index: index, unions: &unions, targets: &targets)
            accumulate(sourceID: pair.secondID, targetID: pair.firstID, mask: pair.secondCovered, index: index, unions: &unions, targets: &targets)
        }
        return unions.map { id, mask in
            AgentOverlapMatch(
                sourceID: id, targets: targets[id] ?? [], coveredFeatureCount: AgentFeatureCoverage.count(mask),
                totalFeatureCount: index.entries[id]!.featureTexts.count
            )
        }.sorted(by: compareMatches)
    }

    private static func accumulate(sourceID: String, targetID: String, mask: Data, index: AgentOverlapIndex, unions: inout [String: Data], targets: inout [String: [AgentOverlapTarget]]) {
        var combined = unions[sourceID]!
        AgentFeatureCoverage.merge(mask, into: &combined)
        unions[sourceID] = combined
        let coverage = AgentFeatureCoverage.fraction(mask, featureCount: index.entries[sourceID]!.featureTexts.count)
        guard coverage > 0 else { return }
        var ranked = targets[sourceID] ?? []
        ranked.append(AgentOverlapTarget(targetID: targetID, title: index.entries[targetID]!.title, coverage: coverage))
        ranked.sort(by: compareTargets)
        targets[sourceID] = Array(ranked.prefix(3))
    }

    private static func compareTargets(_ lhs: AgentOverlapTarget, _ rhs: AgentOverlapTarget) -> Bool {
        lhs.coverage != rhs.coverage ? lhs.coverage > rhs.coverage : lhs.targetID < rhs.targetID
    }

    /// Return a retained support set whose union reaches the threshold; never add percentages.
    public static func supportingTargets(for sourceID: String, allowedIDs: Set<String>, preferredIDs: Set<String>, threshold: Double, index: AgentOverlapIndex) -> Set<String>? {
        guard let source = index.entries[sourceID], !source.featureTexts.isEmpty else { return nil }
        var combined = AgentFeatureCoverage.empty(featureCount: source.featureTexts.count)
        var candidates = [(id: String, mask: Data)]()
        let targetIDs = allowedIDs.intersection(preferredIDs).sorted() + allowedIDs.subtracting(preferredIDs).sorted()
        for targetID in targetIDs where targetID != sourceID {
            guard let target = index.entries[targetID], source.kind == target.kind,
                  let pair = index.matches[pairKey(source, target)] else { continue }
            candidates.append((targetID, pair.firstID == sourceID ? pair.firstCovered : pair.secondCovered))
        }
        var keepers = Set<String>()
        while AgentFeatureCoverage.fraction(combined, featureCount: source.featureTexts.count) < threshold {
            var bestGain = 0
            var selected: (id: String, mask: Data)?
            for candidate in candidates where !keepers.contains(candidate.id) {
                var trial = combined
                AgentFeatureCoverage.merge(candidate.mask, into: &trial)
                let gain = AgentFeatureCoverage.count(trial) - AgentFeatureCoverage.count(combined)
                if gain > bestGain { bestGain = gain; selected = candidate }
            }
            guard let selected else { return nil }
            AgentFeatureCoverage.merge(selected.mask, into: &combined)
            keepers.insert(selected.id)
        }
        return keepers
    }

    public static func compareMatches(_ lhs: AgentOverlapMatch, _ rhs: AgentOverlapMatch) -> Bool {
        if lhs.maximumSingleCoverage != rhs.maximumSingleCoverage { return lhs.maximumSingleCoverage > rhs.maximumSingleCoverage }
        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        return lhs.sourceID < rhs.sourceID
    }

    public static func preselectedSourceIDs(index: AgentOverlapIndex, activeIDs: Set<String>, eligibleIDs: Set<String>, cacheIDs: Set<String>, manuallySelectedIDs: Set<String>, retainedIDs: Set<String>, threshold: Double) -> Set<String> {
        var selected = cacheIDs.intersection(activeIDs).intersection(eligibleIDs)
            .subtracting(retainedIDs).subtracting(manuallySelectedIDs)
        var keepers = Set<String>()
        let candidates = recommendations(in: index, activeIDs: activeIDs).sorted(by: comparePreselectionPriority)
        for item in candidates where item.coverage >= threshold {
            guard eligibleIDs.contains(item.sourceID), !retainedIDs.contains(item.sourceID),
                  !manuallySelectedIDs.contains(item.sourceID), !selected.contains(item.sourceID), !keepers.contains(item.sourceID) else { continue }
            let references = activeIDs.subtracting(manuallySelectedIDs).subtracting(selected)
            let support = supportingTargets(for: item.sourceID, allowedIDs: references.intersection(retainedIDs), preferredIDs: retainedIDs, threshold: threshold, index: index)
                ?? supportingTargets(for: item.sourceID, allowedIDs: references, preferredIDs: retainedIDs, threshold: threshold, index: index)
            guard let support else { continue }
            selected.insert(item.sourceID)
            keepers.formUnion(support)
        }
        return selected
    }

    private static func comparePreselectionPriority(_ lhs: AgentOverlapMatch, _ rhs: AgentOverlapMatch) -> Bool {
        // Resolve jointly covered composites before their individual covering items.
        if lhs.maximumSingleCoverage != rhs.maximumSingleCoverage { return lhs.maximumSingleCoverage < rhs.maximumSingleCoverage }
        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        return lhs.sourceID < rhs.sourceID
    }

    private static func pairKey(_ first: AgentOverlapMemoryEntry, _ second: AgentOverlapMemoryEntry) -> String {
        "\(min(first.cacheID, second.cacheID)):\(max(first.cacheID, second.cacheID))"
    }

    private static func validate(_ vectors: [[Float]], expectedCount: Int) throws {
        guard vectors.count == expectedCount, Set(vectors.map(\.count)).count == 1,
              vectors.allSatisfy(validVector) else { throw AgentOverlapError.invalidEmbeddingOutput }
    }

    private static func validVector(_ vector: [Float]) -> Bool {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return false }
        var norm: Float = 0
        for value in vector { norm += value * value }
        return abs(norm - 1) < 0.01
    }
}
