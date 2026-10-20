import Foundation

public enum AgentResourcePathKind: String, Codable, Hashable, Sendable {
    case providerData
    case skillContainer
    case mcpConfiguration
}

public enum AgentResourcePathBase: String, Codable, Hashable, Sendable {
    case home
    case project
    case absolute
}

public struct AgentResourcePathRule: Codable, Hashable, Sendable {
    public let provider: AgentProvider
    public let scope: AgentScope
    public let kind: AgentResourcePathKind
    public let base: AgentResourcePathBase
    public let path: String
    public let sourceLabel: String

    public init(
        provider: AgentProvider,
        scope: AgentScope,
        kind: AgentResourcePathKind,
        base: AgentResourcePathBase,
        path: String,
        sourceLabel: String
    ) {
        self.provider = provider
        self.scope = scope
        self.kind = kind
        self.base = base
        self.path = path
        self.sourceLabel = sourceLabel
    }
}

/// Single source of truth for filesystem locations documented by Agent vendors.
/// Keep vendor-specific paths here so scanner upgrades do not spread string rules across UI and traversal code.
public enum AgentResourcePathRegistry {
    public static let projectArtifactSeedPaths = [".codex/worktrees", ".claude/worktrees", ".worktrees"]
    public static let rules: [AgentResourcePathRule] = [
        // OpenAI Codex: user, repository, administrator, and compatibility locations.
        .init(provider: .codex, scope: .global, kind: .providerData, base: .home, path: ".codex", sourceLabel: "OpenAI Codex user data"),
        .init(provider: .codex, scope: .global, kind: .skillContainer, base: .home, path: ".agents/skills", sourceLabel: "OpenAI Codex user Skills"),
        .init(provider: .codex, scope: .global, kind: .skillContainer, base: .home, path: ".codex/skills", sourceLabel: "Codex compatibility/system Skills"),
        .init(provider: .codex, scope: .global, kind: .mcpConfiguration, base: .home, path: ".codex/config.toml", sourceLabel: "OpenAI Codex user MCP configuration"),
        .init(provider: .codex, scope: .project, kind: .skillContainer, base: .project, path: ".agents/skills", sourceLabel: "OpenAI Codex repository Skills"),
        .init(provider: .codex, scope: .project, kind: .skillContainer, base: .project, path: ".codex/skills", sourceLabel: "Codex project compatibility Skills"),
        .init(provider: .codex, scope: .project, kind: .mcpConfiguration, base: .project, path: ".codex/config.toml", sourceLabel: "OpenAI Codex project MCP configuration"),
        .init(provider: .codex, scope: .shared, kind: .skillContainer, base: .absolute, path: "/etc/codex/skills", sourceLabel: "OpenAI Codex administrator Skills"),
        .init(provider: .codex, scope: .shared, kind: .mcpConfiguration, base: .absolute, path: "/etc/codex/config.toml", sourceLabel: "OpenAI Codex system MCP configuration"),

        // Anthropic Claude Code: personal, synced, repository, plugin-compatible, and managed locations.
        .init(provider: .claude, scope: .global, kind: .providerData, base: .home, path: ".claude", sourceLabel: "Claude Code user data"),
        .init(provider: .claude, scope: .global, kind: .skillContainer, base: .home, path: ".claude/skills", sourceLabel: "Claude Code personal and synced Skills"),
        .init(provider: .claude, scope: .global, kind: .mcpConfiguration, base: .home, path: ".claude.json", sourceLabel: "Claude Code user and local MCP configuration"),
        .init(provider: .claude, scope: .global, kind: .mcpConfiguration, base: .home, path: "Library/Application Support/Claude/claude_desktop_config.json", sourceLabel: "Claude Desktop MCP configuration"),
        .init(provider: .claude, scope: .project, kind: .skillContainer, base: .project, path: ".claude/skills", sourceLabel: "Claude Code project and nested Skills"),
        .init(provider: .claude, scope: .project, kind: .mcpConfiguration, base: .project, path: ".mcp.json", sourceLabel: "Claude Code project MCP configuration"),
        .init(provider: .claude, scope: .shared, kind: .skillContainer, base: .absolute, path: "/Library/Application Support/ClaudeCode/.claude/skills", sourceLabel: "Claude Code managed Skills"),
        .init(provider: .claude, scope: .shared, kind: .mcpConfiguration, base: .absolute, path: "/Library/Application Support/ClaudeCode/managed-mcp.json", sourceLabel: "Claude Code managed MCP configuration"),

        // Other established local roots retained by the product.
        .init(provider: .codex, scope: .global, kind: .providerData, base: .home, path: ".cache/codex-runtimes", sourceLabel: "Codex runtime cache"),
        .init(provider: .codex, scope: .global, kind: .providerData, base: .home, path: "Library/Caches/Codex", sourceLabel: "Codex application cache"),
        .init(provider: .codex, scope: .global, kind: .providerData, base: .home, path: "Library/Logs/com.openai.codex", sourceLabel: "Codex logs"),
        .init(provider: .claude, scope: .global, kind: .providerData, base: .home, path: ".local/share/claude/versions", sourceLabel: "Claude Code installed versions"),
        .init(provider: .claude, scope: .global, kind: .providerData, base: .home, path: "Library/Application Support/Claude", sourceLabel: "Claude application support"),
        .init(provider: .cursor, scope: .global, kind: .providerData, base: .home, path: ".cursor", sourceLabel: "Cursor user data"),
        .init(provider: .cursor, scope: .global, kind: .providerData, base: .home, path: ".local/share/cursor-agent", sourceLabel: "Cursor Agent runtime"),
        .init(provider: .cursor, scope: .global, kind: .providerData, base: .home, path: "Library/Application Support/Cursor/User/globalStorage", sourceLabel: "Cursor global storage"),
        .init(provider: .trae, scope: .global, kind: .providerData, base: .home, path: ".trae", sourceLabel: "Trae user data"),
        .init(provider: .trae, scope: .global, kind: .providerData, base: .home, path: ".trae-cn", sourceLabel: "Trae CN user data"),
        .init(provider: .trae, scope: .global, kind: .providerData, base: .home, path: "Library/Application Support/Trae", sourceLabel: "Trae application support"),
        .init(provider: .trae, scope: .global, kind: .providerData, base: .home, path: "Library/Application Support/Trae CN", sourceLabel: "Trae CN application support"),
        .init(provider: .genericMCP, scope: .global, kind: .providerData, base: .home, path: ".config/mcp", sourceLabel: "Generic MCP configuration"),
        .init(provider: .git, scope: .project, kind: .providerData, base: .home, path: ".worktrees", sourceLabel: "Git worktrees"),
        .init(provider: .shared, scope: .shared, kind: .providerData, base: .home, path: ".agents", sourceLabel: "Shared Agent resources"),
    ]

