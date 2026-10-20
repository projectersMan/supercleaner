import Foundation

public enum AgentAssetKind: String, Codable, Hashable, Sendable, CaseIterable {
    case providerRoot
    case skill
    case mcpConfiguration
    case credential
    case promptOrInstruction
    case session
    case sandbox
    case reproducibleCache
    case modelCache
    case packageCache
    case worktree
    case unknown
}

public enum AgentProvider: String, Codable, Hashable, Sendable, CaseIterable {
    case codex, claude, cursor, trae, genericMCP, git, shared
}

public enum AgentScope: String, Codable, Hashable, Sendable, CaseIterable {
    case global, project, shared
}

public enum AgentResourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case runtimeTemporaryOutput
    case completedTaskCache
    case buildCache
    case packageCache
    case modelCache
    case sessionHistory
    case sandboxWorkspace
    case skill
    case mcpDefinition
    case configuration
    case credential
    case promptKnowledge
    case sourceCode
    case gitWorktree
    case unknown
}

public enum AgentActivity: String, Codable, Hashable, Sendable {
    case active, recent, completed, unknown
}

public enum AgentCleanupEligibility: String, Codable, Hashable, Sendable {
    case recommended, deep, retained, protected
}

public struct AgentAssetRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public let provider: AgentProvider
    public let scope: AgentScope
    public let resourceKind: AgentResourceKind
    public let activity: AgentActivity
    public let cleanupEligibility: AgentCleanupEligibility
    public let cleanupUnitURL: URL

    public init(
        candidate: CleanupCandidate,
        provider: AgentProvider,
        scope: AgentScope,
        resourceKind: AgentResourceKind,
        activity: AgentActivity,
        cleanupEligibility: AgentCleanupEligibility,
        cleanupUnitURL: URL
    ) {
        self.candidate = candidate
        self.provider = provider
        self.scope = scope
        self.resourceKind = resourceKind
        self.activity = activity
        self.cleanupEligibility = cleanupEligibility
        self.cleanupUnitURL = cleanupUnitURL.standardizedFileURL
    }
}

public struct AgentRoot: Codable, Hashable, Sendable {
    public let provider: AgentProvider
    public let scope: AgentScope
    public let url: URL

    public var providerID: String { provider.rawValue }

    public init(provider: AgentProvider, scope: AgentScope, url: URL) {
        self.provider = provider
        self.scope = scope
        self.url = url
    }
}

public struct AgentAssetRelation: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case contains
        case generatedBy
        case references
        case protects
    }

    public let from: URL
    public let to: URL
    public let kind: Kind

    public init(from: URL, to: URL, kind: Kind) {
        self.from = from
        self.to = to
        self.kind = kind
    }
}

public struct AgentClassification: Sendable, Hashable {
    public let kind: AgentAssetKind
    public let category: CleanupCategory
    public let risk: RiskLevel
    public let evidence: [Evidence]

    public init(kind: AgentAssetKind, category: CleanupCategory, risk: RiskLevel, evidence: [Evidence]) {
        self.kind = kind
        self.category = category
        self.risk = risk
        self.evidence = evidence
    }
}

public protocol AgentProviderAdapter: Sendable {
    var provider: AgentProvider { get }
    var scope: AgentScope { get }
    var rootRelativePaths: [String] { get }
    func discoverRoots(context: ScanContext) async -> [AgentRoot]
    func classify(url: URL, root: AgentRoot, context: ScanContext) async -> AgentClassification
}

public extension AgentProviderAdapter {
    func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        var roots: [AgentRoot] = []
        for relativePath in rootRelativePaths {
            let url = context.homeDirectory.appendingPathComponent(relativePath)
            if await context.fileSystem.fileExists(url) {
                roots.append(AgentRoot(provider: provider, scope: scope, url: url))
            }
        }
        for root in AgentResourcePathRegistry.absoluteRoots(for: provider)
        where await context.fileSystem.fileExists(root.url) {
            roots.append(root)
        }
        for root in AgentResourcePathRegistry.environmentRoots(for: provider)
        where await context.fileSystem.fileExists(root.url) {
            roots.append(root)
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    func classify(url: URL, root: AgentRoot, context: ScanContext) async -> AgentClassification {
        await AgentSemanticClassifier.classify(url: url, root: root, context: context)
    }
}

public struct CodexProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.codex
    public let scope = AgentScope.global
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .codex)
    public init() {}
}

