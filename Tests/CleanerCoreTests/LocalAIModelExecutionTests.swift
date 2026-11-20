import Foundation
import XCTest
@testable import CleanerCore

final class LocalAIModelExecutionTests: XCTestCase {
    func testDeepWeightChangeDuringQuarantinePreparationPreventsDirectoryMove() async throws {
        let fixture = try makeFixture(kind: .directory, change: .weightsDuringPreparation)
        let candidate = try await fixture.candidate()

        let receipt = await fixture.executor(privileged: false).execute(plan: try fixture.plan(candidate))

        XCTAssertEqual(receipt.results.map(\.status), [.skippedProtected])
        if FileManager.default.fileExists(atPath: candidate.url.path) {
            let currentIdentity = try await fixture.fileSystem.identity(at: candidate.url)
            XCTAssertEqual(currentIdentity, candidate.identity,
                "A descendant write must be rejected even when the model directory identity remains unchanged")
        }
        try await assertModelRemains(fixture, candidate: candidate)
    }

    func testProviderStartDuringPreparationDoesNotPreventSingleModelFileMove() async throws {
        let fixture = try makeFixture(kind: .file, change: .processDuringPreparation)
        let candidate = try await fixture.candidate()

        let receipt = await fixture.executor(privileged: false).execute(plan: try fixture.plan(candidate))

        XCTAssertEqual(receipt.results.map(\.status), [.succeeded])
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.url.path))
    }

    func testProviderStartDuringHelperFallbackDoesNotPreventLocalModelMove() async throws {
        let fixture = try makeFixture(kind: .directory, change: .processDuringHelperFallback)
        let candidate = try await fixture.candidate()

        let receipt = await fixture.executor(privileged: true).execute(plan: try fixture.plan(candidate))

        XCTAssertEqual(receipt.results.map(\.status), [.succeeded])
        let calls = await fixture.fileSystem.helperCalls
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.url.path))
    }

    func testFileChangeDuringHelperFallbackPreservesStrictIdentity() async throws {
        let fixture = try makeFixture(kind: .file, change: .weightsDuringHelperFallback)
        let candidate = try await fixture.candidate()

        let receipt = await fixture.executor(privileged: true).execute(plan: try fixture.plan(candidate))

        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .skippedProtected || $0.status == .skippedIdentityChanged })
        XCTAssertFalse(candidate.allowsExecutionContentChanges)
        try await assertModelRemains(fixture, candidate: candidate)
    }

    func testUnchangedModelDirectoriesAndFilesRemainExecutable() async throws {
        for kind in [ModelExecutionFixture.Kind.directory, .file] {
            let fixture = try makeFixture(kind: kind, change: .none)
            let candidate = try await fixture.candidate()

            let receipt = await fixture.executor(privileged: false).execute(plan: try fixture.plan(candidate))

            XCTAssertEqual(receipt.results.map(\.status), [.succeeded])
            let moves = await fixture.fileSystem.moves
            XCTAssertEqual(moves, [candidate.url])
            XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.url.path))
        }
    }

    private func makeFixture(kind: ModelExecutionFixture.Kind, change: ModelExecutionChange) throws -> ModelExecutionFixture {
        let fixture = try ModelExecutionFixture(kind: kind, change: change)
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        return fixture
    }

    private func assertModelRemains(_ fixture: ModelExecutionFixture, candidate: CleanupCandidate) async throws {
        let applied = await fixture.fileSystem.changeApplied
        let moves = await fixture.fileSystem.moves
        XCTAssertTrue(applied, "The fixture must change state after initial validation")
        XCTAssertTrue(moves.isEmpty, "A stale model must never reach the filesystem move operation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.path))
    }
}

private enum ModelExecutionChange: Sendable {
    case none
    case weightsDuringPreparation
    case processDuringPreparation
    case processDuringHelperFallback
    case weightsDuringHelperFallback
}

private struct ModelExecutionFixture {
    enum Kind { case directory, file }
    let root: URL
    let home: URL
    let fileSystem: ModelExecutionFileSystem

