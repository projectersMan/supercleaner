import Foundation
import XCTest
@testable import CleanerCore

final class AgentSymlinkExclusionTests: XCTestCase {
    private var fixture: AgentSymlinkFixture!

    override func setUpWithError() throws { fixture = try AgentSymlinkFixture() }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: fixture.root) }

    func testCatalogEntriesRejectLinksAndLinkedParents() async throws {
        let fileSystem = LocalFileSystem()
        let skillPaths = [".codex/skills/alias", ".codex/skills/dangling", ".agents/skills/manifest-link", ".agents/skills/broken-manifest", ".cursor/skills/hidden"]
        for path in skillPaths {
            let entry = await SkillCatalogSupport.makeEntry(provider: .codex, scope: .global, discoveredURL: fixture.home.appendingPathComponent(path), fileSystem: fileSystem)
            XCTAssertNil(entry, path)
        }
        for path in [".codex/mcp.json", ".claude/.mcp.json", ".cursor/mcp.json"] {
            let record = await MCPConfigurationCatalogSupport.makeRecord(provider: .codex, scope: .global, url: fixture.home.appendingPathComponent(path), homeDirectory: fixture.home, fileSystem: fileSystem)
            XCTAssertNil(record, path)
        }
    }

    func testInventoryKeepsRealTargetsWithoutFollowingAliases() async throws {
        let scanner = AgentWorkspaceScanner(adapters: [CodexProviderAdapter(), ClaudeProviderAdapter(), CursorProviderAdapter(), SharedAgentProviderAdapter()])
        let inventory = try await scanner.scanAssetInventory(context: ScanContext(homeDirectory: fixture.home, fileSystem: LocalFileSystem()))
        XCTAssertEqual(Set(inventory.skills.map { $0.skillRootURL.path }), [fixture.home.appendingPathComponent(".agents/skills/real").path])
        XCTAssertEqual(Set(inventory.mcpConfigurations.map { $0.fileURL.path }), [fixture.home.appendingPathComponent(".agents/mcp.json").path])
        XCTAssertFalse(inventory.assets.contains { $0.candidate.identity.kind == .symbolicLink })
        XCTAssertFalse(inventory.assets.contains { $0.candidate.url.path.hasPrefix(fixture.home.appendingPathComponent(".cursor").path + "/") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent(".codex/skills/alias/SKILL.md").path))
    }

    func testExcludedCachedLinkCannotReceiveNewPairsOrProvideCoverage() async throws {
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: SymlinkFixtureEmbedding(), modelVersion: "symlink-fixture", policy: policy)
        let real = AgentOverlapInput(id: "skill|real", kind: .skill, title: "Real", description: "", features: ["Search source files and inspect repository code."])
        let oldLink = AgentOverlapInput(id: "skill|old-link", kind: .skill, title: "Old link", description: "", features: real.features)
        let newReal = AgentOverlapInput(id: "skill|new-real", kind: .skill, title: "New real", description: "", features: ["Create spreadsheet workbooks with formulas and charts."])
        let seeded = try await analyzer.analyze(inputs: [real, oldLink], index: AgentOverlapIndex())
        let result = try await analyzer.analyze(inputs: [real, newReal], index: seeded.index)
        let active: Set<String> = [real.id, newReal.id]
        XCTAssertEqual(result.calculatedPairCount, 1)
        XCTAssertFalse(result.index.matches.values.contains { Set([$0.firstID, $0.secondID]) == [oldLink.id, newReal.id] })
        XCTAssertTrue(result.matches.allSatisfy { $0.targets.isEmpty && $0.coverage == 0 })
        let selected = AgentOverlapAnalyzer.preselectedSourceIDs(index: result.index, activeIDs: active, eligibleIDs: active, cacheIDs: [], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85)
        XCTAssertTrue(selected.isEmpty)
        XCTAssertNotNil(result.index.entries[oldLink.id], "Historical cache can remain inactive without forcing recalculation")
    }

    func testReturningRealObjectReceivesMissingRelationshipFromCachedVectors() async throws {
        let policy = try AgentOverlapPolicy.load()
        let analyzer = AgentOverlapAnalyzer(provider: SymlinkFixtureEmbedding(), modelVersion: "symlink-fixture", policy: policy)
        let first = AgentOverlapInput(id: "skill|first", kind: .skill, title: "First", description: "", features: ["Search source files and inspect repository code."])
        let second = AgentOverlapInput(id: "skill|second", kind: .skill, title: "Second", description: "", features: first.features)
        let initial = try await analyzer.analyze(inputs: [first], index: AgentOverlapIndex())
        let next = try await analyzer.analyze(inputs: [second], index: initial.index)
        XCTAssertEqual(next.calculatedPairCount, 0, "Inactive objects must not participate")
        XCTAssertFalse(AgentOverlapAnalyzer.hasCompleteRelationships(in: next.index, activeIDs: [first.id, second.id]))
        let returned = try await analyzer.analyze(inputs: [first, second], index: next.index)
        XCTAssertTrue(returned.addedIDs.isEmpty, "Reuse known vectors without embedding again")
        XCTAssertEqual(returned.calculatedPairCount, 1)
        XCTAssertTrue(returned.matches.allSatisfy { $0.coverage == 1 && $0.targets.count == 1 })
        XCTAssertTrue(AgentOverlapAnalyzer.hasCompleteRelationships(in: returned.index, activeIDs: [first.id, second.id]))
    }
}