public struct ClaudeProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.claude
    public let scope = AgentScope.global
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .claude)
    public init() {}
}

public struct CursorProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.cursor
    public let scope = AgentScope.global
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .cursor)
    public init() {}
}

public struct GenericMCPProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.genericMCP
    public let scope = AgentScope.global
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .genericMCP)
    public init() {}
}

public struct GitWorktreeProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.git
    public let scope = AgentScope.project
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .git)
    public init() {}
}

public struct TraeProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.trae
    public let scope = AgentScope.global
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .trae)
    public init() {}
}

public struct SharedAgentProviderAdapter: AgentProviderAdapter {
    public let provider = AgentProvider.shared
    public let scope = AgentScope.shared
    public let rootRelativePaths = AgentResourcePathRegistry.homeRelativeRoots(for: .shared)
    public init() {}
}

private enum AgentSemanticClassifier {
    static let protectedConfigNames: Set<String> = [
        "mcp.json", ".mcp.json", "settings.json", "config.json",
    ]
    static let credentialNames: Set<String> = [
        "auth.json", "credentials.json", ".env", "keychain.json", "tokens.json",
    ]
    static let instructionNames: Set<String> = [
        "agents.md", "claude.md", "memory.md", "prompt.md", "instructions.md",
    ]
    static let reproducibleCacheNames: Set<String> = [
        ".build", "deriveddata", "node_modules", "target", "dist", "build", "__pycache__",
    ]
    static let packageCacheNames: Set<String> = [
        "_cacache", "pip", "uv", "pnpm", "yarn", "package-cache",
    ]
    static let sourceExtensions: Set<String> = [
        "c", "cc", "cpp", "go", "h", "hpp", "java", "js", "jsx", "kt", "m", "mm", "py", "rb", "rs", "sh", "swift", "ts", "tsx",
    ]

