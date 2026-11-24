import Foundation

public struct ModelStorageRoot: Codable, Hashable, Identifiable, Sendable {
    public let provider: LocalAIModelProvider
    public let url: URL
    public var id: String { provider.rawValue + "|" + url.standardizedFileURL.path }

    public init(provider: LocalAIModelProvider, url: URL) {
        self.provider = provider
        self.url = url
    }

    public static func validate(_ url: URL, home: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.pathComponents.contains(".."),
              !["/", "/Users", "/Volumes", home.standardizedFileURL.path].contains(url.standardizedFileURL.path),
              !url.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ModelStorageRootError.invalidPath(url.path)
        }
        _ = try PathPolicy(homeDirectory: home).validateCandidate(url)
    }
}

public enum ModelStorageRootError: Error, LocalizedError {
    case invalidPath(String), invalidConfiguration
    public var errorDescription: String? {
        switch self {
        case let .invalidPath(path): L10n.text("模型存储目录无效：{0}", path)
        case .invalidConfiguration: L10n.text("模型目录配置必须包含 schemaVersion 1 和 roots 列表。")
        }
    }
}

public actor ModelStorageRootsStore {
    private struct Document: Codable {
        let schemaVersion: Int
        let roots: [ModelStorageRoot]
    }
    private let url: URL
    private let home: URL

    public init(url: URL, home: URL) { self.url = url; self.home = home }

    public func roots() throws -> [ModelStorageRoot] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.schemaVersion == 1 else { throw ModelStorageRootError.invalidConfiguration }
        return try normalized(document.roots)
    }

    @discardableResult public func save(_ roots: [ModelStorageRoot]) throws -> [ModelStorageRoot] {
        let roots = try normalized(roots)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Document(schemaVersion: 1, roots: roots)).write(to: url, options: .atomic)
        return roots
    }

    private func normalized(_ roots: [ModelStorageRoot]) throws -> [ModelStorageRoot] {
        for root in roots { try ModelStorageRoot.validate(root.url, home: home) }
        let normalized = roots.map {
            ModelStorageRoot(provider: $0.provider, url: URL(fileURLWithPath: $0.url.standardizedFileURL.path, isDirectory: true))
        }
        return Array(Set(normalized)).sorted(by: Self.rootOrder)
    }

    private static func rootOrder(_ left: ModelStorageRoot, _ right: ModelStorageRoot) -> Bool { left.id < right.id }
}