    init(kind: Kind, change: ModelExecutionChange) throws {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("local-ai-projects-disk/fixtures/" + UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        let relativePath: String
        let processName: String
        switch kind {
        case .directory:
            relativePath = ".lmstudio/models/publisher/chat/deep/model.gguf"
            processName = "LM Studio"
        case .file:
            relativePath = ".cache/whisper/base.pt"
            processName = "python3"
        }
        let weights = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: weights.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("initial model".utf8).write(to: weights)
        fileSystem = ModelExecutionFileSystem(home: home, weights: weights, processName: processName, change: change)
    }

    func candidate() async throws -> CleanupCandidate {
        let inventory = try await LocalAIModelScanner().scan(context: await fileSystem.context())
        let candidate = try XCTUnwrap(inventory.candidates.first)
        XCTAssertEqual(candidate.risk, .review)
        try await fileSystem.validate(candidate)
        return candidate
    }

    func plan(_ candidate: CleanupCandidate) throws -> CleanupPlan {
        try PlanBuilder(ruleVersion: "model-execution-fixture").build(candidates: [candidate], selectedIDs: [candidate.id])
    }

    func executor(privileged: Bool) -> CleanupExecutor {
        CleanupExecutor(fileSystem: fileSystem, pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: "model-execution-fixture",
            loadProtection: { ProtectionPolicy(homeDirectory: home) },
            validateCandidate: { try await fileSystem.validate($0) },
            privilegedApplications: privileged ? fileSystem : nil,
            finalCandidateCheck: { try await fileSystem.validate($0) })
    }
}

/// Real local I/O with deterministic process changes at the executor's await boundaries.
private actor ModelExecutionFileSystem: FileSystemAccess, PrivilegedApplicationOperations {
    private let local = LocalFileSystem()
    private let home: URL
    private let weights: URL
    private let processName: String
    private let change: ModelExecutionChange
    private var processNames: Set<String> = []
    private(set) var moves: [URL] = []
    private(set) var helperCalls = 0
    private(set) var changeApplied = false

    init(home: URL, weights: URL, processName: String, change: ModelExecutionChange) {
        self.home = home
        self.weights = weights
        self.processName = processName
        self.change = change
    }

    func context() -> ScanContext {
        ScanContext(homeDirectory: home, fileSystem: self, activeProcessNames: processNames, activityProbeAvailable: true)
    }

    func validate(_ candidate: CleanupCandidate) async throws {
        try await LocalAIModelScanner().validateForExecution(candidate, context: context())
    }

    func identity(at url: URL) async throws -> FileIdentity { try await local.identity(at: url) }
    func itemGeneration(at url: URL) async throws -> String? { try await local.itemGeneration(at: url) }
    func children(of url: URL) async throws -> [URL] { try await local.children(of: url) }
    func isReadable(_ url: URL) async -> Bool { await local.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await local.isWritable(url) }
    func fileExists(_ url: URL) async -> Bool { await local.fileExists(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await local.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await local.trash(url) }

    func createDirectory(_ url: URL) async throws {
        try await local.createDirectory(url)
        if change == .weightsDuringPreparation { try rewriteWeights() }
        if change == .processDuringPreparation { startProvider() }
    }

    func move(_ source: URL, to destination: URL) async throws {
        moves.append(source)
        try await local.move(source, to: destination)
    }

    func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) async throws -> Bool {
        helperCalls += 1
        await Task.yield()
        if change == .weightsDuringHelperFallback { try rewriteWeights() }
        if change == .processDuringHelperFallback { startProvider() }
        return false
    }

    func restore(source: URL, destination: URL, planID: UUID) -> Bool { false }
    func purge(source: URL, planID: UUID) -> Bool { false }

    private func rewriteWeights() throws {
        try Data("changed model content after validation".utf8).write(to: weights)
        changeApplied = true
    }

    private func startProvider() {
        processNames.insert(processName)
        changeApplied = true
    }
}