    static func classify(url: URL, root: AgentRoot, context: ScanContext) async -> AgentClassification {
        let lowerName = url.lastPathComponent.lowercased()
        let lowerComponents = url.pathComponents.map { $0.lowercased() }
        let isActive = context.isActive(url)
        let identity = try? await context.fileSystem.identity(at: url)
        let age = identity.map { context.now.timeIntervalSince1970 - Double($0.modificationTime) } ?? 0
        let isOld = age >= 30 * 86_400
        let hasCompletionEvidence = lowerComponents.contains { component in
            component.contains("finished") || component.contains("completed") || component.contains("archived")
        }

        let kind: AgentAssetKind
        let category: CleanupCategory
        let baselineRisk: RiskLevel
        let reason: String

        if AgentResourcePathRegistry.matchingRule(for: url, homeDirectory: context.homeDirectory)?.kind == .mcpConfiguration
            || MCPConfigurationCatalogSupport.isSupportedConfiguration(url: url) {
            (kind, category, baselineRisk, reason) = (.mcpConfiguration, .agentMCP, .review, L10n.text("MCP 配置可能包含凭证，默认保留；仅在明确选择后加入可恢复的删除计划"))
        } else if url.standardizedFileURL.path == root.url.standardizedFileURL.path {
            (kind, category, baselineRisk, reason) = (.providerRoot, .configuration, .blocked, L10n.text("Agent Provider 根目录不可整体清理"))
        } else if lowerComponents.contains("skills") || lowerComponents.contains("design_libraries") || lowerName == "skill.md" {
            (kind, category, baselineRisk, reason) = (.skill, .agentSkill, .review, L10n.text("Skill 默认保留，只有手动确认后才会加入删除计划"))
        } else if credentialNames.contains(lowerName) || lowerName.contains("credential") || lowerName.contains("token") {
            (kind, category, baselineRisk, reason) = (.credential, .credential, .blocked, L10n.text("凭证和令牌永不作为清理候选"))
        } else if protectedConfigNames.contains(lowerName) || lowerName.contains("mcp") && ["json", "yaml", "yml", "toml"].contains(url.pathExtension.lowercased()) {
            (kind, category, baselineRisk, reason) = (.mcpConfiguration, .agentMCP, .review, L10n.text("MCP 配置可能包含凭证，默认保留；仅在明确选择后加入可恢复的删除计划"))
        } else if instructionNames.contains(lowerName) || lowerName.contains("prompt") {
            (kind, category, baselineRisk, reason) = (.promptOrInstruction, .userKnowledge, .blocked, L10n.text("提示词、指令和记忆属于用户知识"))
        } else if lowerComponents.contains("worktrees") || lowerName == "worktrees" {
            (kind, category, baselineRisk, reason) = (.worktree, .agentWorktree, .blocked, L10n.text("未验证 Git 状态前禁止清理 worktree"))
        } else if lowerComponents.contains("sessions") || lowerName.contains("session") {
            (kind, category, baselineRisk, reason) = (.session, .agentSession, .review, L10n.text("会话可能包含可恢复上下文，因此默认保留"))
        } else if reproducibleCacheNames.contains(lowerName), lowerComponents.contains("sandboxes") || lowerComponents.contains("workspaces") {
            (kind, category, baselineRisk, reason) = (.reproducibleCache, .agentSandbox, isOld && hasCompletionEvidence ? .safe : .review, hasCompletionEvidence ? L10n.text("已完成沙箱内可重新生成的构建缓存") : L10n.text("任务完成状态不足，因此默认保留"))
        } else if lowerComponents.contains("models") || lowerComponents.contains("huggingface") || lowerComponents.contains("ollama") {
            (kind, category, baselineRisk, reason) = (.modelCache, .agentModelCache, .review, L10n.text("模型可以重新下载，但时间和网络成本较高"))
        } else if packageCacheNames.contains(lowerName) {
            (kind, category, baselineRisk, reason) = (.packageCache, .agentPackageCache, .review, L10n.text("可重新下载，但需确认当前工具链未使用"))
        } else if sourceExtensions.contains(url.pathExtension.lowercased()) {
            (kind, category, baselineRisk, reason) = (.unknown, .userKnowledge, .blocked, L10n.text("源代码属于用户资产，始终保护"))
        } else if lowerComponents.contains("sandboxes") || lowerComponents.contains("workspaces") {
            (kind, category, baselineRisk, reason) = (.sandbox, .agentSandbox, .review, L10n.text("沙箱可能仍关联任务，因此默认保留"))
        } else {
            (kind, category, baselineRisk, reason) = (.unknown, .agentUnknown, .review, L10n.text("未识别的 Agent 资产默认保留"))
        }

        let risk: RiskLevel
        if isActive || identity == nil || identity?.kind == .symbolicLink {
            risk = .blocked
        } else {
            risk = baselineRisk
        }

        var evidence = [
            Evidence(code: "agent-provider", summary: L10n.text("来源：{0}", String(describing: root.providerID))),
            Evidence(code: "agent-semantics", summary: reason),
        ]
        if isActive { evidence.append(Evidence(code: "active", summary: L10n.text("当前 Agent 任务正在使用"))) }
        if identity == nil { evidence.append(Evidence(code: "unverifiable", summary: L10n.text("无法验证文件身份"))) }
        return AgentClassification(kind: kind, category: category, risk: risk, evidence: evidence)
    }
}

public enum AgentProviderCoverageState: String, Codable, Hashable, Sendable {
    case notDetected
    case complete
    case limited
    case unavailable
}

public struct AgentProviderCoverage: Codable, Hashable, Sendable {
    public let provider: AgentProvider
    public let state: AgentProviderCoverageState
    public let detectedRootCount: Int
    public let scannedAssetCount: Int

    public init(
        provider: AgentProvider,
        state: AgentProviderCoverageState,
        detectedRootCount: Int,
        scannedAssetCount: Int
    ) {
        self.provider = provider
        self.state = state
        self.detectedRootCount = detectedRootCount
        self.scannedAssetCount = scannedAssetCount
    }
}

public struct AgentAssetInventory: Sendable {
    public let assets: [AgentAssetRecord]
    public let skills: [SkillCatalogEntry]
    public let mcpConfigurations: [MCPConfigurationRecord]
    public let reachedBudget: Bool
    public let providerCoverage: [AgentProvider: AgentProviderCoverage]
    public let skillDuplicatesCollapsedCount: Int
    public let coverage: CoverageSummary
    public let limitations: [ScanLimitation]
    public var isComplete: Bool {
        !reachedBudget && coverage.unavailableRoots.isEmpty && limitations.isEmpty
            && !providerCoverage.values.contains { $0.state == .limited || $0.state == .unavailable }
    }

