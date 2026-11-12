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
        var changed = Set<String>()
        var dirty = Set<String>()
        var nextCacheID = (index.entries.values.map(\.cacheID).max() ?? -1) + 1
        for input in inputs {
            try Task.checkCancellation()
            if var known = index.entries[input.id] {
                let unchanged = known.kind == input.kind && (known.inputFingerprint == input.fingerprint
                    || (known.inputFingerprint == nil && known.featureTexts == AgentCapabilityExtraction.candidates(for: input, policy: policy)))
                if unchanged {
                    known.title = input.title
                    known.inputFingerprint = input.fingerprint
                    index.entries[input.id] = known
                    continue
                }
                changed.insert(input.id)
                index.vectorFiles?.removeValue(forKey: input.id)
                index.vectorSlices?.removeValue(forKey: input.id)
            }
            index.entries[input.id] = try await makeEntry(input, cacheID: nextCacheID)
            nextCacheID += 1
            if original.entries[input.id] == nil { added.insert(input.id) }
            dirty.insert(input.id)
        }
        if !changed.isEmpty {
            index.matches = index.matches.filter { !changed.contains($0.value.firstID) && !changed.contains($0.value.secondID) }
        }
        let activeIDs = inputs.map(\.id).sorted()
        var calculatedPairs = 0
        // A completed cohort certifies old-old pairs; only dirty/new edges need visiting.
        let certified = original.completeIDs ?? []
        let incremental = original.completeIDs != nil
        let sources = incremental ? activeIDs.filter { dirty.contains($0) || !certified.contains($0) } : activeIDs
        let sourceSet = Set(sources)
        var prepared = [String: PreparedVectors]()
        for sourceID in sources {
            let source = index.entries[sourceID]!
            for targetID in activeIDs where sourceID != targetID {
                try Task.checkCancellation()
                let target = index.entries[targetID]!
                guard source.kind == target.kind else { continue }
                if sourceSet.contains(targetID) && sourceID > targetID { continue }
                let key = Self.pairKey(source, target)
                guard index.matches[key] == nil else { continue }
                // A missing edge in a certified cohort means zero coverage.
                if certified.contains(sourceID), certified.contains(targetID),
                   !dirty.contains(sourceID), !dirty.contains(targetID) { continue }
                guard source.featureVectors.count == source.featureTexts.count,
                      target.featureVectors.count == target.featureTexts.count else { throw AgentOverlapError.invalidEmbeddingOutput }
                if prepared[sourceID] == nil { prepared[sourceID] = try PreparedVectors(source) }
                if prepared[targetID] == nil { prepared[targetID] = try PreparedVectors(target) }
                guard prepared[sourceID]!.width == prepared[targetID]!.width
                    || source.featureVectors.isEmpty || target.featureVectors.isEmpty else { throw AgentOverlapError.invalidEmbeddingOutput }
                let pair = Self.comparePair(source, target, left: prepared[sourceID]!, right: prepared[targetID]!, minimumSimilarity: policy.minimumFeatureSimilarity)
                if pair.firstCovered.contains(where: { $0 != 0 }) || pair.secondCovered.contains(where: { $0 != 0 }) {
                    index.matches[key] = pair
                }
                calculatedPairs += 1
            }
        }
        index.modelVersion = modelVersion
        index.analysisVersion = policy.fingerprint
        index.completeIDs = Set(activeIDs)
        index.revision = UUID().uuidString
        index.cachedRecommendations = nil
        index.recommendationIDs = nil
        let active = Set(activeIDs)
        let recommendations = Self.recommendations(in: index, activeIDs: active)
        index.recommendationIDs = active
        index.cachedRecommendations = recommendations
        return AgentOverlapAnalysisResult(
            index: index, matches: recommendations,
            addedIDs: added, calculatedPairCount: calculatedPairs, changedIDs: changed
        )
    }

    public static func hasCompleteRelationships(in index: AgentOverlapIndex, activeIDs: Set<String>) -> Bool {
        if let completeIDs = index.completeIDs, activeIDs.isSubset(of: completeIDs),
           activeIDs.allSatisfy({ index.entries[$0] != nil }) { return true }
        let entries = activeIDs.sorted().compactMap { index.entries[$0] }
        guard entries.count == activeIDs.count else { return false }
        for (position, source) in entries.enumerated() {
            for target in entries.dropFirst(position + 1) where source.kind == target.kind {
                guard index.matches[pairKey(source, target)] != nil else { return false }
            }
        }
        return true
    }

    /// Adopt legacy vectors only when their exact extracted features still match.
    public static func refreshMetadata(inputs: [AgentOverlapInput], index: inout AgentOverlapIndex, policy: AgentOverlapPolicy) -> Bool {
        var updated = false
        for input in inputs {
            guard var entry = index.entries[input.id] else { continue }
            var entryChanged = false
            if entry.title != input.title { entry.title = input.title; entryChanged = true }
            if entry.inputFingerprint == nil, entry.kind == input.kind,
               entry.featureTexts == AgentCapabilityExtraction.candidates(for: input, policy: policy) {
                entry.inputFingerprint = input.fingerprint; entryChanged = true
            }
            if entryChanged { index.entries[input.id] = entry; updated = true }
        }
        return updated
    }

    public static func canReuse(inputs: [AgentOverlapInput], index: AgentOverlapIndex) -> Bool {
        inputs.allSatisfy { input in
            guard let entry = index.entries[input.id] else { return false }
            return entry.kind == input.kind && entry.inputFingerprint == input.fingerprint && entry.title == input.title
        } && hasCompleteRelationships(in: index, activeIDs: Set(inputs.map(\.id)))
    }

    private func makeEntry(_ input: AgentOverlapInput, cacheID: Int) async throws -> AgentOverlapMemoryEntry {
        let candidates = AgentCapabilityExtraction.candidates(for: input, policy: policy)
        guard !candidates.isEmpty else {
            return AgentOverlapMemoryEntry(id: input.id, cacheID: cacheID, kind: input.kind, title: input.title, featureTexts: [], featureVectors: [], inputFingerprint: input.fingerprint)
        }
        let vectors = try await provider.embed(candidates)
        try Self.validate(vectors, expectedCount: candidates.count)
        return AgentOverlapMemoryEntry(
            id: input.id, cacheID: cacheID, kind: input.kind, title: input.title,
            featureTexts: candidates, featureVectors: vectors, inputFingerprint: input.fingerprint
        )
    }

    private struct PreparedVectors {
        let values: [Float]
        let width: Int
        init(_ entry: AgentOverlapMemoryEntry) throws {
            let width = entry.featureVectors.first?.count ?? 0
            guard entry.featureVectors.allSatisfy({ $0.count == width }),
                  entry.featureVectors.isEmpty || width > 0 else { throw AgentOverlapError.invalidEmbeddingOutput }
            values = entry.featureVectors.flatMap(\.self)
            self.width = width
        }
    }

    private static func comparePair(_ first: AgentOverlapMemoryEntry, _ second: AgentOverlapMemoryEntry, left: PreparedVectors, right: PreparedVectors, minimumSimilarity: Float) -> AgentOverlapPair {
        var firstMask = AgentFeatureCoverage.empty(featureCount: first.featureTexts.count)
        var secondMask = AgentFeatureCoverage.empty(featureCount: second.featureTexts.count)
        if !first.featureVectors.isEmpty, !second.featureVectors.isEmpty {
            let width = left.width
            guard width == right.width else { return AgentOverlapPair(firstID: first.id, secondID: second.id, firstCovered: firstMask, secondCovered: secondMask) }
            let rows = first.featureVectors.count
            let columns = second.featureVectors.count
            // Transpose flags avoid materializing a transpose for every pair.
            // Tile score matrices so unusually long manifests have bounded scratch space.
            left.values.withUnsafeBufferPointer { lhs in
                right.values.withUnsafeBufferPointer { rhs in
                    for start in stride(from: 0, to: rows, by: 128) {
                        let count = min(128, rows - start)
                        var scores = [Float](repeating: 0, count: count * columns)
                        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(count), Int32(columns), Int32(width),
                            1, lhs.baseAddress!.advanced(by: start * width), Int32(width), rhs.baseAddress!, Int32(width), 0, &scores, Int32(columns))
                        scores.withUnsafeBufferPointer { values in
                            // Coverage requires existence of a qualifying match,
                            // so row/column maxima are exactly equivalent to
                            // visiting every matching cell and setting both bits.
                            for row in 0..<count {
                                var maximum: Float = -.infinity
                                vDSP_maxv(values.baseAddress!.advanced(by: row * columns), 1, &maximum, vDSP_Length(columns))
                                if maximum >= minimumSimilarity { AgentFeatureCoverage.insert(start + row, into: &firstMask) }
                            }
                            for column in 0..<columns {
                                var maximum: Float = -.infinity
                                vDSP_maxv(values.baseAddress!.advanced(by: column), vDSP_Stride(columns), &maximum, vDSP_Length(count))
                                if maximum >= minimumSimilarity { AgentFeatureCoverage.insert(column, into: &secondMask) }
                            }
                        }
                    }
                }
            }
        }
        return AgentOverlapPair(firstID: first.id, secondID: second.id, firstCovered: firstMask, secondCovered: secondMask)
    }

    public static func recommendations(in index: AgentOverlapIndex, activeIDs: Set<String>) -> [AgentOverlapMatch] {
        if index.recommendationIDs == activeIDs, let cached = index.cachedRecommendations {
            return cached.map { match in
                AgentOverlapMatch(sourceID: match.sourceID, targets: match.targets.map {
                    AgentOverlapTarget(targetID: $0.targetID, title: index.entries[$0.targetID]?.title ?? $0.title, coverage: $0.coverage)
                }, coveredFeatureCount: match.coveredFeatureCount, totalFeatureCount: match.totalFeatureCount)
            }
        }
        var unions = [String: Data]()
        var targets = [String: [AgentOverlapTarget]]()
        for id in activeIDs {
            guard let entry = index.entries[id] else { continue }
            unions[id] = AgentFeatureCoverage.empty(featureCount: entry.featureTexts.count)
        }
        for pair in index.matches.values where pair.firstID != pair.secondID && activeIDs.contains(pair.firstID) && activeIDs.contains(pair.secondID) {
            if Task.isCancelled { return [] }
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

    public static func preselectedSourceIDs(index: AgentOverlapIndex, activeIDs: Set<String>, eligibleIDs: Set<String>, cacheIDs: Set<String>, manuallySelectedIDs: Set<String>, retainedIDs: Set<String>, threshold: Double, cachedRecommendations: [AgentOverlapMatch]? = nil) -> Set<String> {
        var selected = cacheIDs.intersection(activeIDs).intersection(eligibleIDs)
            .subtracting(retainedIDs).subtracting(manuallySelectedIDs)
        var keepers = Set<String>()
        let candidates = (cachedRecommendations ?? recommendations(in: index, activeIDs: activeIDs)).sorted(by: comparePreselectionPriority)
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
