import Foundation

public struct ValidatedPath: Hashable, Sendable {
    public let literal: URL
    public let physical: URL

    public init(literal: URL, physical: URL) {
        self.literal = literal
        self.physical = physical
    }
}

public enum PathPolicyError: Error, Equatable, Sendable {
    case invalidSyntax
    case protectedPath(String)
    case outsideAllowedHome
}

public struct PathPolicy: Sendable {
    public let homeDirectory: URL
    private let protectedSystemRoots: [String]
    private let protectedAgentRoots: [String]
    private let protectedAgentNames: Set<String>

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.protectedSystemRoots = [
            "/System", "/Library", "/bin", "/sbin", "/usr", "/etc",
            "/Applications", "/private/etc", "/private/var/db", "/var/db",
        ]
        self.protectedAgentRoots = [".codex", ".claude", ".cursor", ".agents"]
        self.protectedAgentNames = [
            "auth.json", "credentials.json", "settings.json", "config.json",
            ".env", "AGENTS.md", "CLAUDE.md",
        ]
    }

    public func validateCandidate(_ url: URL) throws -> ValidatedPath {
        let rawPath = url.path
        guard url.isFileURL,
              rawPath.hasPrefix("/"),
              !rawPath.isEmpty,
              !url.pathComponents.contains(".."),
              rawPath.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw PathPolicyError.invalidSyntax
        }

        let literal = url.standardizedFileURL
        let physical = literal.resolvingSymlinksInPath().standardizedFileURL
        try rejectProtected(literal)
        try rejectProtected(physical)
        return ValidatedPath(literal: literal, physical: physical)
    }

    public func validateApplicationBundle(_ url: URL) throws -> ValidatedPath {
        let rawPath = url.path
        guard url.isFileURL, rawPath.hasPrefix("/"), url.pathExtension.lowercased() == "app",
              !url.pathComponents.contains(".."),
              rawPath.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw PathPolicyError.invalidSyntax
        }
        let literal = url.standardizedFileURL
        let physical = literal.resolvingSymlinksInPath().standardizedFileURL
        let allowedParents = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
            homeDirectory.appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path,
            homeDirectory.appendingPathComponent("Applications", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path,
        ]
        func allowed(_ candidate: URL) -> Bool {
            let parent = candidate.deletingLastPathComponent()
            guard !parent.pathComponents.contains(where: { $0.lowercased().hasSuffix(".app") }) else { return false }
            return allowedParents.contains { root in parent.path == root || parent.path.hasPrefix(root + "/") }
        }
        guard allowed(literal), allowed(physical) else {
            throw PathPolicyError.protectedPath(physical.path)
        }
        return ValidatedPath(literal: literal, physical: physical)
    }

    private func rejectProtected(_ url: URL) throws {
        let path = normalized(url.path)
        let home = normalized(homeDirectory.path)

        if path == "/" || path == "/Users" || path == home {
            throw PathPolicyError.protectedPath(path)
        }

        if protectedSystemRoots.contains(where: { isEqualOrDescendant(path, of: $0) }) {
            throw PathPolicyError.protectedPath(path)
        }

        for rootName in protectedAgentRoots {
            let root = normalized(homeDirectory.appendingPathComponent(rootName).path)
            if path == root {
                throw PathPolicyError.protectedPath(path)
            }
            if isEqualOrDescendant(path, of: root) {
                let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let components = relative.split(separator: "/").map(String.init)
                if components.first == "skills" || components.contains(where: protectedAgentNames.contains) {
                    throw PathPolicyError.protectedPath(path)
                }
            }
        }
    }

    private func normalized(_ path: String) -> String {
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func isEqualOrDescendant(_ path: String, of root: String) -> Bool {
        let cleanRoot = normalized(root)
        return path == cleanRoot || path.hasPrefix(cleanRoot + "/")
    }
}
