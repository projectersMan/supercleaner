import XCTest
@testable import CleanerCore

final class AgentScanAccelerationTests: XCTestCase {
    func testProjectMCPInsideGlobalProviderHasSameResolvedScopeInBothPhases() async throws {
        let home = fixture("agent-project-mcp-scope")
        defer { try? FileManager.default.removeItem(at: home) }
        let configuration = home.appendingPathComponent(".codex/worktrees/project/.codex/config.toml")
        try FileManager.default.createDirectory(at: configuration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[mcp_servers.search]\ncommand = \"search\"\n".utf8).write(to: configuration)
        let plugin = home.appendingPathComponent(".claude/plugins/marketplaces/official/external_plugins/asana/.mcp.json")
        try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"tasks":{"command":"tasks"}}}"#.utf8).write(to: plugin)
        let recorder = CapabilityCollector()
        let full = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter(), ClaudeProviderAdapter()]).scanAssetInventory(
            context: .init(homeDirectory: home)) { await recorder.set($0) }
        let early = await recorder.catalog
        XCTAssertEqual(full.mcpConfigurations.first?.scope, .project)
        XCTAssertEqual(full.mcpConfigurations.count, 2)
        XCTAssertTrue(full.mcpConfigurations.allSatisfy { $0.scope == .project })
        XCTAssertEqual(early?.mcpConfigurations, full.mcpConfigurations)
    }
    func testCapabilityPhasePreservesLegacyFileStyleSkillEntries() async throws {
        let home = fixture("agent-file-skill")
        defer { try? FileManager.default.removeItem(at: home) }
        let container = home.appendingPathComponent(".codex/skills")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let file = container.appendingPathComponent("README.md")
        try Data("Legacy file-style catalog entry".utf8).write(to: file)
        let recorder = CapabilityCollector()
        let full = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()]).scanAssetInventory(
            context: .init(homeDirectory: home)) { await recorder.set($0) }
        let early = await recorder.catalog
        XCTAssertEqual(full.skills.map(\.id), [file.path])
        XCTAssertEqual(early?.skills.map(\.id), full.skills.map(\.id))
        XCTAssertEqual(early?.skills.first?.functionalSections, full.skills.first?.functionalSections)
    }
    func testNestedManifestsMergeIntoCanonicalSkillInBothPhases() async throws {
        let home = fixture("agent-nested-manifests")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".codex/plugins/skills/collection")
        for (name, text) in [("one", "Search source files."), ("two", "Create document reports.")] {
            let child = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data(("# " + name + "\n" + text).utf8).write(to: child.appendingPathComponent("SKILL.md"))
        }
        let recorder = CapabilityCollector()
        let full = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()]).scanAssetInventory(
            context: .init(homeDirectory: home)) { await recorder.set($0) }
        let early = await recorder.catalog
        XCTAssertEqual(full.skills.count, 1)
        let actual = try XCTUnwrap(full.skills.first)
        XCTAssertEqual(actual.id, root.path)
        XCTAssertTrue(actual.functionalSections.contains { $0.contains("Search source files") })
        XCTAssertTrue(actual.functionalSections.contains { $0.contains("Create document reports") })
        XCTAssertEqual(early?.skills.first?.functionalSections, actual.functionalSections, "Stable manifest order must keep the exact analysis input equal")
    }
    func testCapabilitySubtreesReuseParsingAndInvalidateDeepFileChanges() async throws {
        let home = fixture("agent-subtree")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex")
        let skill = directory.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        let manifest = skill.appendingPathComponent("SKILL.md")
        try Data("# Demo\nSearch source files.".utf8).write(to: manifest)
        let runtime = directory.appendingPathComponent("runtime.bin")
        try Data([1]).write(to: runtime)
        let fs = MeasuredAgentFileSystem()
        let snapshot = AgentDirectorySnapshot()
        let scanner = AgentWorkspaceScanner(directorySnapshot: snapshot)
        let roots = [AgentRoot(provider: .codex, scope: .global, url: directory)]
        let context = ScanContext(homeDirectory: home, fileSystem: fs)
        let first = try await scanner.scanCapabilityInventory(roots: roots, context: context)
        let reads = await fs.textReads
        let runtimeReads = await fs.identityReads[runtime.path]
        let repeatResult = try await scanner.scanCapabilityInventory(roots: roots, context: context)
        let repeatReads = await fs.textReads
        let repeatedRuntime = await fs.identityReads[runtime.path]
        XCTAssertEqual(first.skills.map(\.functionalSections), repeatResult.skills.map(\.functionalSections))
        XCTAssertEqual(reads, repeatReads, "Unchanged subtrees do not reread or reparse manifests")
        XCTAssertEqual(runtimeReads, repeatedRuntime, "Unchanged directory membership avoids revisiting runtime files")
        let parentStamp = try await fs.directoryGeneration(at: skill)
        try Data("# Demo\nCreate source files.".utf8).write(to: manifest)
        let parentAfter = try await fs.directoryGeneration(at: skill)
        XCTAssertEqual(parentStamp, parentAfter, "File writes do not update the parent directory")
        let modified = try await scanner.scanCapabilityInventory(roots: roots, context: context)
        XCTAssertNotEqual(first.skills.first?.functionalSections, modified.skills.first?.functionalSections)
        let added = directory.appendingPathComponent("skills/added")
        try FileManager.default.createDirectory(at: added, withIntermediateDirectories: true)
        try Data("# Added\nRead task status.".utf8).write(to: added.appendingPathComponent("SKILL.md"))
        let addition = try await scanner.scanCapabilityInventory(roots: roots, context: context)
        XCTAssertEqual(addition.skills.count, 2)
        try FileManager.default.removeItem(at: added)
        try FileManager.default.moveItem(at: skill, to: directory.appendingPathComponent("real-demo"))
        try FileManager.default.createSymbolicLink(at: skill, withDestinationURL: directory.appendingPathComponent("real-demo"))
        let linked = try await scanner.scanCapabilityInventory(roots: roots, context: context)
        XCTAssertFalse(linked.skills.contains { $0.id == skill.path }, "A cached real subtree cannot survive replacement by a link")
        let hits = await snapshot.catalogHits
        XCTAssertGreaterThan(hits, 0)
    }
    func testCompiledRuleResolverPreservesSpecificityAndScope() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let resolver = AgentResourcePathRegistry.Resolver(homeDirectory: home)
        func original(_ url: URL) -> AgentResourcePathRule? {
            let path = url.standardizedFileURL.path
            return AgentResourcePathRegistry.rules.compactMap { rule -> (AgentResourcePathRule, Int, Bool)? in
                if rule.base == .project {
                    let exact = path.hasSuffix("/" + rule.path)
                    return exact || path.contains("/" + rule.path + "/") ? (rule, rule.path.count, exact) : nil
                }
                let target = rule.base == .home ? home.appendingPathComponent(rule.path) : URL(fileURLWithPath: rule.path)
                let root = target.standardizedFileURL.path
                return path == root || path.hasPrefix(root + "/") ? (rule, root.count, path == root) : nil
            }.sorted { $0.2 != $1.2 ? $0.2 && !$1.2 : $0.1 > $1.1 }.first?.0
        }
        for rule in AgentResourcePathRegistry.rules {
            let root: URL
            switch rule.base {
            case .home: root = home.appendingPathComponent(rule.path)
            case .absolute: root = URL(fileURLWithPath: rule.path)
            case .project: root = home.appendingPathComponent("code/demo/" + rule.path)
            }
            for url in [root, root.appendingPathComponent("demo/SKILL.md"), URL(fileURLWithPath: root.path + "-other")] {
                XCTAssertEqual(resolver.matchingRule(for: url), original(url), url.path)
            }
        }
    }
    func testProjectProvidersShareDirectoryDiscovery() async throws {
        let root = fixture("agent-projects")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("code/example")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".agents/skills"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent(".mcp.json"))
        let fs = MeasuredAgentFileSystem()
        _ = try await AgentWorkspaceScanner(adapters: [CodexProjectProviderAdapter(), ClaudeProjectProviderAdapter()])
            .scanAssetInventory(context: .init(homeDirectory: root, fileSystem: fs))
        let reads = await fs.directoryReadsByPath[project.path]
        XCTAssertEqual(reads, 1, "One project walk matches both providers")
    }

    func testCancellationStopsLiveConcurrentScan() async throws {
        let root = fixture("agent-cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<64 {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex/data-\(i)/nested"), withIntermediateDirectories: true)
        }
        let fs = MeasuredAgentFileSystem()
        let task = Task {
            try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()], maximumConcurrentReads: 4)
                .scanAssetInventory(context: .init(homeDirectory: root, fileSystem: fs))
        }
        while await fs.directoryReads < 2 { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled scan cannot publish a completed inventory") }
        catch is CancellationError { }
        let active = await fs.activeReads
        XCTAssertEqual(active, 0, "Structured child tasks must finish before cancellation returns")
    }
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("." + name + "-" + UUID().uuidString)
    }
    func testDirectorySnapshotsInvalidateDeepMutationsAndPermissionChanges() async throws {
        let root = fixture("agent-snapshot")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fs = MeasuredAgentFileSystem()
        let snapshot = AgentDirectorySnapshot()
        _ = try await snapshot.children(of: root, fileSystem: fs)
        _ = try await snapshot.children(of: nested, fileSystem: fs)
        _ = try await snapshot.children(of: root, fileSystem: fs)
        let initialReads = await fs.directoryReads
        XCTAssertEqual(initialReads, 2)
        let leaf = nested.appendingPathComponent("new")
        try Data([1]).write(to: leaf)
        let added = try await snapshot.children(of: nested, fileSystem: fs)
        XCTAssertEqual(added.map(\.lastPathComponent), ["new"])
        try FileManager.default.removeItem(at: leaf)
        let removed = try await snapshot.children(of: nested, fileSystem: fs)
        XCTAssertTrue(removed.isEmpty)
        let before = try await fs.directoryGeneration(at: nested)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nested.path)
        let after = try await fs.directoryGeneration(at: nested)
        XCTAssertNotEqual(before, after)
        let hits = await snapshot.hits
        XCTAssertEqual(hits, 1)
    }

    func testBoundedReadsReuseIdentityAndPreserveInventory() async throws {
        let root = fixture("agent-concurrency")
        defer { try? FileManager.default.removeItem(at: root) }
        let providerRoot = root.appendingPathComponent(".codex")
        for i in 0..<24 {
            let directory = providerRoot.appendingPathComponent("data-\(i)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("leaf.bin"))
        }
        let fs = MeasuredAgentFileSystem()
        let scanner = AgentWorkspaceScanner(adapters: [CodexProviderAdapter()], maximumConcurrentReads: 4, directorySnapshot: .init())
        let result = try await scanner.scanAssetInventory(context: .init(homeDirectory: root, fileSystem: fs))
        let peak = await fs.peakReads
        XCTAssertGreaterThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertEqual(result.assets.count, 49)
        let leafReads = await fs.identityReads[providerRoot.appendingPathComponent("data-0/leaf.bin").path]
        XCTAssertEqual(leafReads, 1, "Classification must reuse the traversal identity")
        let serial = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()], maximumConcurrentReads: 1,
            directorySnapshot: .init()).scanAssetInventory(context: .init(homeDirectory: root))
        XCTAssertEqual(result.assets.map { $0.candidate.url.path }, serial.assets.map { $0.candidate.url.path })
        XCTAssertEqual(result.assets.map(\.resourceKind), serial.assets.map(\.resourceKind))
        XCTAssertEqual(result.assets.map { $0.candidate.risk }, serial.assets.map { $0.candidate.risk })
    }

    func testCapabilityPhasePrecedesAndMatchesFullCatalog() async throws {
        let root = fixture("agent-phases")
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = root.appendingPathComponent(".codex/plugins/example/skills/demo")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: Demo\ndescription: Search source files\n---\n# Features\nFind source code and report results.".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        let mcp = root.appendingPathComponent(".codex/config.toml")
        try Data("[mcp_servers.search]\ncommand = \"search\"\n".utf8).write(to: mcp)
        let collector = CapabilityCollector()
        let inventory = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()]).scanAssetInventory(
            context: .init(homeDirectory: root)) { catalog in await collector.set(catalog) }
        let catalog = await collector.catalog
        XCTAssertTrue(catalog?.capabilitiesOnly == true)
        XCTAssertFalse(catalog?.isComplete == true, "A capability snapshot cannot claim the complete cleanup inventory is ready")
        XCTAssertTrue(catalog?.assets.isEmpty == true)
        XCTAssertEqual(catalog?.skills.map(\.id), inventory.skills.map(\.id))
        XCTAssertEqual(catalog?.skills.first?.functionalSections, inventory.skills.first?.functionalSections)
        XCTAssertEqual(catalog?.mcpConfigurations.map(\.id), inventory.mcpConfigurations.map(\.id))
        XCTAssertFalse(inventory.capabilitiesOnly)
        XCTAssertFalse(inventory.assets.isEmpty)
    }
}

