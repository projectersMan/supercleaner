import CleanerCore
import Foundation

func runAgentScannerContracts() async throws {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    require(
        AgentResourcePathRegistry.rules.contains {
            $0.provider == .codex && $0.base == .home && $0.path == ".agents/skills" && $0.kind == .skillContainer
        },
        "Codex canonical user Skills path must be registered"
    )
    require(
        AgentResourcePathRegistry.rules.contains {
            $0.provider == .codex && $0.base == .project && $0.path == ".codex/config.toml" && $0.kind == .mcpConfiguration
        },
        "Codex project MCP config path must be registered"
    )
    require(
        AgentResourcePathRegistry.rules.contains {
            $0.provider == .claude && $0.base == .project && $0.path == ".mcp.json" && $0.kind == .mcpConfiguration
        },
        "Claude project MCP config path must be registered"
    )
    require(
        AgentResourcePathRegistry.rules.contains {
            $0.provider == .claude && $0.base == .absolute && $0.path == "/Library/Application Support/ClaudeCode/.claude/skills"
        },
        "Claude managed Skills path must be registered"
    )
    let now = Date(timeIntervalSince1970: 20_000_000)
    let context = ScanContext(homeDirectory: home, fileSystem: AgentContractFileSystem(home: home, now: now), now: now)
    let scanner = AgentWorkspaceScanner(adapters: [CodexProviderAdapter(), SharedAgentProviderAdapter()])
    let results = try await scanner.scan(context: context)
    let assets = try await scanner.scanAssets(context: context)

    require(results.first { $0.url.lastPathComponent == "SKILL.md" }?.risk == .blocked, "custom Skill must be blocked")
    require(results.first { $0.url.lastPathComponent == "mcp.json" }?.risk == .review, "MCP config must be eligible only through explicit selection")
    require(results.first { $0.url.lastPathComponent == "AGENTS.md" }?.risk == .blocked, "Agent instructions must be blocked")
    require(results.first { $0.url.lastPathComponent == ".build" }?.risk == .safe, "finished sandbox build cache should be safe")
    require(results.first { $0.url.lastPathComponent == "old-session.jsonl" }?.risk == .review, "sessions must require review")
    require(results.first { $0.url.lastPathComponent == ".codex" }?.risk == .blocked, "provider root must be blocked")
    require(assets.first { $0.candidate.displayName == "model-notes.md" }?.resourceKind != .modelCache, "a filename substring must not classify a model cache")
    let sharedAssets = assets.filter { $0.candidate.url.path.hasPrefix(home.appendingPathComponent(".agents").path) }
    require(!sharedAssets.isEmpty && sharedAssets.allSatisfy { $0.provider == .shared && $0.scope == .shared }, "shared Agent roots must have one shared owner")
    let protectedKinds: Set<AgentResourceKind> = [.skill, .credential, .configuration, .promptKnowledge, .sourceCode, .gitWorktree]
    require(assets.filter { protectedKinds.contains($0.resourceKind) }.allSatisfy { $0.cleanupEligibility == .protected }, "protected Agent resource kinds must never be eligible")
    require(assets.filter { $0.activity == .active }.allSatisfy { $0.cleanupEligibility == .protected }, "active Agent assets must remain protected")
    let inventory = try await scanner.scanAssetInventory(context: context)
    let skills = inventory.skills
    require(skills.count == 2, "Agent inventory must expose both personal and shared skill catalog entries")
    require(skills.contains { $0.displayName == "bits-code-guard" && $0.parseStatus == .manifestParsed }, "Skill catalog must parse manifest metadata")
    require(skills.contains { $0.source == .shared }, "shared Agent roots must also contribute skill catalog entries")
    require(
        inventory.mcpConfigurations.contains {
            $0.fileURL.lastPathComponent == "config.toml"
                && $0.parseStatus == .parsed
                && $0.servers.contains { $0.name == "official-docs" && $0.transport == .http }
                && $0.servers.contains { $0.name == "local-tool" && $0.transport == .stdio }
        },
        "Codex TOML MCP servers must be inventoried without exposing their sensitive fields"
    )
    require(
        inventory.mcpConfigurations.contains {
            $0.fileURL.lastPathComponent == "mcp.json"
                && $0.servers.contains { $0.name == "project-files" && $0.transport == .stdio }
        },
        "JSON MCP servers must be inventoried structurally"
    )
    require(assets.filter { $0.resourceKind == .mcpDefinition }.allSatisfy {
        $0.candidate.risk == .review && $0.cleanupEligibility == .retained
    }, "MCP definitions must remain retained by default while allowing deliberate selection")
    let hierarchy = AgentAssetGrouping.group(assets)
    require(hierarchy.flatMap(\.scopes).flatMap(\.resourceGroups).reduce(0) { $0 + $1.assets.count } == assets.count, "Agent hierarchy must preserve every structured asset")
    require(hierarchy.contains { $0.provider == .codex } && hierarchy.contains { $0.provider == .shared }, "Agent hierarchy must separate provider ownership")
    let selectableIDs = Set(hierarchy.flatMap(\.scopes).flatMap(\.resourceGroups).flatMap { AgentAssetGrouping.selectableIDs(in: $0) })
    require(assets.filter { $0.cleanupEligibility == .protected || $0.activity == .active }.allSatisfy { !selectableIDs.contains($0.id) }, "Agent group selection must exclude protected and active assets")
    let knowledgeCategories: Set<CleanupCategory> = [.agentSkill, .credential, .configuration, .userKnowledge]
    require(results.filter { knowledgeCategories.contains($0.category) }.allSatisfy { $0.risk == .blocked }, "Agent knowledge and credentials must never be safe")

    let externalContext = ScanContext(
        homeDirectory: home,
        fileSystem: ExternalAgentRootsContractFileSystem(home: home, now: now),
        now: now
    )
    let externalInventory = try await AgentWorkspaceScanner(adapters: [
        CodexProviderAdapter(), ClaudeProviderAdapter(), CursorProviderAdapter(),
    ]).scanAssetInventory(context: externalContext)
    let externalAssetsByPath = Dictionary(
        uniqueKeysWithValues: externalInventory.assets.map { ($0.candidate.url.standardizedFileURL.path, $0) }
    )
    let expectedExternalRoots: [(AgentProvider, String)] = [
        (.codex, ".cache/codex-runtimes"),
        (.codex, "Library/Caches/Codex"),
        (.codex, "Library/Logs/com.openai.codex"),
        (.claude, ".local/share/claude/versions"),
        (.claude, "Library/Application Support/Claude"),
        (.cursor, ".local/share/cursor-agent"),
        (.cursor, "Library/Application Support/Cursor/User/globalStorage"),
    ]
    for (provider, relativePath) in expectedExternalRoots {
        let rootPath = home.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL.path
        let rootAsset = externalAssetsByPath[rootPath]
        require(rootAsset?.provider == provider, "\(provider.rawValue) must discover external root \(relativePath)")
        require(
            rootAsset?.candidate.risk == .blocked && rootAsset?.cleanupEligibility == .protected,
            "external Agent provider roots must remain protected"
        )
    }
    let versionedRuntimeNames: Set<String> = ["runtime-2026.08", "2.0.0", "current"]
    let versionedRuntimes = externalInventory.assets.filter { versionedRuntimeNames.contains($0.candidate.displayName) }
    require(versionedRuntimes.count == versionedRuntimeNames.count, "all external versioned runtimes must be inventoried")
    require(
        versionedRuntimes.allSatisfy { $0.cleanupEligibility == .retained && $0.candidate.risk != .safe },
        "unknown or versioned Agent runtimes must never enter automatic cleanup"
    )

    let constrained = AgentWorkspaceScanner(adapters: [CodexProviderAdapter()], maximumAssets: 1)
    let constrainedInventory = try await constrained.scanAssetInventory(context: context)
    require(constrainedInventory.reachedBudget, "Agent inventory must disclose when its scan budget truncates discovery")

    let fairScanner = AgentWorkspaceScanner(
        adapters: [CodexProviderAdapter(), ClaudeProviderAdapter(), TraeProviderAdapter()],
        maximumAssets: 3
    )
    let fairInventory = try await fairScanner.scanAssetInventory(context: context)
    require(
        Set(fairInventory.assets.map(\.provider)) == Set([.codex, .claude, .trae]),
        "a wide first provider must not starve other detected Agent platforms"
    )
    require(
        fairInventory.providerCoverage[.codex]?.state == .limited,
        "a provider truncated by the shared budget must disclose limited coverage"
    )
    require(
        fairInventory.providerCoverage[.claude]?.state == .complete
            && fairInventory.providerCoverage[.trae]?.state == .complete,
        "detected providers whose roots were inspected must disclose complete coverage"
    )
    require(
        fairInventory.providerCoverage[.cursor]?.state == .notDetected,
        "known platforms with no roots must be reported as not detected instead of disappearing"
    )
    let overlappingScanner = AgentWorkspaceScanner(
        adapters: [CodexProviderAdapter(), DuplicateClaudeRootAdapter()],
        maximumAssets: 100
    )
    let overlappingInventory = try await overlappingScanner.scanAssetInventory(context: context)
    let uniquePaths = Set(overlappingInventory.assets.map { $0.candidate.url.standardizedFileURL.path })
    require(
        uniquePaths.count == overlappingInventory.assets.count,
        "Agent inventory must count each standardized path only once across providers"
    )
    require(
        overlappingInventory.assets.allSatisfy { $0.provider == .codex || $0.provider == .shared },
        "overlapping Agent paths must keep the first provider as their single owner"
    )
    require(
        overlappingInventory.providerCoverage[.claude]?.scannedAssetCount == 0,
        "provider coverage must report unique owned assets instead of duplicated traversal entries"
    )

    let unlimitedRoot = home.appendingPathComponent(".unlimited-agent", isDirectory: true)
    let unlimitedContext = ScanContext(
        homeDirectory: home,
        fileSystem: UnlimitedContractFileSystem(root: unlimitedRoot, wideChildCount: 5_001, deepChildCount: 10),
        now: now
    )
    let unlimitedInventory = try await AgentWorkspaceScanner(adapters: [
        FixedAgentRootAdapter(provider: .codex, root: unlimitedRoot),
    ]).scanAssetInventory(context: unlimitedContext)
    require(
        unlimitedInventory.assets.count == 5_012,
        "the default Agent scanner must traverse beyond the legacy 5,000-asset cap"
    )
    require(
        unlimitedInventory.assets.contains { $0.candidate.displayName == "depth-10" },
        "the default Agent scanner must traverse beyond the legacy depth-eight cap"
    )
    require(
        !unlimitedInventory.reachedBudget && unlimitedInventory.providerCoverage[.codex]?.state == .complete,
        "an uncapped default Agent scan must report complete coverage"
    )

    let cancelledScan = Task {
        try await AgentWorkspaceScanner(adapters: []).scanAssetInventory(context: unlimitedContext)
    }
    cancelledScan.cancel()
    do {
        _ = try await cancelledScan.value
        require(false, "a cancelled default Agent scan must not report successful completion")
    } catch is CancellationError {
        // Expected.
    }
}

