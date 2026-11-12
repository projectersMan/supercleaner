import Foundation
import CryptoKit

public enum AgentOverlapError: Error, LocalizedError, Sendable {
    case invalidThreshold
    case invalidEmbeddingOutput
    case unsupportedIndexSchema
    case missingAnalysisPolicy
    case invalidAnalysisPolicy
    case truncatedEmbeddingInput
    case requiresFullRecalculation
    case unsupportedPlatform
    case inferenceWorkerUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidThreshold: "Containment threshold must be between 0.5 and 1.0."
        case .invalidEmbeddingOutput: "The local embedding model returned invalid vectors."
        case .unsupportedIndexSchema: "The local containment index uses an unsupported schema. Use Recalculate All."
        case .missingAnalysisPolicy: "The bundled containment policy is missing."
        case .invalidAnalysisPolicy: "The bundled containment policy contains invalid parameters."
        case .truncatedEmbeddingInput: "The local model truncated an analysis description."
        case .requiresFullRecalculation: "The model or analysis policy changed. Use Recalculate All in Settings."
        case .unsupportedPlatform: "Agent capability analysis requires macOS 14 or later on Apple Silicon. Other features remain available."
        case .inferenceWorkerUnavailable: "The bundled Agent inference process is unavailable or stopped before returning a result."
        }
    }
}

public enum AgentOverlapKind: String, Codable, Sendable { case skill, mcp }

public struct AgentOverlapInput: Sendable {
    public let id: String
    public let kind: AgentOverlapKind
    public let title: String
    public let description: String
    public let features: [String]
    public let contentVersion: String?
    public let platform: AgentProvider

    public init(id: String, kind: AgentOverlapKind, title: String, description: String, features: [String], contentVersion: String? = nil, platform: AgentProvider = .shared) {
        self.id = id; self.kind = kind; self.title = title; self.description = description; self.features = features; self.contentVersion = contentVersion
        self.platform = platform
    }
}

public struct AgentOverlapMemoryEntry: Codable, Sendable, Equatable {
    public let id: String
    public let cacheID: Int
    public let kind: AgentOverlapKind
    public var title: String
    public let featureTexts: [String]
    public var featureVectors: [[Float]]
    public var inputFingerprint: String? = nil
    /// Missing in legacy indexes. Never use an unclassified entry as coverage.
    public var platform: AgentProvider?

    public init(id: String, cacheID: Int, kind: AgentOverlapKind, title: String,
                featureTexts: [String], featureVectors: [[Float]], inputFingerprint: String? = nil, platform: AgentProvider? = .shared) {
        self.id = id; self.cacheID = cacheID; self.kind = kind; self.title = title
        self.featureTexts = featureTexts; self.featureVectors = featureVectors
        self.inputFingerprint = inputFingerprint
        self.platform = platform
    }

    public func canCompare(with other: Self) -> Bool {
        platform != nil && platform == other.platform && kind == other.kind
    }
}

/// Each unordered pair stores both directional coverage masks, including zero coverage.
public struct AgentOverlapPair: Codable, Sendable, Equatable {
    public let firstID: String
    public let secondID: String
    public let firstCovered: Data
    public let secondCovered: Data

    public init(firstID: String, secondID: String, firstCovered: Data, secondCovered: Data) {
        self.firstID = firstID; self.secondID = secondID
        self.firstCovered = firstCovered; self.secondCovered = secondCovered
    }
}

public struct AgentOverlapTarget: Codable, Sendable, Identifiable, Equatable {
    public var id: String { targetID }
    public let targetID: String
    public let title: String
    public let coverage: Double

    public init(targetID: String, title: String, coverage: Double) {
        self.targetID = targetID; self.title = title; self.coverage = coverage
    }
}

public struct AgentOverlapMatch: Codable, Sendable, Identifiable, Equatable {
    public var id: String { sourceID }
    public let sourceID: String
    public let targets: [AgentOverlapTarget]
    public let coveredFeatureCount: Int
    public let totalFeatureCount: Int
    public var maximumSingleCoverage: Double { targets.first?.coverage ?? 0 }
    public var coverage: Double { totalFeatureCount == 0 ? 0 : Double(coveredFeatureCount) / Double(totalFeatureCount) }

    public init(sourceID: String, targets: [AgentOverlapTarget], coveredFeatureCount: Int, totalFeatureCount: Int) {
        self.sourceID = sourceID; self.targets = targets
        self.coveredFeatureCount = coveredFeatureCount; self.totalFeatureCount = totalFeatureCount
    }
}

public struct AgentOverlapIndex: Codable, Sendable {
    public static let currentSchemaVersion = 3
    public var schemaVersion = currentSchemaVersion
    public var modelVersion: String?
    public var analysisVersion: String?
    public var entries: [String: AgentOverlapMemoryEntry] = [:]
    public var matches: [String: AgentOverlapPair] = [:]
    public var localMetadata: [String: AgentOverlapLocalMetadata] = [:]
    public var completeIDs: Set<String>?
    public var vectorFiles: [String: String]?
    public var revision: String?
    public var vectorSlices: [String: AgentVectorSlice]?
    public var recommendationIDs: Set<String>?
    public var cachedRecommendations: [AgentOverlapMatch]?
    public var comparisonPolicyVersion: Int?

    public init() {}
}

public struct AgentVectorSlice: Codable, Sendable {
    public let file: String
    public let offset: Int
    public let rows: Int
    public let width: Int
}

public struct AgentOverlapLocalMetadata: Codable, Sendable {
    public let description: String
}

public struct AgentOverlapAnalysisResult: Sendable {
    public let index: AgentOverlapIndex
    public let matches: [AgentOverlapMatch]
    public let addedIDs: Set<String>
    public let calculatedPairCount: Int
    public var changedIDs: Set<String> = []
}

public enum AgentFeatureCoverage {
    public static func empty(featureCount: Int) -> Data { Data(repeating: 0, count: (featureCount + 7) / 8) }

    public static func insert(_ position: Int, into mask: inout Data) {
        mask[position / 8] |= UInt8(1 << (position % 8))
    }

    public static func merge(_ mask: Data, into union: inout Data) {
        precondition(mask.count == union.count, "Invalid containment mask dimensions")
        for position in mask.indices { union[position] |= mask[position] }
    }

    public static func count(_ mask: Data) -> Int {
        mask.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    public static func fraction(_ mask: Data, featureCount: Int) -> Double {
        featureCount == 0 ? 0 : Double(count(mask)) / Double(featureCount)
    }
}

extension AgentOverlapInput {
    public var fingerprint: String {
        // Length boundaries are supplied by JSON, avoiding concatenation collisions.
        let data = try! JSONEncoder().encode([kind.rawValue, description, contentVersion ?? ""] + features)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
