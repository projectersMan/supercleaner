import Foundation
import XCTest
@testable import CleanerCore

final class LocalAIModelScannerTests: XCTestCase {
    func testProviderLayoutsKeepModelUnitsAndRequireManualSelection() async throws {
        let fixture = LocalAIModelFixture()
        let files: [(String, UInt64)] = [
            (".cache/huggingface/hub/models--org--text/blobs/weights", 100),
            (".cache/huggingface/hub/models--org--text/snapshots/revision/config.json", 4),
            (".cache/huggingface/hub/datasets--org--data/blobs/data", 30),
            (".lmstudio/models/publisher/chat/model.gguf", 200),
            (".cache/lm-studio/models/publisher/old/model.gguf", 50),
            (".cache/torch/hub/checkpoints/model.pth", 40),
            (".cache/whisper/base.pt", 60),
            (".keras/models/network.h5", 70),
            (".keras/datasets/mnist.npz", 80),
            ("Library/Application Support/nomic.ai/GPT4All/chat.gguf", 90),
        ]
        for (path, size) in files { await fixture.fileSystem.addFile(fixture.url(path), size: size) }
        await fixture.fileSystem.addFile(fixture.url(".keras/keras.json"), size: 5)
        await fixture.fileSystem.addFile(fixture.url(".cache/huggingface/token"), size: 5)
        await fixture.fileSystem.addFile(fixture.url("Library/Application Support/nomic.ai/GPT4All/settings.json"), size: 5)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.models.count, 9)
        XCTAssertEqual(Set(inventory.models.map(\.provider)), Set(LocalAIModelProvider.allCases.filter { $0 != .ollama }))
        XCTAssertTrue(inventory.candidates.allSatisfy { $0.risk == .review && $0.defaultSelection == false && $0.requiresExplicitSelection == true })
        XCTAssertTrue(inventory.candidates.allSatisfy { $0.source == .localAIModels && $0.category == .agentModelCache })
        XCTAssertTrue(inventory.candidates.allSatisfy { !PlanItem(candidate: $0).isSelected })
        XCTAssertFalse(inventory.candidates.contains { $0.url.lastPathComponent == "settings.json" || $0.url.lastPathComponent == "keras.json" || $0.url.lastPathComponent == "token" })
        XCTAssertTrue(inventory.limitations.isEmpty)
    }

    func testRootAndCandidateSymlinksAreExcludedWithoutFollowingTargets() async throws {
        let fixture = LocalAIModelFixture()
        await fixture.fileSystem.addFile(fixture.url(".lmstudio/models/publisher/linked/model.gguf"), size: 700)
        await fixture.fileSystem.replace(fixture.url(".lmstudio/models/publisher/linked"), kind: .symbolicLink)
        await fixture.fileSystem.addFile(fixture.url(".lmstudio/models/publisher/real/model.gguf"), size: 100)
        await fixture.fileSystem.addFile(fixture.url(".cache/huggingface/hub/models--org--hidden/blobs/weights"), size: 800)
        await fixture.fileSystem.replace(fixture.url(".cache/huggingface"), kind: .symbolicLink)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.map(\.url), [fixture.url(".lmstudio/models/publisher/real")])
        XCTAssertFalse(inventory.limitations.isEmpty)
        let requested = await fixture.fileSystem.childRequests()
        XCTAssertFalse(requested.contains(fixture.url(".lmstudio/models/publisher/linked")))
        XCTAssertFalse(requested.contains(fixture.url(".cache/huggingface/hub")))
    }

    func testHuggingFaceSnapshotLinksDoNotDoubleCountBlobContent() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".cache/huggingface/hub/models--org--chat")
        await fixture.fileSystem.addFile(model.appendingPathComponent("blobs/weights"), size: 100)
        await fixture.fileSystem.addFile(model.appendingPathComponent("snapshots/hash/model.bin"), size: 100)
        await fixture.fileSystem.replace(model.appendingPathComponent("snapshots/hash/model.bin"), kind: .symbolicLink)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.count, 1)
        XCTAssertEqual(inventory.candidates.first?.bytes, 100)
        XCTAssertEqual(inventory.candidates.first?.risk, .review)
    }

    func testProcessNamesPathsAndUnavailableActivityDoNotRestrictModelCleanup() async throws {
        let fixture = LocalAIModelFixture()
        await fixture.fileSystem.addFile(fixture.url(".cache/whisper/base.pt"), size: 100)
        let scanner = LocalAIModelScanner()

        let running = try await scanner.scan(context: fixture.context(processes: ["python3.13", "Ollama"]))
        XCTAssertEqual(running.candidates.count, 1)
        XCTAssertTrue(running.candidates.allSatisfy { ResourceCleanupListPolicy.isSelectable($0) && !$0.isActive })
        let unknown = try await scanner.scan(context: fixture.context(activityAvailable: false))
        XCTAssertTrue(unknown.candidates.allSatisfy { ResourceCleanupListPolicy.isSelectable($0) && !$0.isActive })
        let active = try await scanner.scan(context: fixture.context(activePaths: [fixture.url(".cache/whisper/base.pt")]))
        XCTAssertEqual(active.models.first { $0.provider == .whisper }?.candidate.risk, .review)
        XCTAssertTrue(unknown.limitations.isEmpty)
        XCTAssertFalse((running.candidates + unknown.candidates + active.candidates).flatMap(\.evidence).contains { $0.code == "local-ai-model-active" })
    }

    func testUnreadableContentIsBlockedAndReportsCoverageInsteadOfSafeZero() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        await fixture.fileSystem.addFile(model.appendingPathComponent("model.gguf"), size: 100)
        await fixture.fileSystem.denyChildren(model)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
        XCTAssertTrue(inventory.coverage.unavailableRoots.contains(model))
        XCTAssertTrue(inventory.limitations.contains { $0.path == model && $0.reason == .access })
    }

    func testMissingChildIdentityReportsLimitationAndBlocksParent() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        let file = model.appendingPathComponent("model.gguf")
        await fixture.fileSystem.addFile(file, size: 100)
        await fixture.fileSystem.denyIdentity(file)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
        XCTAssertFalse(inventory.limitations.isEmpty)
    }

    func testCredentialsInsideModelUnitBlockWholeUnit() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        await fixture.fileSystem.addFile(model.appendingPathComponent("model.gguf"), size: 100)
        await fixture.fileSystem.addFile(model.appendingPathComponent("credentials.json"), size: 2)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
    }

    func testProviderRootsExcludeUnsupportedFilesAndUnrecognizedBinaryNames() async throws {
        let fixture = LocalAIModelFixture()
        await fixture.fileSystem.addFile(fixture.url(".cache/whisper/settings.bin"), size: 5)
        await fixture.fileSystem.addFile(fixture.url(".keras/models/preferences.bin"), size: 5)
        await fixture.fileSystem.addFile(fixture.url("Library/Application Support/nomic.ai/GPT4All/settings.bin"), size: 5)
        await fixture.fileSystem.addFile(fixture.url("Library/Application Support/nomic.ai/GPT4All/ggml-chat.bin"), size: 100)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.map(\.url), [fixture.url("Library/Application Support/nomic.ai/GPT4All/ggml-chat.bin")])
    }

    func testGenericReadErrorDoesNotMisreportPermissionDenial() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        await fixture.fileSystem.addFile(model.appendingPathComponent("model.gguf"), size: 100)
        await fixture.fileSystem.failReads(model)

        let inventory = try await LocalAIModelScanner().scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
        XCTAssertTrue(inventory.limitations.contains { $0.path == model && $0.reason == nil })
    }

    func testRealFileSystemFixtureLeavesConfigOutsideModelScopeAndSkipsSnapshotLinks() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/local-ai-projects-disk/fixtures/" + UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let model = home.appendingPathComponent(".cache/huggingface/hub/models--org--chat", isDirectory: true)
        let blob = model.appendingPathComponent("blobs/weights")
        let snapshot = model.appendingPathComponent("snapshots/hash/model.bin")
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: blob)
        try FileManager.default.createSymbolicLink(at: snapshot, withDestinationURL: blob)
        let token = home.appendingPathComponent(".cache/huggingface/token")
        try Data("fixture-token".utf8).write(to: token)
        let context = ScanContext(homeDirectory: home, fileSystem: LocalFileSystem())

        let inventory = try await LocalAIModelScanner().scan(context: context)
        let candidate = try XCTUnwrap(inventory.candidates.first)

        XCTAssertEqual(inventory.candidates.count, 1)
        XCTAssertEqual(candidate.bytes, 100)
        XCTAssertEqual(candidate.risk, .review)
        try await LocalAIModelScanner().validateForExecution(candidate, context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: token.path))
    }

    func testEntryBudgetRetainsBlockedPartialCandidateAndLimitation() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        for index in 0..<30 { await fixture.fileSystem.addFile(model.appendingPathComponent("blobs/sha256-\(index)"), size: 100) }

        let inventory = try await LocalAIModelScanner(maximumEntries: 12, timeLimit: 30).scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
        XCTAssertTrue(inventory.coverage.budgetLimitedModules.contains(.localAIModels))
        XCTAssertTrue(inventory.limitations.contains { $0.reason == .budget })
    }

    func testExhaustedBudgetStopsBeforeInspectingFurtherModelCandidates() async throws {
        let fixture = LocalAIModelFixture()
        for index in 0..<5 { await fixture.fileSystem.addFile(fixture.url(".cache/whisper/model-\(index).pt"), size: 100) }

        let inventory = try await LocalAIModelScanner(maximumEntries: 6, timeLimit: 30).scan(context: fixture.context())

        XCTAssertEqual(inventory.candidates.count, 1)
        XCTAssertEqual(inventory.candidates.first?.risk, .blocked)
        XCTAssertTrue(inventory.coverage.budgetLimitedModules.contains(.localAIModels))
    }

    func testCancellationIsPropagated() async throws {
        let fixture = LocalAIModelFixture()
        await fixture.fileSystem.addFile(fixture.url(".cache/whisper/base.pt"), size: 100)
        await fixture.fileSystem.cancelReads()

        do {
            _ = try await LocalAIModelScanner().scan(context: fixture.context())
            XCTFail("Cancellation must escape the scanner")
        } catch is CancellationError {
            return
        }
    }

    func testExecutionRevalidatesProviderScopeAndIdentityWithoutActivityGate() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".cache/whisper/base.pt")
        await fixture.fileSystem.addFile(model, size: 100)
        let scanner = LocalAIModelScanner()
        let inventory = try await scanner.scan(context: fixture.context())
        let candidate = try XCTUnwrap(inventory.candidates.first)
        try await scanner.validateForExecution(candidate, context: fixture.context())

        try await scanner.validateForExecution(candidate, context: fixture.context(processes: ["python"], activityAvailable: false, activePaths: [model]))
        let forged = CleanupCandidate(url: fixture.url(".keras/keras.json"), displayName: "config", category: .agentModelCache,
            bytes: candidate.bytes, risk: .review, evidence: candidate.evidence, identity: candidate.identity,
            source: .localAIModels, lastAccessDate: nil, isActive: false, defaultSelection: false, requiresExplicitSelection: true)
        await assertExecutionRefused(scanner, candidate: forged, context: fixture.context())
        await fixture.fileSystem.replace(model, kind: .file)
        await assertExecutionRefused(scanner, candidate: candidate, context: fixture.context())
    }

    func testExecutionRejectsChangedContentsAndNewSymlinkAncestor() async throws {
        let fixture = LocalAIModelFixture()
        let model = fixture.url(".lmstudio/models/publisher/chat")
        let file = model.appendingPathComponent("model.gguf")
        await fixture.fileSystem.addFile(file, size: 100)
        let scanner = LocalAIModelScanner()
        let inventory = try await scanner.scan(context: fixture.context())
        let candidate = try XCTUnwrap(inventory.candidates.first)
        await fixture.fileSystem.replace(file, kind: .file)
        await assertExecutionRefused(scanner, candidate: candidate, context: fixture.context())
        await fixture.fileSystem.replace(fixture.url(".lmstudio/models/publisher"), kind: .symbolicLink)
        await assertExecutionRefused(scanner, candidate: candidate, context: fixture.context())
    }

    private func assertExecutionRefused(_ scanner: LocalAIModelScanner, candidate: CleanupCandidate, context: ScanContext) async {
        do {
            try await scanner.validateForExecution(candidate, context: context)
            XCTFail("Execution must be refused")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }
}