private struct FixedAgentRootAdapter: AgentProviderAdapter {
    let provider: AgentProvider
    let scope = AgentScope.global
    let rootRelativePaths: [String] = []
    let root: URL

    func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        [AgentRoot(provider: provider, scope: scope, url: root)]
    }
}

private struct DuplicateClaudeRootAdapter: AgentProviderAdapter {
    let provider = AgentProvider.claude
    let scope = AgentScope.global
    let rootRelativePaths: [String] = []

    func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        [AgentRoot(
            provider: provider,
            scope: scope,
            url: context.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        )]
    }
}

private actor AgentContractFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]
    private let textByPath: [String: String]

    init(home: URL, now: Date) {
        let root = home.appendingPathComponent(".codex", isDirectory: true)
        let skills = root.appendingPathComponent("skills", isDirectory: true)
        let skill = skills.appendingPathComponent("custom", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let sandboxes = root.appendingPathComponent("sandboxes", isDirectory: true)
        let finished = sandboxes.appendingPathComponent("finished-task", isDirectory: true)
        let build = finished.appendingPathComponent(".build", isDirectory: true)
        let models = root.appendingPathComponent("models", isDirectory: true)
        let modelNotes = root.appendingPathComponent("model-notes.md")
        let codexConfig = root.appendingPathComponent("config.toml")
        let claudeRoot = home.appendingPathComponent(".claude", isDirectory: true)
        let traeRoot = home.appendingPathComponent(".trae", isDirectory: true)
        let sharedRoot = home.appendingPathComponent(".agents", isDirectory: true)
        let sharedSkill = sharedRoot.appendingPathComponent("skills/shared/SKILL.md")
        let urls = [root, skills, skill, skill.appendingPathComponent("SKILL.md"), codexConfig, root.appendingPathComponent("mcp.json"), root.appendingPathComponent("AGENTS.md"), sessions, sessions.appendingPathComponent("old-session.jsonl"), sandboxes, finished, build, models, modelNotes, claudeRoot, traeRoot, sharedRoot, sharedSkill]
        childrenByPath = [
            root.path: [skills, codexConfig, root.appendingPathComponent("mcp.json"), root.appendingPathComponent("AGENTS.md"), sessions, sandboxes, models, modelNotes],
            skills.path: [skill], skill.path: [skill.appendingPathComponent("SKILL.md")],
            sessions.path: [sessions.appendingPathComponent("old-session.jsonl")],
            sandboxes.path: [finished], finished.path: [build],
            sharedRoot.path: [sharedSkill],
        ]
        identities = Dictionary(uniqueKeysWithValues: urls.map { url in
            let directoryPaths: Set<String> = [root, skills, skill, sessions, sandboxes, finished, build, models, claudeRoot, traeRoot, sharedRoot].reduce(into: []) { $0.insert($1.path) }
            return (url.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64(url.path.hashValue)), size: 100, modificationTime: Int64(now.addingTimeInterval(-45 * 86_400).timeIntervalSince1970), kind: directoryPaths.contains(url.path) ? .directory : .file))
        })
        textByPath = [
            skill.appendingPathComponent("SKILL.md").path: """
            ---
            name: bits-code-guard
            description: 代码审查与 HTML 报告输出
            tags: ["代码审查", "HTML 报告"]
            triggers: ["/bits-code-guard"]
            ---

            # bits-code-guard
            """,
            sharedSkill.path: """
            # shared-knowledge-skill

            共享目录中的 Skill。
            """,
            codexConfig.path: """
            [mcp_servers.official-docs]
            url = "https://example.invalid/mcp"
            bearer_token_env_var = "SECRET_TOKEN"

            [mcp_servers.local-tool]
            command = "private-command"
            args = ["--secret"]
            """,
            root.appendingPathComponent("mcp.json").path: """
            {"mcpServers":{"project-files":{"command":"private-command","env":{"TOKEN":"secret"}}}}
            """,
        ]
    }

    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func readText(at url: URL, maximumBytes: Int) throws -> String { String(textByPath[url.path]!.prefix(maximumBytes)) }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor UnlimitedContractFileSystem: FileSystemAccess {
    private let root: URL
    private let childrenByPath: [String: [URL]]

    init(root: URL, wideChildCount: Int, deepChildCount: Int) {
        self.root = root
        let wideChildren = (0..<wideChildCount).map { root.appendingPathComponent("entry-\($0)") }
        var children = [root.path: wideChildren]
        var parent = root
        for depth in 1...deepChildCount {
            let child = parent.appendingPathComponent("depth-\(depth)", isDirectory: true)
            children[parent.path, default: []].append(child)
            parent = child
        }
        childrenByPath = children
    }

    func identity(at url: URL) throws -> FileIdentity {
        FileIdentity(
            device: 1,
            inode: UInt64(bitPattern: Int64(url.path.hashValue)),
            size: 1,
            modificationTime: 1,
            kind: url == root || childrenByPath[url.path] != nil ? .directory : .file
        )
    }

    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor ExternalAgentRootsContractFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]

    init(home: URL, now: Date) {
        let rootsAndChildren: [(String, String)] = [
            (".cache/codex-runtimes", "runtime-2026.08"),
            ("Library/Caches/Codex", "cache-entry"),
            ("Library/Logs/com.openai.codex", "runtime.log"),
            (".local/share/claude/versions", "2.0.0"),
            ("Library/Application Support/Claude", "workspace-state"),
            (".local/share/cursor-agent", "current"),
            ("Library/Application Support/Cursor/User/globalStorage", "state.vscdb"),
        ]
        var children: [String: [URL]] = [:]
        var allURLs: [URL] = []
        var directoryPaths = Set<String>()
        for (rootRelativePath, childName) in rootsAndChildren {
            let root = home.appendingPathComponent(rootRelativePath, isDirectory: true)
            let child = root.appendingPathComponent(childName, isDirectory: true)
            children[root.path] = [child]
            allURLs.append(contentsOf: [root, child])
            directoryPaths.formUnion([root.path, child.path])
        }
        childrenByPath = children
        identities = Dictionary(uniqueKeysWithValues: allURLs.map { url in
            (
                url.path,
                FileIdentity(
                    device: 1,
                    inode: UInt64(bitPattern: Int64(url.path.hashValue)),
                    size: 100,
                    modificationTime: Int64(now.addingTimeInterval(-45 * 86_400).timeIntervalSince1970),
                    kind: directoryPaths.contains(url.path) ? .directory : .file
                )
            )
        })
    }

    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