private actor CapabilityCollector {
    var catalog: AgentAssetInventory?
    func set(_ value: AgentAssetInventory) { catalog = value }
}

private actor MeasuredAgentFileSystem: FileSystemAccess {
    let base = LocalFileSystem()
    var directoryReads = 0
    var directoryReadsByPath = [String: Int]()
    var activeReads = 0
    var peakReads = 0
    var identityReads = [String: Int]()
    var textReads = 0
    func identity(at url: URL) async throws -> FileIdentity {
        identityReads[url.path, default: 0] += 1
        return try await base.identity(at: url)
    }
    func children(of url: URL) async throws -> [URL] {
        directoryReads += 1; activeReads += 1; peakReads = max(peakReads, activeReads)
        directoryReadsByPath[url.path, default: 0] += 1
        defer { activeReads -= 1 }
        try await Task.sleep(for: .milliseconds(1))
        return try await base.children(of: url)
    }
    func directoryGeneration(at url: URL) async throws -> String? { try await base.directoryGeneration(at: url) }
    func itemGeneration(at url: URL) async throws -> String? { try await base.itemGeneration(at: url) }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func isReadable(_ url: URL) async -> Bool { await base.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func readText(at url: URL, maximumBytes: Int) async throws -> String { textReads += 1; return try await base.readText(at: url, maximumBytes: maximumBytes) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
