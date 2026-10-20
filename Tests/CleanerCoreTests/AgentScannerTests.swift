import Foundation
import XCTest
@testable import CleanerCore

final class AgentScannerTests: XCTestCase {
    func testCustomSkillsPromptsAndMCPConfigAreBlocked() async throws {
        let fixture = AgentScanFixture()
        let results = try await fixture.scanner.scan(context: fixture.context)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == "SKILL.md" }?.risk, .blocked)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == "mcp.json" }?.risk, .blocked)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == "AGENTS.md" }?.risk, .blocked)
    }

    func testFinishedSandboxCacheCanBeSafeButSessionIsReview() async throws {
        let fixture = AgentScanFixture()
        let results = try await fixture.scanner.scan(context: fixture.context)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == ".build" }?.risk, .safe)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == "old-session.jsonl" }?.risk, .review)
    }

    func testProviderRootAndModelCacheAreNotSafe() async throws {
        let fixture = AgentScanFixture()
        let results = try await fixture.scanner.scan(context: fixture.context)
        XCTAssertEqual(results.first { $0.url.lastPathComponent == ".codex" }?.risk, .blocked)
        XCTAssertNotEqual(results.first { $0.url.lastPathComponent == "models" }?.risk, .safe)
    }

    func testSkillCatalogParsesManifestAndCollapsesDuplicateDiscovery() async throws {
        let fixture = AgentScanFixture()
        let inventory = try await fixture.scanner.scanAssetInventory(context: fixture.context)

        XCTAssertEqual(inventory.skills.count, 1)
        XCTAssertEqual(inventory.skillDuplicatesCollapsedCount, 1)
        XCTAssertEqual(inventory.skills.first?.displayName, "bits-code-guard")
        XCTAssertEqual(inventory.skills.first?.summary, "代码审查与 HTML 报告输出")
        XCTAssertEqual(inventory.skills.first?.parseStatus, .manifestParsed)
        XCTAssertEqual(inventory.skills.first?.tags, ["代码审查", "HTML 报告"])
        XCTAssertEqual(inventory.skills.first?.triggers, ["/bits-code-guard", "review code"])
    }

    func testSkillCatalogQueryMatchesNameSummaryAndPath() async throws {
        let fixture = AgentScanFixture()
        let inventory = try await fixture.scanner.scanAssetInventory(context: fixture.context)
        let skill = try XCTUnwrap(inventory.skills.first)

        XCTAssertTrue(skill.matches(query: "bits-code-guard"))
        XCTAssertTrue(skill.matches(query: "HTML 报告"))
        XCTAssertTrue(skill.matches(query: "custom"))
        XCTAssertFalse(skill.matches(query: "not-existing-skill"))
    }

    func testOverlappingProviderRootsProduceOneGloballyOwnedAsset() async throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let root = home.appendingPathComponent(".shared-agent", isDirectory: true)
        let context = ScanContext(
            homeDirectory: home,
            fileSystem: OverlappingAgentFileSystem(root: root),
            now: Date(timeIntervalSince1970: 20_000_000)
        )
        let scanner = AgentWorkspaceScanner(adapters: [
            OverlappingProviderAdapter(provider: .codex, root: root),
            OverlappingProviderAdapter(provider: .claude, root: root),
        ])

        let inventory = try await scanner.scanAssetInventory(context: context)

        XCTAssertEqual(inventory.assets.count, 2)
        XCTAssertEqual(Set(inventory.assets.map { $0.candidate.url.standardizedFileURL.path }).count, 2)
        XCTAssertTrue(inventory.assets.allSatisfy { $0.provider == .codex })
        XCTAssertEqual(inventory.providerCoverage[.codex]?.scannedAssetCount, 2)
        XCTAssertEqual(inventory.providerCoverage[.claude]?.scannedAssetCount, 0)
    }

    func testDefaultScannerTraversesPastLegacyAssetAndDepthLimits() async throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let root = home.appendingPathComponent(".unlimited-agent", isDirectory: true)
        let fileSystem = UnlimitedAgentFileSystem(root: root, wideChildCount: 5_001, deepChildCount: 10)
        let context = ScanContext(homeDirectory: home, fileSystem: fileSystem)
        let scanner = AgentWorkspaceScanner(adapters: [
            OverlappingProviderAdapter(provider: .codex, root: root),
        ])

        let inventory = try await scanner.scanAssetInventory(context: context)

        XCTAssertEqual(inventory.assets.count, 5_012)
        XCTAssertTrue(inventory.assets.contains { $0.candidate.displayName == "depth-10" })
        XCTAssertFalse(inventory.reachedBudget)
        XCTAssertEqual(inventory.providerCoverage[.codex]?.state, .complete)
    }

    func testDefaultScannerHonorsCancellationEvenWhenNoRootsAreDetected() async throws {
        let context = ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
            fileSystem: OverlappingAgentFileSystem(
                root: URL(fileURLWithPath: "/Users/tester/.missing-agent", isDirectory: true)
            )
        )
        let task = Task {
            try await AgentWorkspaceScanner(adapters: []).scanAssetInventory(context: context)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled uncapped scan must not report successful completion")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private struct OverlappingProviderAdapter: AgentProviderAdapter {
    let provider: AgentProvider
    let scope = AgentScope.global
    let rootRelativePaths: [String] = []
    let root: URL

    func discoverRoots(context: ScanContext) async -> [AgentRoot] {
        [AgentRoot(provider: provider, scope: scope, url: root)]
    }
}