private struct SymlinkFixtureEmbedding: AgentEmbeddingProvider {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { $0.contains("spreadsheet") ? [0, 1] : [1, 0] }
    }
}

private struct AgentSymlinkFixture {
    let root: URL
    let home: URL

    init() throws {
        let manager = FileManager.default
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("agent-symlink-exclusion/fixtures/" + UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        let external = root.appendingPathComponent("external", isDirectory: true)
        for directory in [".codex/skills", ".claude", ".agents/skills/real/references", ".agents/skills/manifest-link", ".agents/skills/broken-manifest"] {
            try manager.createDirectory(at: home.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try manager.createDirectory(at: external.appendingPathComponent("skills/hidden"), withIntermediateDirectories: true)
        let manifest = home.appendingPathComponent(".agents/skills/real/SKILL.md")
        try "---\nname: physical-skill\ndescription: Search source files and inspect repository code.\n---\n".write(to: manifest, atomically: true, encoding: .utf8)
        try "# Hidden alias target\n".write(to: external.appendingPathComponent("skills/hidden/SKILL.md"), atomically: true, encoding: .utf8)
        let mcp = home.appendingPathComponent(".agents/mcp.json")
        try "{\"mcpServers\":{\"project-search\":{\"type\":\"stdio\"}}}".write(to: mcp, atomically: true, encoding: .utf8)
        try "{}".write(to: external.appendingPathComponent("mcp.json"), atomically: true, encoding: .utf8)
        let links = [
            (home.appendingPathComponent(".codex/skills/alias"), home.appendingPathComponent(".agents/skills/real")),
            (home.appendingPathComponent(".codex/skills/dangling"), root.appendingPathComponent("missing")),
            (home.appendingPathComponent(".agents/skills/manifest-link/SKILL.md"), manifest),
            (home.appendingPathComponent(".agents/skills/broken-manifest/SKILL.md"), root.appendingPathComponent("missing.md")),
            (home.appendingPathComponent(".agents/skills/real/references/latest.md"), manifest),
            (home.appendingPathComponent(".codex/mcp.json"), mcp),
            (home.appendingPathComponent(".claude/.mcp.json"), root.appendingPathComponent("missing.json")),
            (home.appendingPathComponent(".cursor"), external),
        ]
        for (link, target) in links { try manager.createSymbolicLink(at: link, withDestinationURL: target) }
    }
}