    public init(
        assets: [AgentAssetRecord],
        skills: [SkillCatalogEntry] = [],
        mcpConfigurations: [MCPConfigurationRecord] = [],
        reachedBudget: Bool,
        providerCoverage: [AgentProvider: AgentProviderCoverage] = [:],
        skillDuplicatesCollapsedCount: Int = 0,
        coverage: CoverageSummary = CoverageSummary(),
        limitations: [ScanLimitation] = []
    ) {
        self.assets = assets
        self.skills = skills
        self.mcpConfigurations = mcpConfigurations
        self.reachedBudget = reachedBudget
        self.providerCoverage = providerCoverage
        self.skillDuplicatesCollapsedCount = skillDuplicatesCollapsedCount
        self.coverage = coverage
        self.limitations = limitations
    }
}

public struct AgentWorkspaceScanner: CleanerCore.Scanner {
    public let id = "agent.workspace"
    public let category = CleanupCategory.agentSandbox
    public let adapters: [any AgentProviderAdapter]
    public let maximumDepth: Int?
    public let maximumAssets: Int?

    public init(
        adapters: [any AgentProviderAdapter] = [
            CodexProviderAdapter(), CodexProjectProviderAdapter(),
            ClaudeProviderAdapter(), ClaudeProjectProviderAdapter(), CursorProviderAdapter(),
            TraeProviderAdapter(), GenericMCPProviderAdapter(), GitWorktreeProviderAdapter(), SharedAgentProviderAdapter(),
        ],
        maximumDepth: Int? = nil,
        maximumAssets: Int? = nil
    ) {
        self.adapters = adapters
        self.maximumDepth = maximumDepth.map { max(1, $0) }
        self.maximumAssets = maximumAssets.map { max(1, $0) }
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        try await scanAssets(context: context).map(\.candidate)
    }

    public func scanAssets(context: ScanContext) async throws -> [AgentAssetRecord] {
        try await scanAssetInventory(context: context).assets
    }