private struct LocalAIModelFixture {
    let home = URL(fileURLWithPath: "/Users/local-ai-fixture", isDirectory: true)
    let fileSystem = LocalAIModelFixtureFileSystem()

    func url(_ path: String) -> URL { home.appendingPathComponent(path).standardizedFileURL }
    func context(processes: Set<String> = [], activityAvailable: Bool = true, activePaths: Set<URL> = []) -> ScanContext {
        ScanContext(homeDirectory: home, fileSystem: fileSystem, now: Date(timeIntervalSince1970: 1_000),
            activePaths: activePaths, activeProcessNames: processes, activityProbeAvailable: activityAvailable)
    }
}

private actor LocalAIModelFixtureFileSystem: FileSystemAccess {
    private var identities: [String: FileIdentity] = [:]
    private var entries: [String: [URL]] = [:]
    private var refusedChildren = Set<String>()
    private var refusedIdentities = Set<String>()
    private var failedReads = Set<String>()
    private var requests: [URL] = []
    private var nextInode: UInt64 = 1
    private var cancelled = false

    func addFile(_ url: URL, size: UInt64) {
        var directories: [URL] = []
        var parent = url.deletingLastPathComponent()
        while true {
            directories.append(parent)
            if parent.path == "/" { break }
            parent = parent.deletingLastPathComponent()
        }
        for directory in directories.reversed() where identities[directory.path] == nil {
            identities[directory.path] = identity(kind: .directory, size: 0)
            entries[directory.path] = []
            let parentURL = directory.deletingLastPathComponent()
            if parentURL.path != directory.path { entries[parentURL.path, default: []].append(URL(fileURLWithPath: directory.path)) }
        }
        identities[url.path] = identity(kind: .file, size: size)
        entries[url.deletingLastPathComponent().path, default: []].append(url)
    }

    func replace(_ url: URL, kind: FileIdentity.Kind) {
        identities[url.path] = identity(kind: kind, size: identities[url.path]!.size)
    }
    func denyChildren(_ url: URL) { refusedChildren.insert(url.path) }
    func denyIdentity(_ url: URL) { refusedIdentities.insert(url.path) }
    func failReads(_ url: URL) { failedReads.insert(url.path) }
    func cancelReads() { cancelled = true }
    func childRequests() -> [URL] { requests }

    func identity(at url: URL) throws -> FileIdentity {
        if cancelled { throw CancellationError() }
        if refusedIdentities.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
        guard let result = identities[url.standardizedFileURL.path] else { throw FileSystemError.missing(url) }
        return result
    }
    func children(of url: URL) throws -> [URL] {
        if cancelled { throw CancellationError() }
        requests.append(url)
        if refusedChildren.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
        if failedReads.contains(url.path) { throw CocoaError(.fileReadUnknown) }
        guard let children = entries[url.path] else { throw FileSystemError.missing(url) }
        return children
    }
    func isReadable(_ url: URL) -> Bool { !refusedChildren.contains(url.path) }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }

    private func identity(kind: FileIdentity.Kind, size: UInt64) -> FileIdentity {
        defer { nextInode += 1 }
        return FileIdentity(device: 1, inode: nextInode, size: size, modificationTime: 100, kind: kind)
    }
}
