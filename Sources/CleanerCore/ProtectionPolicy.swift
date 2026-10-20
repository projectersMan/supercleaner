import Foundation

public struct ProtectedPath: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let physicalURL: URL
    public let addedAt: Date

    public init(id: UUID = UUID(), url: URL, addedAt: Date = Date()) {
        self.id = id
        self.url = url.standardizedFileURL
        physicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        self.addedAt = addedAt
    }
}

public enum ProtectionError: Error, Equatable, Sendable {
    case invalidPath
    case unreadablePolicy
    case protectedPath(String)
}

/// A directory cannot be removed if it contains a protected path. Literal and
/// physical paths both deny access; resolving a link never grants permission.
public struct ProtectionPolicy: Sendable {
    public let entries: [ProtectedPath]
    public let isAvailable: Bool
    private let builtInPaths: [URL]

    public init(
        entries: [ProtectedPath] = [],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isAvailable: Bool = true
    ) {
        self.entries = entries
        self.isAvailable = isAvailable
        builtInPaths = [
            ".ssh", ".gnupg", ".aws", ".kube", ".config/gcloud",
            ".docker/config.json", "Library/Keychains", "Library/Application Support/SuperCleaner",
        ].map { homeDirectory.appendingPathComponent($0).standardizedFileURL }
    }

    public func validate(_ url: URL) throws {
        guard isAvailable else { throw ProtectionError.unreadablePolicy }
        let proposed = [url.standardizedFileURL, url.resolvingSymlinksInPath().standardizedFileURL]
        let denied = builtInPaths.flatMap { [$0, $0.resolvingSymlinksInPath().standardizedFileURL] }
            + entries.flatMap { [$0.url, $0.physicalURL, $0.url.resolvingSymlinksInPath().standardizedFileURL] }
        if proposed.contains(where: { target in denied.contains { Self.overlaps(target.path, $0.path) } }) {
            throw ProtectionError.protectedPath(url.path)
        }
    }

    public func applying(to candidate: CleanupCandidate) -> CleanupCandidate {
        do { try validate(candidate.url); return candidate }
        catch {
            return candidate.replacing(
                risk: .blocked,
                evidence: candidate.evidence + [Evidence(
                    code: isAvailable ? "protected-by-policy" : "protection-unavailable",
                    summary: isAvailable ? "此路径或其内容受到保护" : "保护清单无法读取，暂停删除"
                )]
            )
        }
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs == "/" ? "/" : rhs + "/")
            || rhs.hasPrefix(lhs == "/" ? "/" : lhs + "/")
    }
}

public actor ProtectionStore {
    public let url: URL
    private let homeDirectory: URL

    public init(url: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.url = url
        self.homeDirectory = homeDirectory
    }

    public func snapshot() throws -> ProtectionPolicy {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) {
                return ProtectionPolicy(homeDirectory: homeDirectory)
            }
            throw ProtectionError.unreadablePolicy
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1_048_576 else { throw ProtectionError.unreadablePolicy }
        guard let entries = try? JSONDecoder().decode([ProtectedPath].self, from: Data(contentsOf: url)),
              entries.allSatisfy({ Self.valid($0.url) && Self.valid($0.physicalURL) }),
              Set(entries.map(\.id)).count == entries.count else {
            throw ProtectionError.unreadablePolicy
        }
        return ProtectionPolicy(entries: entries, homeDirectory: homeDirectory)
    }

    @discardableResult public func protect(_ path: URL) throws -> ProtectionPolicy {
        guard Self.valid(path) else { throw ProtectionError.invalidPath }
        var entries = try snapshot().entries
        let entry = ProtectedPath(url: path)
        if !entries.contains(where: { $0.url == entry.url }) { entries.append(entry) }
        return try save(entries)
    }

    @discardableResult public func remove(id: UUID) throws -> ProtectionPolicy {
        try save(snapshot().entries.filter { $0.id != id })
    }

    private func save(_ entries: [ProtectedPath]) throws -> ProtectionPolicy {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        return ProtectionPolicy(entries: entries, homeDirectory: homeDirectory)
    }

    private static func valid(_ path: URL) -> Bool {
        path.isFileURL && path.path.hasPrefix("/") && !path.pathComponents.contains("..")
            && path.path.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