    public func scanAssetInventory(context: ScanContext) async throws -> AgentAssetInventory {
        try Task.checkCancellation()
        var assets: [AgentAssetRecord] = []
        var skillsByRootPath: [String: SkillCatalogEntry] = [:]
        var mcpConfigurationsByPath: [String: MCPConfigurationRecord] = [:]
        var skillDuplicatesCollapsedCount = 0
        var globallyOwnedPaths = Set<String>()
        var traversals: [ProviderTraversal] = []
        var scannedRoots = Set<URL>()
        var unavailableRoots = Set<URL>()
        var limitations: [ScanLimitation] = []
        for adapter in adapters {
            let roots = await adapter.discoverRoots(context: context)
            traversals.append(ProviderTraversal(adapter: adapter, roots: roots))
        }

        while maximumAssets.map({ assets.count < $0 }) ?? true {
            try Task.checkCancellation()
            var madeProgress = false
            for index in traversals.indices {
                guard maximumAssets.map({ assets.count < $0 }) ?? true else { break }
                while traversals[index].cursor < traversals[index].queue.count {
                    try Task.checkCancellation()
                    let entry = traversals[index].queue[traversals[index].cursor]
                    traversals[index].cursor += 1
                    madeProgress = true
                    let url = entry.url
                    let path = url.standardizedFileURL.path
                    guard traversals[index].seenPaths.insert(path).inserted else { continue }
                    guard globallyOwnedPaths.insert(path).inserted else { continue }
                    guard let identity = try? await context.fileSystem.identity(at: url) else {
                        globallyOwnedPaths.remove(path)
                        traversals[index].identityFailures += 1
                        unavailableRoots.insert(url)
                        limitations.append(Self.limitation(url, L10n.text("无法验证 Agent 路径身份")))
                        continue
                    }
                    scannedRoots.insert(entry.root.url)

                    var classification = await traversals[index].adapter.classify(
                        url: url,
                        root: entry.root,
                        context: context
                    )
                    do {
                        _ = try context.pathPolicy.validateCandidate(url)
                    } catch {
                        classification = AgentClassification(
                            kind: classification.kind,
                            category: classification.category,
                            risk: .blocked,
                            evidence: classification.evidence + [Evidence(code: "protected-path", summary: L10n.text("路径安全策略禁止清理"))]
                        )
                    }

                    let candidate = context.protectionPolicy.applying(to: CleanupCandidate(
                        url: url,
                        displayName: url.lastPathComponent,
                        category: classification.category,
                        bytes: identity.size,
                        risk: classification.risk,
                        evidence: classification.evidence,
                        identity: identity,
                        source: .agentWorkspace,
                        lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                        isActive: context.isActive(url)
                    ))
                    let activity = activity(for: url, identity: identity, context: context)
                    let resourceKind = resourceKind(for: classification, candidate: candidate)
                    let eligibility = eligibility(
                        for: resourceKind,
                        risk: candidate.risk,
                        activity: activity
                    )
                    assets.append(AgentAssetRecord(
                        candidate: candidate,
                        provider: entry.root.provider,
                        scope: entry.root.scope,
                        resourceKind: resourceKind,
                        activity: activity,
                        cleanupEligibility: eligibility,
                        cleanupUnitURL: url
                    ))
                    if let configuration = await MCPConfigurationCatalogSupport.makeRecord(
                        provider: entry.root.provider,
                        scope: entry.root.scope,
                        url: url,
                        homeDirectory: context.homeDirectory,
                        fileSystem: context.fileSystem
                    ) {
                        mcpConfigurationsByPath[configuration.fileURL.path] = configuration
                    }
                    if classification.kind == .skill,
                       let skillEntry = await SkillCatalogSupport.makeEntry(
                           provider: entry.root.provider,
                           scope: entry.root.scope,
                           discoveredURL: url,
                           fileSystem: context.fileSystem
                       ) {
                        let rootPath = skillEntry.skillRootURL.path
                        if let existing = skillsByRootPath[rootPath] {
                            skillsByRootPath[rootPath] = existing.merged(with: skillEntry)
                            skillDuplicatesCollapsedCount += 1
                        } else {
                            skillsByRootPath[rootPath] = skillEntry
                        }
                    }
                    traversals[index].scannedAssetCount += 1

                    if identity.kind == .directory {
                        do {
                            let children = try await context.fileSystem.children(of: url)
                            if maximumDepth.map({ entry.depth < $0 }) ?? true {
                                traversals[index].queue.append(contentsOf: children.map {
                                    ProviderTraversal.Entry(url: $0, depth: entry.depth + 1, root: entry.root)
                                })
                            } else if !children.isEmpty {
                                traversals[index].depthLimited = true
                                limitations.append(Self.limitation(url, L10n.text("达到 Agent 扫描深度")))
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            traversals[index].readFailures += 1
                            unavailableRoots.insert(url)
                            limitations.append(Self.limitation(url, L10n.text("Agent 目录无法读取")))
                        }
                    }
                    break
                }
            }
            if !madeProgress { break }
        }

        var providerCoverage = Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map { provider in
            (provider, AgentProviderCoverage(
                provider: provider,
                state: .notDetected,
                detectedRootCount: 0,
                scannedAssetCount: 0
            ))
        })
        for provider in AgentProvider.allCases {
            let matchingTraversals = traversals.filter { $0.adapter.provider == provider }
            let detectedRootCount = matchingTraversals.reduce(0) { $0 + $1.roots.count }
            let scannedAssetCount = matchingTraversals.reduce(0) { $0 + $1.scannedAssetCount }
            let hasLimitedTraversal = matchingTraversals.contains { $0.cursor < $0.queue.count || $0.depthLimited }
            let identityFailures = matchingTraversals.reduce(0) { $0 + $1.identityFailures }
            let readFailures = matchingTraversals.reduce(0) { $0 + $1.readFailures }
            let state: AgentProviderCoverageState
            if detectedRootCount == 0 {
                state = .notDetected
            } else if scannedAssetCount == 0, identityFailures > 0 {
                state = .unavailable
            } else if hasLimitedTraversal || identityFailures > 0 || readFailures > 0 {
                state = .limited
            } else {
                state = .complete
            }
            providerCoverage[provider] = AgentProviderCoverage(
                provider: provider,
                state: state,
                detectedRootCount: detectedRootCount,
                scannedAssetCount: scannedAssetCount
            )
        }
        let reachedBudget = traversals.contains { $0.cursor < $0.queue.count || $0.depthLimited }
        for traversal in traversals where traversal.cursor < traversal.queue.count {
            limitations.append(Self.limitation(traversal.queue[traversal.cursor].url, L10n.text("达到 Agent 条目预算")))
        }
        let sortedAssets = assets.sorted { $0.candidate.url.path.localizedStandardCompare($1.candidate.url.path) == .orderedAscending }
        let sortedSkills = skillsByRootPath.values.sorted {
            let lhsProvider = $0.provider.rawValue
            let rhsProvider = $1.provider.rawValue
            if lhsProvider != rhsProvider {
                return lhsProvider.localizedStandardCompare(rhsProvider) == .orderedAscending
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        let sortedMCPConfigurations = mcpConfigurationsByPath.values.sorted {
            $0.fileURL.path.localizedStandardCompare($1.fileURL.path) == .orderedAscending
        }
        return AgentAssetInventory(
            assets: sortedAssets,
            skills: sortedSkills,
            mcpConfigurations: sortedMCPConfigurations,
            reachedBudget: reachedBudget,
            providerCoverage: providerCoverage,
            skillDuplicatesCollapsedCount: skillDuplicatesCollapsedCount,
            coverage: CoverageSummary(scannedRoots: Array(scannedRoots), unavailableRoots: Array(unavailableRoots),
                                      budgetLimitedModules: reachedBudget ? [.agentEnvironment] : []),
            limitations: Array(Set(limitations)).sorted { $0.id < $1.id }
        )
    }

    private static func limitation(_ url: URL, _ title: String) -> ScanLimitation {
        ScanLimitation(title: title, path: url, impact: L10n.text("此位置或后代未完整检查，不能声明扫描完整"), recovery: L10n.text("检查权限或缩小扫描范围后重试"))
    }

    private struct ProviderTraversal {
        struct Entry {
            let url: URL
            let depth: Int
            let root: AgentRoot
        }

        let adapter: any AgentProviderAdapter
        let roots: [AgentRoot]
        var queue: [Entry]
        var cursor = 0
        var seenPaths = Set<String>()
        var scannedAssetCount = 0
        var identityFailures = 0
        var readFailures = 0
        var depthLimited = false

        init(adapter: any AgentProviderAdapter, roots: [AgentRoot]) {
            self.adapter = adapter
            self.roots = roots
            queue = roots.map { Entry(url: $0.url, depth: 0, root: $0) }
        }
    }

    private func activity(for url: URL, identity: FileIdentity, context: ScanContext) -> AgentActivity {
        if context.isActive(url) { return .active }
        let components = url.pathComponents.map { $0.lowercased() }
        let completed = components.contains { component in
            component == "completed" || component == "finished" || component == "archived"
                || component.hasPrefix("completed-") || component.hasPrefix("finished-") || component.hasPrefix("archived-")
        }
        if completed { return .completed }
        let age = context.now.timeIntervalSince1970 - Double(identity.modificationTime)
        return age < 7 * 86_400 ? .recent : .unknown
    }

    private func resourceKind(for classification: AgentClassification, candidate: CleanupCandidate) -> AgentResourceKind {
        if candidate.category == .userKnowledge,
           AgentSemanticClassifier.sourceExtensions.contains(candidate.url.pathExtension.lowercased()) {
            return .sourceCode
        }
        return switch classification.kind {
        case .providerRoot: .configuration
        case .skill: .skill
        case .mcpConfiguration: .mcpDefinition
        case .credential: .credential
        case .promptOrInstruction: .promptKnowledge
        case .session: .sessionHistory
        case .sandbox: .sandboxWorkspace
        case .reproducibleCache: .buildCache
        case .modelCache: .modelCache
        case .packageCache: .packageCache
        case .worktree: .gitWorktree
        case .unknown: .unknown
        }
    }

    private func eligibility(
        for resourceKind: AgentResourceKind,
        risk: RiskLevel,
        activity: AgentActivity
    ) -> AgentCleanupEligibility {
        if risk == .blocked || activity == .active { return .protected }
        switch resourceKind {
        case .configuration, .credential, .promptKnowledge, .sourceCode, .gitWorktree:
            return .protected
        case .skill, .mcpDefinition:
            return .retained
        case .modelCache, .packageCache:
            return .deep
        case .runtimeTemporaryOutput, .completedTaskCache, .buildCache:
            return risk == .safe && activity == .completed ? .recommended : .retained
        case .sessionHistory, .sandboxWorkspace, .unknown:
            return .retained
        }
    }
}
