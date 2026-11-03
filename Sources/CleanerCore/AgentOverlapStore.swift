import Foundation

public actor AgentOverlapStore {
    public let url: URL
    private let descriptionSources: [URL]

    public init(url: URL, descriptionSources: [URL]) {
        self.url = url.standardizedFileURL
        self.descriptionSources = descriptionSources
    }

    public func load(resetAnalysis: Bool) throws -> AgentOverlapIndex {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if resetAnalysis {
                var empty = AgentOverlapIndex()
                empty.localMetadata = try PropertyListDecoder().decode(Descriptions.self, from: data).localMetadata
                return empty
            }
            let index = try PropertyListDecoder().decode(AgentOverlapIndex.self, from: data)
            guard index.schemaVersion == AgentOverlapIndex.currentSchemaVersion else { throw AgentOverlapError.unsupportedIndexSchema }
            return index
        }
        var empty = AgentOverlapIndex()
        for source in descriptionSources where FileManager.default.fileExists(atPath: source.path) {
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

    public func save(_ index: AgentOverlapIndex) throws {
        try Task.checkCancellation()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(index)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
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