    public static func homeRelativeRoots(for provider: AgentProvider) -> [String] {
        unique(rules.filter { $0.provider == provider && $0.base == .home }.map(\.path))
    }

    public static func absoluteRoots(for provider: AgentProvider) -> [AgentRoot] {
        rules.filter { $0.provider == provider && $0.base == .absolute }.map {
            AgentRoot(provider: $0.provider, scope: $0.scope, url: URL(fileURLWithPath: $0.path, isDirectory: $0.kind != .mcpConfiguration))
        }
    }

    public static func projectRules(for provider: AgentProvider) -> [AgentResourcePathRule] {
        rules.filter { $0.provider == provider && $0.base == .project }
    }

    /// Codex can relocate its state root with CODEX_HOME. The canonical `.agents/skills`
    /// location remains under HOME, but compatibility Skills and config.toml follow this root.
    public static func environmentRoots(for provider: AgentProvider) -> [AgentRoot] {
        guard provider == .codex,
              let configuredPath = ProcessInfo.processInfo.environment["CODEX_HOME"],
              !configuredPath.isEmpty
        else { return [] }
        return [AgentRoot(provider: .codex, scope: .global, url: URL(fileURLWithPath: configuredPath, isDirectory: true))]
    }

    public static func matchingRule(for url: URL, homeDirectory: URL) -> AgentResourcePathRule? {
        let path = url.standardizedFileURL.path
        return rules.compactMap { rule -> (rule: AgentResourcePathRule, targetLength: Int, exact: Bool)? in
            let target: URL
            switch rule.base {
            case .home:
                target = homeDirectory.appendingPathComponent(rule.path)
            case .absolute:
                target = URL(fileURLWithPath: rule.path)
            case .project:
                let exact = path.hasSuffix("/" + rule.path)
                guard exact || path.contains("/" + rule.path + "/") else { return nil }
                return (rule, rule.path.count, exact)
            }
            let targetPath = target.standardizedFileURL.path
            guard path == targetPath || path.hasPrefix(targetPath + "/") else { return nil }
            return (rule, targetPath.count, path == targetPath)
        }
        .sorted {
            if $0.exact != $1.exact { return $0.exact && !$1.exact }
            return $0.targetLength > $1.targetLength
        }
        .first?.rule
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

enum AgentProjectResourceDiscovery {
    private static let maximumDepth = 7
    private static let maximumDirectories = 20_000
    private static let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", "vendor", "deriveddata", ".build", "build", "dist",
        "library", "applications", "movies", "music", "pictures", "downloads", ".trash",
    ]
    private static let preferredSeedNames = [
        "Desktop", "Documents", "Developer", "Projects", "code", "src", "workspace", "work", "repos", "git",
    ]

    static func discover(
        provider: AgentProvider,
        context: ScanContext
    ) async -> [AgentRoot] {
        let rules = AgentResourcePathRegistry.projectRules(for: provider)
        guard !rules.isEmpty else { return [] }
        var seeds = [context.homeDirectory]
        for name in preferredSeedNames {
            let candidate = context.homeDirectory.appendingPathComponent(name, isDirectory: true)
            if await context.fileSystem.fileExists(candidate) { seeds.append(candidate) }
        }
        var queue = seeds.map { ($0.standardizedFileURL, 0) }
        var cursor = 0
        var visited = Set<String>()
        var roots: [AgentRoot] = []
        while cursor < queue.count, visited.count < maximumDirectories {
            if Task.isCancelled { break }
            let (directory, depth) = queue[cursor]
            cursor += 1
            guard visited.insert(directory.path).inserted else { continue }
            for rule in rules {
                let candidate = directory.appendingPathComponent(rule.path, isDirectory: rule.kind != .mcpConfiguration)
                if await context.fileSystem.fileExists(candidate) {
                    roots.append(AgentRoot(provider: provider, scope: .project, url: candidate.standardizedFileURL))
                }
            }
            guard depth < maximumDepth else { continue }
            let children = (try? await context.fileSystem.children(of: directory)) ?? []
            for child in children {
                let name = child.lastPathComponent.lowercased()
                if skippedDirectoryNames.contains(name) || (name.hasPrefix(".") && name != ".config") { continue }
                guard let identity = try? await context.fileSystem.identity(at: child), identity.kind == .directory else { continue }
                queue.append((child.standardizedFileURL, depth + 1))
            }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.url.path).inserted }
    }
}

public struct CodexProjectProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.codex
    public let scope = AgentScope.project
    public let rootRelativePaths: [String] = []
    public init() {}
    public func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        await AgentProjectResourceDiscovery.discover(provider: provider, context: context)
    }
}

public struct ClaudeProjectProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.claude
    public let scope = AgentScope.project
    public let rootRelativePaths: [String] = []
    public init() {}
    public func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        await AgentProjectResourceDiscovery.discover(provider: provider, context: context)
    }
}
