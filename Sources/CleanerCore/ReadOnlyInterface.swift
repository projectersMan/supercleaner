import Foundation

public enum ReadOnlyInterfaceError: Error, LocalizedError, Sendable {
    case invalidArguments(String), cancelled, scanUnavailable, unknownPath(String)
    public var errorDescription: String? {
        switch self {
        case let .invalidArguments(message): message
        case .cancelled: "Scan cancelled"
        case .scanUnavailable: "No scan result is available"
        case let .unknownPath(path): "Path was not discovered as an eligible candidate: \(path)"
        }
    }
}

public struct ReadOnlyRequest: Sendable {
    public enum Command: String, Sendable { case scan, candidates, preview, history, projects; case projectPreview = "project-preview" }
    public let command: Command
    public let home: URL
    public let module: ScanModuleID?
    public let selectedPaths: Set<String>

    public static let usage = """
    supercleaner <scan|candidates|preview|history|projects|project-preview> [--json] [--home /absolute/path]
      --module general|applications|largeFiles|agentEnvironment  Limit a scan
      --path /absolute/candidate                              Preview selection (repeatable)
    All commands are read-only. JSON schema version: 1. No deletion command is provided.
    """

    public init(arguments: [String], defaultHome: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard let first = arguments.first, let command = Command(rawValue: first) else {
            throw ReadOnlyInterfaceError.invalidArguments(Self.usage)
        }
        var home = defaultHome
        var module: ScanModuleID?
        var selected = Set<String>()
        var index = 1
        var seenOptions = Set<String>()
        while index < arguments.count {
            let option = arguments[index]
            if option == "--json" { index += 1; continue }
            guard ["--home", "--module", "--path"].contains(option), index + 1 < arguments.count else {
                throw ReadOnlyInterfaceError.invalidArguments("Unknown or incomplete option: \(option)")
            }
            let value = arguments[index + 1]
            if option != "--path", !seenOptions.insert(option).inserted {
                throw ReadOnlyInterfaceError.invalidArguments("Duplicate option: \(option)")
            }
            if option == "--module" {
                guard let parsed = ScanModuleID(rawValue: value), ![.history, .projects, .projectPreview].contains(command) else {
                    throw ReadOnlyInterfaceError.invalidArguments("Invalid scan module: \(value)")
                }
                module = parsed
            } else {
                guard value.hasPrefix("/"), !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw ReadOnlyInterfaceError.invalidArguments("An absolute filesystem path is required")
                }
                let url = URL(fileURLWithPath: value).standardizedFileURL
                if option == "--home" { home = url }
                else {
                    guard [.preview, .projectPreview].contains(command) else { throw ReadOnlyInterfaceError.invalidArguments("--path is only supported by preview commands") }
                    selected.insert(url.resolvingSymlinksInPath().standardizedFileURL.path)
                }
            }
            index += 2
        }
        self.command = command
        self.home = home
        self.module = module
        selectedPaths = selected
    }
}

public struct ReadOnlyScanDocument: Codable, Sendable {
    public let metadata: ScanGenerationMetadata
    public let scanStatus: String
    public let modules: [ScanModuleStatus]
    public let coverage: CoverageSummary
    public let candidates: [CleanupCandidate]
    public let applications: [ApplicationUninstallAnalysis]
    public let agentSkills: [SkillCatalogEntry]
    public let mcpConfigurations: [MCPConfigurationRecord]
    public let protectionAvailable: Bool
    public var applicationOwnership: ApplicationOwnershipGraph? = nil
    public var agentProviderCoverage: [AgentProviderCoverage] = []
}

public struct ReadOnlyDocument: Codable, Sendable {
    public let schemaVersion: Int
    public let command: String
    public let generatedAt: Date
    public let scan: ReadOnlyScanDocument?
    public let plan: CleanupPlan?
    public let receipts: [OperationReceipt]?
    public let projects: ProjectScanReport?

