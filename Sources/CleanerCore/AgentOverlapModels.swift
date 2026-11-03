import Foundation

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

    public init(id: String, kind: AgentOverlapKind, title: String, description: String, features: [String]) {
        self.id = id; self.kind = kind; self.title = title; self.description = description; self.features = features
    }
}

public struct AgentOverlapMemoryEntry: Codable, Sendable {
    public let id: String
    public let cacheID: Int
    public let kind: AgentOverlapKind
    public var title: String
    public let featureTexts: [String]
    public let featureVectors: [[Float]]
}

/// Each unordered pair stores both directional coverage masks, including zero coverage.
public struct AgentOverlapPair: Codable, Sendable {
    public let firstID: String
    public let secondID: String
    public let firstCovered: Data
    public let secondCovered: Data
}

public struct AgentOverlapTarget: Sendable, Identifiable {
    public var id: String { targetID }
    public let targetID: String
    public let title: String
    public let coverage: Double
}

public struct AgentOverlapMatch: Sendable, Identifiable {
    public var id: String { sourceID }
    public let sourceID: String
    public let targets: [AgentOverlapTarget]
    public let coveredFeatureCount: Int
    public let totalFeatureCount: Int
    public var maximumSingleCoverage: Double { targets.first?.coverage ?? 0 }
    public var coverage: Double { totalFeatureCount == 0 ? 0 : Double(coveredFeatureCount) / Double(totalFeatureCount) }
}

public struct AgentOverlapIndex: Codable, Sendable {
    public static let currentSchemaVersion = 3
    public var schemaVersion = currentSchemaVersion
    public var modelVersion: String?
    public var analysisVersion: String?
    public var entries: [String: AgentOverlapMemoryEntry] = [:]
    public var matches: [String: AgentOverlapPair] = [:]
    public var localMetadata: [String: AgentOverlapLocalMetadata] = [:]

    public init() {}
}

public struct AgentOverlapLocalMetadata: Codable, Sendable {
    public let description: String
}

public struct AgentOverlapAnalysisResult: Sendable {
    public let index: AgentOverlapIndex
    public let matches: [AgentOverlapMatch]
    public let addedIDs: Set<String>
    public let calculatedPairCount: Int
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
