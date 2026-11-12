import Foundation

/// Caches directory membership, never file identities, content, or deletion eligibility.
/// Every nested directory is independently checked, so a deep mutation cannot hide
/// behind an unchanged ancestor. Failed reads and unstable generations aren't cached.
public actor AgentDirectorySnapshot {
    struct CapabilityDirectory: Sendable {
        let directories: [URL]
        let skills: [SkillCatalogEntry]
        let configurations: [MCPConfigurationRecord]
    }
    private struct CatalogEntry {
        let generation: String
        let stamps: [String: String]
        let value: CapabilityDirectory
    }
    public static let shared = AgentDirectorySnapshot()
    private struct Entry { let generation: String; let children: [URL] }
    private var entries: [String: Entry] = [:]
    private var catalogs: [String: CatalogEntry] = [:]
    public private(set) var catalogHits = 0
    public private(set) var catalogMisses = 0
    public private(set) var hits = 0
    public private(set) var misses = 0
    public init() {}

    /// Reuse an unchanged capability subtree's membership and parsed local data.
    /// Each nested directory is still generation-checked: file writes do not
    /// propagate to ancestor mtimes, so manifest/config stamps are checked too.
    func capabilities(in url: URL, root: AgentRoot, resolver: AgentResourcePathRegistry.Resolver, context: ScanContext) async throws -> CapabilityDirectory {
        try Task.checkCancellation()
        let fs = context.fileSystem
        let key = context.homeDirectory.path + "|" + root.provider.rawValue + "|" + root.scope.rawValue + "|" + url.path
        let generation = try await fs.directoryGeneration(at: url)
        if let generation, let known = catalogs[key], generation == known.generation {
            var same = true
            for (path, stamp) in known.stamps {
                if (try? await fs.itemGeneration(at: URL(fileURLWithPath: path))) != stamp { same = false; break }
            }
            if same { catalogHits += 1; return known.value }
        }
        catalogs.removeValue(forKey: key)
        catalogMisses += 1
        let members = try await children(of: url, fileSystem: fs)
        var directories = [URL](), skills = [SkillCatalogEntry](), configurations = [MCPConfigurationRecord]()
        var stamps = [String: String]()
        var canCache = generation != nil
        let isSkillRoot = SkillCatalogSupport.rootPath(for: url) == url.path
        for child in members {
            try Task.checkCancellation()
            guard let identity = try? await fs.identity(at: child) else { canCache = false; continue }
            if identity.kind == .symbolicLink { continue }
            if identity.kind == .directory { directories.append(child) }
            let manifest = child.lastPathComponent.lowercased() == "skill.md"
            let fileSkillRoot = identity.kind != .directory && SkillCatalogSupport.rootPath(for: child) == child.path
            let mcp = MCPConfigurationCatalogSupport.isSupportedConfiguration(url: child)
            if manifest || mcp || fileSkillRoot {
                if let stamp = try await fs.itemGeneration(at: child) { stamps[child.path] = stamp }
                else { canCache = false }
            }
            if (manifest && !isSkillRoot || fileSkillRoot && !manifest),
               let entry = await SkillCatalogSupport.makeEntry(provider: root.provider, scope: resolver.matchingRule(for: child)?.scope ?? root.scope, discoveredURL: child, fileSystem: fs) {
                skills.append(entry)
            }
            if mcp, let entry = await MCPConfigurationCatalogSupport.makeRecord(provider: root.provider, scope: resolver.matchingRule(for: child)?.scope ?? root.scope,
                url: child, homeDirectory: context.homeDirectory, fileSystem: fs) { configurations.append(entry) }
        }
        if isSkillRoot, let skill = await SkillCatalogSupport.makeEntry(provider: root.provider, scope: resolver.matchingRule(for: url)?.scope ?? root.scope,
            discoveredURL: url, fileSystem: fs) { skills.append(skill) }
        let value = CapabilityDirectory(directories: directories, skills: skills, configurations: configurations)
        if canCache, let generation, generation == (try await fs.directoryGeneration(at: url)) {
            // Don't commit a parsed snapshot if a capability file changed during parsing.
            var stable = true
            for (path, stamp) in stamps {
                if (try? await fs.itemGeneration(at: URL(fileURLWithPath: path))) != stamp { stable = false; break }
            }
            if stable {
                if catalogs.count >= 100_000 { catalogs.removeAll(keepingCapacity: true) }
                catalogs[key] = CatalogEntry(generation: generation, stamps: stamps, value: value)
            }
        }
        return value
    }

    public func children(of url: URL, fileSystem: any FileSystemAccess) async throws -> [URL] {
        try Task.checkCancellation()
        let path = url.standardizedFileURL.path
        let generation = try await fileSystem.directoryGeneration(at: url)
        if let generation, let entry = entries[path], entry.generation == generation {
            hits += 1
            return entry.children
        }
        entries.removeValue(forKey: path)
        misses += 1
        let children = try await fileSystem.children(of: url)
        try Task.checkCancellation()
        if let generation, generation == (try await fileSystem.directoryGeneration(at: url)) {
            if entries.count >= 100_000 { entries.removeAll(keepingCapacity: true) }
            entries[path] = Entry(generation: generation, children: children)
        }
        return children
    }
}
