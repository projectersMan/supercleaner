import Foundation
import CryptoKit
import Accelerate

public actor AgentOverlapStore {
    public let url: URL
    private let descriptionSources: [URL]

    public init(url: URL, descriptionSources: [URL]) {
        self.url = url.standardizedFileURL
        self.descriptionSources = descriptionSources
    }

    private var cached: AgentOverlapIndex?
    private var cachedStamp: String?
    private var partitionFiles: [String: String] = [:]
    private var partitionVersion = 0
    private var mappedVectors: [String: Data] = [:]
    public var summaryURL: URL { url.appendingPathExtension("summary.plist") }
    private var vectorsURL: URL { url.appendingPathExtension("vectors") }
    private var relationsURL: URL { url.appendingPathExtension("relations") }

    private struct Manifest: Codable {
        let storageVersion: Int
        let index: AgentOverlapIndex
        let partitions: [String: String]
    }

    private struct SourcePartition: Codable, Equatable {
        let entry: AgentOverlapMemoryEntry
        let pairs: [String: AgentOverlapPair]
        let recommendation: AgentOverlapMatch?
    }

    private func child(_ name: String, in directory: URL) throws -> URL {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              !name.contains("/"), name != ".", name != ".." else { throw AgentOverlapError.invalidEmbeddingOutput }
        return directory.appendingPathComponent(name)
    }

    private func stamp(_ file: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return "\(attributes[.systemFileNumber] ?? 0)|\(attributes[.size] ?? 0)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }

    public func load(resetAnalysis: Bool) throws -> AgentOverlapIndex {
        try Task.checkCancellation()
        let fm = FileManager.default
        let source = fm.fileExists(atPath: summaryURL.path) ? summaryURL : url
        if fm.fileExists(atPath: source.path) {
            let currentStamp = try stamp(source)
            let index: AgentOverlapIndex
            if let cached, cachedStamp == currentStamp { index = cached }
            else {
                let data = try Data(contentsOf: source, options: .mappedIfSafe)
                let decoder = PropertyListDecoder()
                let manifest = try? decoder.decode(Manifest.self, from: data)
                var decoded: AgentOverlapIndex
                if let manifest {
                    guard (1...2).contains(manifest.storageVersion) else { throw AgentOverlapError.unsupportedIndexSchema }
                    decoded = manifest.index
                    var recommendations = [AgentOverlapMatch]()
                    for (id, name) in manifest.partitions {
                        try Task.checkCancellation()
                        let bytes = try Data(contentsOf: child(name, in: relationsURL), options: .mappedIfSafe)
                        if manifest.storageVersion == 1 {
                            decoded.matches.merge(try decoder.decode([String: AgentOverlapPair].self, from: bytes)) { _, new in new }
                        } else {
                            let partition = try decoder.decode(SourcePartition.self, from: bytes)
                            guard partition.entry.id == id, partition.entry.featureVectors.isEmpty else { throw AgentOverlapError.invalidEmbeddingOutput }
                            decoded.entries[id] = partition.entry
                            decoded.matches.merge(partition.pairs) { _, new in new }
                            if let recommendation = partition.recommendation { recommendations.append(recommendation) }
                        }
                    }
                    if manifest.storageVersion == 2, decoded.recommendationIDs != nil {
                        decoded.cachedRecommendations = recommendations.sorted(by: AgentOverlapAnalyzer.compareMatches)
                    }
                    partitionFiles = manifest.partitions
                    partitionVersion = manifest.storageVersion
                } else {
                    decoded = try decoder.decode(AgentOverlapIndex.self, from: data)
                }
                guard decoded.schemaVersion == AgentOverlapIndex.currentSchemaVersion else { throw AgentOverlapError.unsupportedIndexSchema }
                try Task.checkCancellation()
                if (manifest == nil || manifest?.storageVersion == 1) && !resetAnalysis {
                    // One-time migration. Keep the legacy file intact until and after commit.
                    try save(decoded)
                    index = cached!
                } else {
                    cached = decoded; cachedStamp = currentStamp; index = decoded
                }
            }
            if resetAnalysis {
                var empty = AgentOverlapIndex(); empty.localMetadata = index.localMetadata
                return empty
            }
            return index
        }
        var empty = AgentOverlapIndex()
        for source in descriptionSources where fm.fileExists(atPath: source.path) {
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            let descriptions = source.pathExtension == "json"
                ? try JSONDecoder().decode(Descriptions.self, from: Self.descriptionPayload(data))
                : try PropertyListDecoder().decode(Descriptions.self, from: data)
            for (id, value) in descriptions.localMetadata where empty.localMetadata[id] == nil {
                empty.localMetadata[id] = value
            }
        }
        return empty
    }

    /// The summary contains texts and coverage masks, never vector arrays.
    /// Immutable vector blobs are written first; one atomic summary write commits the generation.
    public func save(_ index: AgentOverlapIndex) throws {
        try Task.checkCancellation()
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let fm = FileManager.default
        try fm.createDirectory(at: vectorsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: relationsURL, withIntermediateDirectories: true)
        var summary = index
        var slices = index.vectorSlices ?? [:]
        let blockName = UUID().uuidString + ".bin"
        var block = Data()
        for (id, entry) in index.entries {
            try Task.checkCancellation()
            if slices[id] == nil && !entry.featureTexts.isEmpty {
                var vectors = entry.featureVectors
                if vectors.isEmpty, let name = index.vectorFiles?[id] {
                    vectors = try PropertyListDecoder().decode(PackedVectors.self,
                        from: Data(contentsOf: child(name, in: vectorsURL), options: .mappedIfSafe))
                        .unpack(expectedRows: entry.featureTexts.count)
                }
                guard vectors.count == entry.featureTexts.count, let width = vectors.first?.count,
                      width > 0, vectors.allSatisfy({ $0.count == width }) else { throw AgentOverlapError.invalidEmbeddingOutput }
                slices[id] = AgentVectorSlice(file: blockName, offset: block.count, rows: vectors.count, width: width)
                // All supported macOS architectures are little endian. Append
                // IEEE Float storage directly instead of allocating UInt32 arrays.
                for vector in vectors { vector.withUnsafeBytes { block.append(contentsOf: $0) } }
            }
            var compact = entry; compact.featureVectors = []
            summary.entries[id] = compact
        }
        if !block.isEmpty { try block.write(to: vectorsURL.appendingPathComponent(blockName), options: .atomic) }
        summary.vectorFiles = nil
        summary.vectorSlices = slices
        // Missing edges are zero only with a complete cohort certificate. Legacy
        // incomplete generations retain their explicit zero edges until repaired.
        if index.completeIDs != nil {
            summary.matches = index.matches.filter {
                $0.value.firstCovered.contains(where: { $0 != 0 }) || $0.value.secondCovered.contains(where: { $0 != 0 })
            }
        }
        if let ids = summary.completeIDs {
            // Include the full union, not merely the three displayed sources.
            summary.cachedRecommendations = nil; summary.recommendationIDs = nil
            summary.cachedRecommendations = AgentOverlapAnalyzer.recommendations(in: summary, activeIDs: ids)
            summary.recommendationIDs = ids
        }
        let groups = Dictionary(grouping: summary.matches.keys, by: { summary.matches[$0]!.firstID })
        let previousGroups = Dictionary(grouping: cached?.matches.keys.map { $0 } ?? [], by: { cached!.matches[$0]!.firstID })
        let recommendations = Dictionary(uniqueKeysWithValues: (summary.cachedRecommendations ?? []).map { ($0.sourceID, $0) })
        let previousRecommendations = Dictionary(uniqueKeysWithValues: (cached?.cachedRecommendations ?? []).map { ($0.sourceID, $0) })
        var nextFiles = [String: String]()
        for (source, entry) in summary.entries {
            try Task.checkCancellation()
            let keys = groups[source] ?? []
            let pairs = Dictionary(uniqueKeysWithValues: keys.map { ($0, summary.matches[$0]!) })
            let oldPairs = Dictionary(uniqueKeysWithValues: (previousGroups[source] ?? []).map { ($0, cached!.matches[$0]!) })
            let partition = SourcePartition(entry: entry, pairs: pairs, recommendation: recommendations[source])
            if partitionVersion == 2, cached?.entries[source] == entry, oldPairs == pairs,
               previousRecommendations[source] == recommendations[source], let name = partitionFiles[source] {
                nextFiles[source] = name; continue
            }
            let bytes = try encoder.encode(partition)
            let name = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() + ".plist"
            let destination = relationsURL.appendingPathComponent(name)
            if !fm.fileExists(atPath: destination.path) { try bytes.write(to: destination, options: .atomic) }
            nextFiles[source] = name
        }
        summary.revision = UUID().uuidString
        var header = summary; header.matches = [:]; header.entries = [:]; header.cachedRecommendations = nil
        let data = try encoder.encode(Manifest(storageVersion: 2, index: header, partitions: nextFiles))
        try Task.checkCancellation()
        try data.write(to: summaryURL, options: .atomic)
        cached = summary; cachedStamp = try stamp(summaryURL)
        partitionFiles = nextFiles
        partitionVersion = 2
    }

    /// Read only vectors needed for comparisons. Unchanged scans never call this.
    public func hydrating(_ index: AgentOverlapIndex, ids: Set<String>) throws -> AgentOverlapIndex {
        var hydrated = index
        for id in ids {
            try Task.checkCancellation()
            guard var entry = hydrated.entries[id], entry.featureVectors.isEmpty, !entry.featureTexts.isEmpty else { continue }
            if let slice = index.vectorSlices?[id] {
                let bytes: Data
                if let mapped = mappedVectors[slice.file] { bytes = mapped }
                else {
                    bytes = try Data(contentsOf: child(slice.file, in: vectorsURL), options: .alwaysMapped)
                    mappedVectors[slice.file] = bytes
                }
                guard slice.rows == entry.featureTexts.count, slice.width > 0, slice.rows > 0,
                      slice.offset >= 0, slice.offset <= bytes.count,
                      slice.width <= (bytes.count - slice.offset) / 4 / slice.rows else { throw AgentOverlapError.invalidEmbeddingOutput }
                entry.featureVectors = try Self.unpack(bytes, offset: slice.offset, rows: slice.rows, width: slice.width)
                hydrated.entries[id] = entry
                continue
            }
            guard let name = index.vectorFiles?[id], name == URL(fileURLWithPath: name).lastPathComponent,
                  UUID(uuidString: String(name.dropLast(6))) != nil, name.hasSuffix(".plist") else {
                throw AgentOverlapError.invalidEmbeddingOutput
            }
            let payload = try PropertyListDecoder().decode(PackedVectors.self,
                from: Data(contentsOf: vectorsURL.appendingPathComponent(name), options: .mappedIfSafe))
            entry.featureVectors = try payload.unpack(expectedRows: entry.featureTexts.count)
            hydrated.entries[id] = entry
        }
        return hydrated
    }

    private struct PackedVectors: Codable {
        let widths: [Int]
        let bytes: Data
        init(_ vectors: [[Float]]) {
            widths = vectors.map(\.count)
            let words = vectors.flatMap { $0.map { $0.bitPattern.littleEndian } }
            bytes = words.withUnsafeBytes { Data($0) }
        }
        func unpack(expectedRows: Int) throws -> [[Float]] {
            guard widths.count == expectedRows, Set(widths).count == 1,
                  let width = widths.first, width > 0, width <= 1_000_000,
                  expectedRows <= bytes.count / 4 / width, bytes.count / 4 / width == expectedRows,
                  bytes.count % (width * 4) == 0 else { throw AgentOverlapError.invalidEmbeddingOutput }
            return try AgentOverlapStore.unpack(bytes, offset: 0, rows: expectedRows, width: width)
        }
    }

    /// Copy full rows, then validate squared norms in Accelerate. A finite norm
    /// also rejects every NaN/Inf element; bounds are checked before this helper.
    private static func unpack(_ bytes: Data, offset: Int, rows: Int, width: Int) throws -> [[Float]] {
        try bytes.withUnsafeBytes { buffer in
            try (0..<rows).map { row in
                var vector = [Float](repeating: 0, count: width)
                let start = offset + row * width * 4
                vector.withUnsafeMutableBytes { destination in
                    destination.copyMemory(from: UnsafeRawBufferPointer(rebasing: buffer[start..<(start + width * 4)]))
                }
                var norm: Float = 0
                vDSP_dotpr(vector, 1, vector, 1, &norm, vDSP_Length(width))
                guard norm.isFinite, abs(norm - 1) < 0.01 else { throw AgentOverlapError.invalidEmbeddingOutput }
                return vector
            }
        }
    }

    private struct Descriptions: Decodable {
        let localMetadata: [String: AgentOverlapLocalMetadata]
    }

    // v1 used sortedKeys; import only user descriptions, never its old vectors or scores.
    private static func descriptionPayload(_ data: Data) throws -> Data {
        guard let start = data.range(of: Data(",\"localMetadata\":".utf8)),
              let end = data.range(of: Data(",\"matches\":".utf8)), start.lowerBound < end.lowerBound else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var result = Data([123])
        result.append(data[(start.lowerBound + 1)..<end.lowerBound])
        result.append(125)
        return result
    }
}