private actor OverlappingAgentFileSystem: FileSystemAccess {
    private let root: URL
    private let child: URL

    init(root: URL) {
        self.root = root
        child = root.appendingPathComponent("cache", isDirectory: true)
    }

    func identity(at url: URL) throws -> FileIdentity {
        FileIdentity(
            device: 1,
            inode: url == root ? 1 : 2,
            size: url == root ? 10 : 20,
            modificationTime: 1,
            kind: .directory
        )
    }

    func children(of url: URL) -> [URL] { url == root ? [child] : [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { url == root || url == child }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor UnlimitedAgentFileSystem: FileSystemAccess {
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

private struct AgentScanFixture {
    let scanner = AgentWorkspaceScanner(adapters: [CodexProviderAdapter()])
    let context: ScanContext

    init() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let now = Date(timeIntervalSince1970: 20_000_000)
        context = ScanContext(
            homeDirectory: home,
            fileSystem: AgentFixtureFileSystem(home: home, now: now),
            now: now
        )
    }
}

private actor AgentFixtureFileSystem: FileSystemAccess {
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
        let urls = [root, skills, skill, skill.appendingPathComponent("SKILL.md"), root.appendingPathComponent("mcp.json"), root.appendingPathComponent("AGENTS.md"), sessions, sessions.appendingPathComponent("old-session.jsonl"), sandboxes, finished, build, models]
        childrenByPath = [
            root.path: [skills, root.appendingPathComponent("mcp.json"), root.appendingPathComponent("AGENTS.md"), sessions, sandboxes, models],
            skills.path: [skill],
            skill.path: [skill.appendingPathComponent("SKILL.md")],
            sessions.path: [sessions.appendingPathComponent("old-session.jsonl")],
            sandboxes.path: [finished],
            finished.path: [build],
        ]
        identities = Dictionary(uniqueKeysWithValues: urls.map { url in
            let isDirectory = childrenByPath[url.path] != nil || [root, skills, skill, sessions, sandboxes, finished, build, models].contains(url)
            return (url.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64(url.path.hashValue)), size: 100, modificationTime: Int64(now.addingTimeInterval(-45 * 86_400).timeIntervalSince1970), kind: isDirectory ? .directory : .file))
        })
        textByPath = [
            skill.appendingPathComponent("SKILL.md").path: """
            ---
            name: bits-code-guard
            description: 代码审查与 HTML 报告输出
            tags: ["代码审查", "HTML 报告"]
            triggers: ["/bits-code-guard", "review code"]
            ---

            # bits-code-guard

            面向代码变更的多维度代码质量审查 Skill。
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