    public init(command: String, scan: ReadOnlyScanDocument? = nil, plan: CleanupPlan? = nil, receipts: [OperationReceipt]? = nil, projects: ProjectScanReport? = nil) {
        schemaVersion = 1
        self.command = command
        generatedAt = Date()
        self.scan = scan
        self.plan = plan
        self.receipts = receipts
        self.projects = projects
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum ReadOnlyInterface {
    public static func run(_ request: ReadOnlyRequest, runtime: CleanupRuntime? = nil) async throws -> ReadOnlyDocument {
        let runtime = runtime ?? CleanupRuntime(home: request.home)
        if request.command == .history {
            let store = HistoryStore(url: request.home.appendingPathComponent("Library/Application Support/SuperCleaner/history.json"))
            let receipts = try await store.receipts().sorted { $0.completedAt > $1.completedAt }
            return ReadOnlyDocument(command: request.command.rawValue, receipts: receipts)
        }
        if [.projects, .projectPreview].contains(request.command) {
            let configuration = try await runtime.configuration(includeProjectActivity: true)
            let roots = try await runtime.projectRoots.roots()
            let report = try await ProjectArtifactScanner(roots: roots).scan(context: configuration.context)
            var plan: CleanupPlan?
            if request.command == .projectPreview {
                let available = Dictionary(report.artifacts.map { ($0.candidate.url.resolvingSymlinksInPath().path, $0.candidate) }, uniquingKeysWith: { first, _ in first })
                for path in request.selectedPaths where available[path] == nil { throw ReadOnlyInterfaceError.unknownPath(path) }
                let selected = request.selectedPaths.sorted().compactMap { available[$0] }
                plan = try PlanBuilder(ruleVersion: configuration.pack.executionVersion, protectionPolicy: configuration.context.protectionPolicy)
                    .build(candidates: selected, selectedIDs: Set(selected.map(\.id)))
            }
            return ReadOnlyDocument(command: request.command.rawValue, plan: plan, projects: report)
        }
        let configuration = try await runtime.configuration()
        let context = configuration.context
        let pack = configuration.pack
        let report: ReadOnlyScanDocument
        if request.module == .general {
            let engine = CleanupRuleEngine(pack: pack)
            let result = await ScanCoordinator().scan(using: engine.scanners + [InstallerScanner(), IncompleteDownloadScanner()], context: context)
            guard !Task.isCancelled else { throw ReadOnlyInterfaceError.cancelled }
            report = ReadOnlyScanDocument(
                metadata: ScanGenerationMetadata(startedAt: result.startedAt, completedAt: result.completedAt, rulesetVersion: pack.executionVersion),
                scanStatus: result.failures.isEmpty ? "complete" : "partial",
                modules: [ScanModuleStatus(module: .general, state: result.failures.isEmpty ? .completed : .limited,
                                          startedAt: result.startedAt, completedAt: result.completedAt,
                                          limitations: result.failures.map { ScanLimitation(title: $0.scannerID, impact: $0.message, recovery: "Fix access or scan limits and retry") })],
                coverage: CoverageSummary(), candidates: engine.consolidate(result.candidates, home: request.home),
                applications: [], agentSkills: [], mcpConfigurations: [], protectionAvailable: context.protectionPolicy.isAvailable
            )
        } else if let module = request.module {
            report = try await scanModule(module, context: context, pack: pack)
        } else {
            guard let full = await SystemScanCoordinator(rulePack: pack).scan(context: context) else {
                throw Task.isCancelled ? ReadOnlyInterfaceError.cancelled : ReadOnlyInterfaceError.scanUnavailable
            }
            let modules = full.modules.values.filter { request.module == nil || $0.module == request.module }.sorted { $0.module.rawValue < $1.module.rawValue }
            let candidates: [CleanupCandidate]
            switch request.module {
            case .applications: candidates = full.applicationUninstallInventory.plans.flatMap { $0.items.map(\.candidate) }
            case .largeFiles: candidates = full.largeFileCandidates
            case .agentEnvironment: candidates = full.agentAssets.map(\.candidate)
            default: candidates = full.candidates + full.applicationUninstallInventory.plans.flatMap { $0.items.map(\.candidate) }
            }
            report = ReadOnlyScanDocument(
                metadata: full.metadata,
                scanStatus: modules.allSatisfy { $0.state == .completed } ? "complete" : "partial",
                modules: modules, coverage: full.coverage, candidates: candidates,
                applications: request.module == nil || request.module == .applications ? full.applicationUninstallInventory.analyses : [],
                agentSkills: request.module == nil || request.module == .agentEnvironment ? full.agentSkills : [],
                mcpConfigurations: request.module == nil || request.module == .agentEnvironment ? full.agentMCPConfigurations : [],
                protectionAvailable: context.protectionPolicy.isAvailable,
                applicationOwnership: full.applicationUninstallInventory.ownershipGraph,
                agentProviderCoverage: full.agentProviderCoverage.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
            )
        }
        var plan: CleanupPlan?
        if request.command == .preview {
            let available = Dictionary(report.candidates.map { ($0.url.resolvingSymlinksInPath().standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
            for path in request.selectedPaths where available[path] == nil { throw ReadOnlyInterfaceError.unknownPath(path) }
            let selected = request.selectedPaths.isEmpty
                ? report.candidates.filter { $0.source == .general && $0.risk == .safe && $0.defaultSelection == true }
                : request.selectedPaths.compactMap { available[$0] }
            plan = try PlanBuilder(ruleVersion: pack.executionVersion, protectionPolicy: context.protectionPolicy)
                .build(candidates: selected, selectedIDs: Set(selected.map(\.id)))
        }
        return ReadOnlyDocument(command: request.command.rawValue, scan: report, plan: plan)
    }

    private static func scanModule(_ module: ScanModuleID, context: ScanContext, pack: RulePack) async throws -> ReadOnlyScanDocument {
        let started = Date()
        var candidates: [CleanupCandidate] = []
        var applications: [ApplicationUninstallAnalysis] = []
        var skills: [SkillCatalogEntry] = []
        var mcp: [MCPConfigurationRecord] = []
        var coverage = CoverageSummary()
        var limitations: [ScanLimitation] = []
        var limited = false
        var ownership: ApplicationOwnershipGraph?
        var providers: [AgentProviderCoverage] = []
        switch module {
        case .applications:
            let inventory = await ApplicationScanner().installedApplications(context: context, maximumDepth: 12, maximumEntries: 30_000)
            let analyzed = await ApplicationUninstallAnalyzer().analyze(inventory: inventory, context: context)
            applications = analyzed.analyses
            candidates = analyzed.plans.flatMap { $0.items.map(\.candidate) }
            coverage = CoverageSummary(scannedRoots: Array(Set(inventory.coverage.scannedRoots + analyzed.associationCoverage.scannedRoots)),
                unavailableRoots: Array(Set(inventory.coverage.unavailableRoots + analyzed.associationCoverage.unavailableRoots)),
                budgetLimitedModules: inventory.coverage.budgetLimitedModules.union(analyzed.associationCoverage.budgetLimitedModules))
            limited = analyzed.moduleCoverage.isLimited
            limitations = analyzed.moduleCoverage.limitations
            ownership = analyzed.ownershipGraph
        case .largeFiles:
            let tree: DiskUsageTree
            if let indexed = try? await IndexedLargeFileScanner().scan(context: context) { tree = indexed }
            else { tree = try await DiskUsageScanner(maximumDepth: 8, maximumEntries: 50_000).scan(context: context) }
            candidates = try await LargeFileScanner().candidates(from: tree, context: context)
            coverage = tree.coverage
            limited = !coverage.unavailableRoots.isEmpty || !coverage.budgetLimitedModules.isEmpty
        case .agentEnvironment:
            let inventory = try await AgentWorkspaceScanner(maximumDepth: 8, maximumAssets: 20_000).scanAssetInventory(context: context)
            candidates = inventory.assets.map(\.candidate)
            skills = inventory.skills
            mcp = inventory.mcpConfigurations
            limited = !inventory.isComplete
            coverage = inventory.coverage
            limitations = inventory.limitations
            providers = inventory.providerCoverage.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
        case .general: throw ReadOnlyInterfaceError.invalidArguments("General scan is handled by the rule engine")
        }
        guard !Task.isCancelled else { throw ReadOnlyInterfaceError.cancelled }
        let completed = Date()
        return ReadOnlyScanDocument(
            metadata: ScanGenerationMetadata(startedAt: started, completedAt: completed, rulesetVersion: pack.executionVersion),
            scanStatus: limited ? "partial" : "complete",
            modules: [ScanModuleStatus(module: module, state: limited ? .limited : .completed, startedAt: started, completedAt: completed, limitations: limitations)],
            coverage: coverage, candidates: candidates, applications: applications, agentSkills: skills,
            mcpConfigurations: mcp, protectionAvailable: context.protectionPolicy.isAvailable, applicationOwnership: ownership,
            agentProviderCoverage: providers
        )
    }
}
