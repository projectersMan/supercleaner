import Foundation
import XCTest
@testable import CleanerCore

final class OllamaModelCleanupTests: XCTestCase {
    func testFailedSelectedManifestKeepsSharedBlobsButDoesNotBlockOtherModel() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: Set(inventory.candidates.map(\.id)))
        let context = fixture.context
        let refusedManifest = fixture.firstManifest
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: fixture.home),
            quarantineRoot: fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine"),
            currentRuleVersion: "bundled-1", loadProtection: { context.protectionPolicy },
            validateCandidate: { candidate in
                if candidate.url == refusedManifest { throw RuleScanError.executionRefused("fixture-manifest-refusal") }
                try await LocalAIModelScanner().validateForExecution(candidate, context: context)
            })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first { $0.originalURL == fixture.firstManifest }?.status, .skippedProtected)
        XCTAssertEqual(receipt.results.first { $0.originalURL == fixture.secondManifest }?.status, .succeeded)
        for name in ["a", "b", "c"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.blob(name).path))
            XCTAssertEqual(receipt.results.first { $0.originalURL == fixture.blob(name) }?.status, .skippedProtected)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.blob("d").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstManifest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.secondManifest.path))
    }

    func testModelsMoveToTrashUsingProductionRecoveryDirectory() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: Set(inventory.candidates.map(\.id)))
        let receipt = await fixture.executor().execute(plan: plan)
        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .succeeded })
        let fileSystem = ModelTrashFixtureFileSystem(trashRoot: fixture.root.appendingPathComponent("fake-trash"))
        let executor = CleanupExecutor(fileSystem: fileSystem, pathPolicy: PathPolicy(homeDirectory: fixture.home),
            quarantineRoot: fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine"),
            currentRuleVersion: "bundled-1")
        let entry = await executor.prepareResolution(action: .trash, receipt: receipt, id: UUID(), startedAt: Date())
        let results = await executor.resolve(entry)
        XCTAssertEqual(results.count, 6)
        XCTAssertTrue(results.allSatisfy { $0.status == .succeeded && $0.disposition == .trashed })
        for result in receipt.results {
            let source = try XCTUnwrap(result.destinationURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathExtension("ollama-files").path))
        }
    }

    func testRecoveryRejectsForgedSnapshotDestination() async throws {
        let fixture = try makeFixture()
        let planDirectory = fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine/" + UUID().uuidString)
        let recovery = OllamaModelRecovery(context: fixture.context, planDirectory: planDirectory)
        let forged = OperationResult(candidateID: UUID(), originalURL: fixture.firstManifest,
            destinationURL: fixture.home.appendingPathComponent("Documents/important"), disposition: .quarantined, status: .succeeded, bytes: 1)
        XCTAssertThrowsError(try recovery.directory(for: forged))
    }

    func testRecoverySnapshotSymlinkCannotAuthorizeDeletionOfItsTarget() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let candidate = try XCTUnwrap(inventory.candidates.first { $0.ollamaModelProof != nil })
        let planDirectory = fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: planDirectory, withIntermediateDirectories: true)
        let destination = planDirectory.appendingPathComponent(candidate.id.uuidString + "-" + candidate.url.lastPathComponent)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathExtension("ollama-files"), withDestinationURL: fixture.storage)
        let recovery = OllamaModelRecovery(context: fixture.context, planDirectory: planDirectory)
        let outcome = await Task { try await recovery.prepare(candidate, destination: destination) }.result
        if case .success = outcome { XCTFail("Recovery preparation must reject a symlink") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstManifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.blob("b").path))
    }

    func testRecoveryRejectsPlanDirectorySymlinkBeforeCreatingAnything() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let candidate = try XCTUnwrap(inventory.candidates.first { $0.ollamaModelProof != nil })
        let planDirectory = fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: planDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = fixture.root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: planDirectory, withDestinationURL: target)
        let recovery = OllamaModelRecovery(context: fixture.context, planDirectory: planDirectory)
        let destination = planDirectory.appendingPathComponent(candidate.id.uuidString + "-" + candidate.url.lastPathComponent)
        let outcome = await Task { try await recovery.prepare(candidate, destination: destination) }.result
        if case .success = outcome { XCTFail("A symlinked plan directory must be rejected before mutation") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    func testModelsHaveNamesAndSingleSelectionPreservesSharedBlobs() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertEqual(Set(inventory.candidates.map(\.displayName)), ["qwen3:0.6b", "team/chat:latest"])
        let selected = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [selected.id])
        XCTAssertEqual(Set(plan.selectedItems.map(\.candidate.url)), [fixture.firstManifest, fixture.blob("c")])
        XCTAssertEqual(plan.selectedBytes, UInt64(try Data(contentsOf: fixture.firstManifest).count) + 20)
        XCTAssertTrue(inventory.limitations.isEmpty)
    }

    func testSelectingBothModelsIncludesSharedBlobsOnceAfterManifests() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: Set(inventory.candidates.map(\.id)))
        XCTAssertEqual(plan.selectedItems.count, 6)
        XCTAssertEqual(Set(plan.selectedItems.map(\.candidate.url)),
            [fixture.firstManifest, fixture.secondManifest, fixture.blob("a"), fixture.blob("b"), fixture.blob("c"), fixture.blob("d")])
        XCTAssertEqual(Set(plan.selectedItems.prefix(2).map(\.candidate.url)), [fixture.firstManifest, fixture.secondManifest])
        XCTAssertEqual(plan.selectedBytes, UInt64(try Data(contentsOf: fixture.firstManifest).count + Data(contentsOf: fixture.secondManifest).count) + 153)
    }

    func testSingleModelUsesCommonExecutorAndRestoresWithoutChangingOtherModel() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let selected = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let manifestData = try Data(contentsOf: fixture.firstManifest)
        let retainedData = try Data(contentsOf: fixture.secondManifest)
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [selected.id])
        let executor = fixture.executor()

        let receipt = await executor.execute(plan: plan)

        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .succeeded])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.firstManifest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.blob("c").path))
        XCTAssertEqual(try Data(contentsOf: fixture.secondManifest), retainedData)
        for name in ["a", "b", "d"] { XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.blob(name).path)) }
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.count, 2)
        XCTAssertTrue(restored.results.allSatisfy { $0.disposition == .restored })
        XCTAssertEqual(try Data(contentsOf: fixture.firstManifest), manifestData)
        XCTAssertEqual(try Data(contentsOf: fixture.blob("c")), Data(repeating: 1, count: 20))
    }

    func testAllSelectedModelsAndSharedBlobsExecuteAndRestore() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: Set(inventory.candidates.map(\.id)))
        let executor = fixture.executor()
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.count, 6)
        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .succeeded })
        XCTAssertTrue(plan.selectedItems.allSatisfy { !FileManager.default.fileExists(atPath: $0.candidate.url.path) })
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.count, 6)
        XCTAssertTrue(restored.results.allSatisfy { $0.disposition == .restored })
        let rescanned = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertEqual(rescanned.models.count, 2)
        XCTAssertTrue(rescanned.limitations.isEmpty)
    }

    func testNewReferenceAfterScanProtectsBlobDuringExecution() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let selected = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [selected.id])
        let newManifest = fixture.storage.appendingPathComponent("manifests/registry.ollama.ai/library/new/latest")
        try fixture.writeManifest(newManifest, privateBlob: "c", size: 20)

        let receipt = await fixture.executor().execute(plan: plan)

        XCTAssertEqual(receipt.results.map(\.status), [.succeeded, .skippedProtected])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.blob("c").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newManifest.path))
    }

    func testFailedManifestRemovalKeepsItsBlobs() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let selected = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [selected.id])
        try fixture.writeManifest(fixture.firstManifest, privateBlob: "c", size: 20)

        let receipt = await fixture.executor().execute(plan: plan)

        XCTAssertEqual(receipt.results.count, 2)
        XCTAssertFalse(receipt.results.contains { $0.status == .succeeded })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstManifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.blob("c").path))
    }

    func testMalformedOrUnsupportedManifestLayoutDoesNotProduceDeletableModels() async throws {
        let fixture = try makeFixture()
        try Data("invalid manifest".utf8).write(to: fixture.secondManifest)
        let malformed = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertTrue(malformed.candidates.isEmpty)
        XCTAssertFalse(malformed.limitations.isEmpty)
        try fixture.writeManifest(fixture.secondManifest, privateBlob: "d", size: 30)
        try FileManager.default.createDirectory(at: fixture.storage.appendingPathComponent("manifests-v2"), withIntermediateDirectories: true)
        let unsupported = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertTrue(unsupported.candidates.isEmpty)
        XCTAssertFalse(unsupported.limitations.isEmpty)
    }

    func testBlobSymlinkIsNeverFollowedOrScheduledForDeletion() async throws {
        let fixture = try makeFixture()
        try FileManager.default.removeItem(at: fixture.blob("c"))
        try FileManager.default.createSymbolicLink(at: fixture.blob("c"), withDestinationURL: fixture.blob("d"))
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertTrue(inventory.candidates.isEmpty)
        XCTAssertFalse(inventory.limitations.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.blob("d")), Data(repeating: 1, count: 30))
    }

    func testConsecutiveCleanupBatchesUpdateReferencesWithoutRescanning() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let report = SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "bundled-1"),
            modules: [.localAIModels: .init(module: .localAIModels, state: .completed)], generalCandidates: [],
            applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: [], localAIModelInventory: inventory)
        let first = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let firstPlan = try PlanBuilder().build(candidates: report.candidates, selectedIDs: [first.id])
        let executor = fixture.executor()
        let receipt = await executor.execute(plan: firstPlan)
        let remaining = report.reconcilingCleanup(receipt)
        let second = try XCTUnwrap(remaining.localAIModelInventory?.candidates.first)
        XCTAssertEqual(second.displayName, "team/chat:latest")
        let secondPlan = try PlanBuilder().build(candidates: remaining.candidates, selectedIDs: [second.id])
        XCTAssertEqual(Set(secondPlan.selectedItems.map(\.candidate.url)),
            [fixture.secondManifest, fixture.blob("a"), fixture.blob("b"), fixture.blob("d")])
        let secondReceipt = await executor.execute(plan: secondPlan)
        XCTAssertEqual(secondReceipt.results.count, 4)
        XCTAssertTrue(secondReceipt.results.allSatisfy { $0.status == .succeeded })
    }

    func testPurgingLaterBatchCannotBreakEarlierModelRecovery() async throws {
        let fixture = try makeFixture()
        let executor = fixture.executor()
        let firstScan = try await LocalAIModelScanner().scan(context: fixture.context)
        let first = try XCTUnwrap(firstScan.candidates.first { $0.displayName == "qwen3:0.6b" })
        let firstReceipt = await executor.execute(plan: try PlanBuilder().build(candidates: firstScan.candidates, selectedIDs: [first.id]))
        let secondScan = try await LocalAIModelScanner().scan(context: fixture.context)
        let second = try XCTUnwrap(secondScan.candidates.first)
        let secondReceipt = await executor.execute(plan: try PlanBuilder().build(candidates: secondScan.candidates, selectedIDs: [second.id]))
        let purged = await executor.purge(receipt: secondReceipt)
        XCTAssertTrue(purged.results.allSatisfy { $0.status == .succeeded })

        let restored = await executor.restore(receipt: firstReceipt)

        XCTAssertTrue(restored.results.allSatisfy { $0.disposition == .restored })
        let restoredScan = try await LocalAIModelScanner().scan(context: fixture.context)
        XCTAssertEqual(restoredScan.candidates.map(\.displayName), ["qwen3:0.6b"])
        XCTAssertTrue(restoredScan.limitations.isEmpty)
    }

    func testRecoveryRejectsSymlinkInBlobDestinationAncestors() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let first = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let executor = fixture.executor()
        let receipt = await executor.execute(plan: try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [first.id]))
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let blobs = fixture.storage.appendingPathComponent("blobs")
        try FileManager.default.moveItem(at: blobs, to: fixture.root.appendingPathComponent("original-blobs"))
        try FileManager.default.createSymbolicLink(at: blobs, withDestinationURL: outside)

        let restored = await executor.restore(receipt: receipt)

        XCTAssertFalse(restored.results.contains { $0.candidateID == first.id && $0.disposition == .restored })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testFinalValidationFailureRemovesUncommittedRecoverySnapshots() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let first = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [first.id])
        let context = fixture.context
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: fixture.home),
            quarantineRoot: fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine"), currentRuleVersion: "bundled-1",
            loadProtection: { context.protectionPolicy },
            validateCandidate: { try await LocalAIModelScanner().validateForExecution($0, context: context) },
            finalCandidateCheck: { _ in throw RuleScanError.executionRefused("fixture-refusal") })

        let receipt = await executor.execute(plan: plan)

        XCTAssertFalse(receipt.results.contains { $0.status == .succeeded })
        let archived = fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine/" + plan.id.uuidString)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: archived, includingPropertiesForKeys: nil)
            .allSatisfy { $0.pathExtension != "ollama-files" })
    }

    func testInterruptedPreparationRemovesUncommittedSnapshots() async throws {
        let fixture = try makeFixture()
        let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
        let first = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
        let plan = try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [first.id])
        let archived = fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine/" + plan.id.uuidString)
        let destination = archived.appendingPathComponent(first.id.uuidString + "-" + first.url.lastPathComponent)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        try await OllamaModelRecovery(context: fixture.context, planDirectory: archived).prepare(first, destination: destination)
        let entry = ExecutionJournalEntry(id: UUID(), plan: plan, startedAt: Date(), retentionPolicy: .manual)

        let recovered = await fixture.executor().recoverInterruptedExecution(entry)

        XCTAssertFalse(recovered.results.contains { $0.status == .succeeded })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathExtension("ollama-files").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
    }

    func testRestoreAndPurgeRetrySnapshotCleanupAfterPrimaryFileAlreadyMoved() async throws {
        for action in [ResolutionAction.restore, .purge] {
            let fixture = try makeFixture()
            let inventory = try await LocalAIModelScanner().scan(context: fixture.context)
            let first = try XCTUnwrap(inventory.candidates.first { $0.displayName == "qwen3:0.6b" })
            let receipt = await fixture.executor().execute(plan: try PlanBuilder().build(candidates: inventory.candidates, selectedIDs: [first.id]))
            let remover = ModelSnapshotRemovalFailure()
            let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: fixture.home),
                quarantineRoot: fixture.home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine"), currentRuleVersion: "bundled-1",
                permanentRemove: { try await remover.remove($0) })
            let entry = await executor.prepareResolution(action: action, receipt: receipt, id: UUID(), startedAt: Date())
            let initial = await executor.resolve(entry)
            XCTAssertTrue(initial.contains { $0.status == .failed })

            let retried = await executor.resolve(entry)

            XCTAssertFalse(retried.contains { $0.status == .failed })
            let source = try XCTUnwrap(receipt.results.first?.destinationURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathExtension("ollama-files").path))
        }
    }

    private func makeFixture() throws -> OllamaCleanupFixture {
        let fixture = try OllamaCleanupFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        return fixture
    }
}

private struct ModelTrashFixtureFileSystem: FileSystemAccess {
    let trashRoot: URL
    private let local = LocalFileSystem()
    func identity(at url: URL) async throws -> FileIdentity { try await local.identity(at: url) }
    func children(of url: URL) async throws -> [URL] { try await local.children(of: url) }
    func fileExists(_ url: URL) async -> Bool { await local.fileExists(url) }
    func isReadable(_ url: URL) async -> Bool { await local.isReadable(url) }
    func isWritable(_ url: URL) async -> Bool { await local.isWritable(url) }
    func move(_ source: URL, to destination: URL) async throws { try await local.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await local.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await local.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL {
        try await local.createDirectory(trashRoot)
        let destination = trashRoot.appendingPathComponent(url.lastPathComponent)
        try await local.move(url, to: destination)
        return destination
    }
}

private actor ModelSnapshotRemovalFailure {
    private var shouldFail = true

    func remove(_ url: URL) throws {
        if url.pathExtension == "ollama-files" && shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: url)
    }
}

private struct OllamaCleanupFixture {
    let root: URL
    let home: URL
    var storage: URL { home.appendingPathComponent(".ollama/models") }
    var firstManifest: URL { storage.appendingPathComponent("manifests/registry.ollama.ai/library/qwen3/0.6b") }
    var secondManifest: URL { storage.appendingPathComponent("manifests/registry.ollama.ai/team/chat/latest") }
    var context: ScanContext {
        ScanContext(homeDirectory: home, fileSystem: LocalFileSystem(), activePaths: [storage],
            activeProcessNames: ["python3", "ollama"], activityProbeAvailable: false)
    }

    init() throws {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("local-ai-model-granularity/fixtures/" + UUID().uuidString)
        home = root.appendingPathComponent("home")
        for (name, size) in [("a", 3), ("b", 100), ("c", 20), ("d", 30)] {
            let url = blob(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
        try writeManifest(firstManifest, privateBlob: "c", size: 20)
        try writeManifest(secondManifest, privateBlob: "d", size: 30)
    }

    func blob(_ name: String) -> URL { storage.appendingPathComponent("blobs/sha256-" + String(repeating: name, count: 64)) }

    func executor() -> CleanupExecutor {
        let context = context
        return CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine"), currentRuleVersion: "bundled-1",
            isActive: { _ in XCTFail("Model cleanup must never request activity state"); return true },
            loadProtection: { context.protectionPolicy },
            validateCandidate: { try await LocalAIModelScanner().validateForExecution($0, context: context) },
            finalCandidateCheck: { try await LocalAIModelScanner().validateForExecution($0, context: context) })
    }

    func writeManifest(_ url: URL, privateBlob: String, size: Int) throws {
        let manifest: [String: Any] = [
            "schemaVersion": 2, "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
            "config": ["mediaType": "application/vnd.docker.container.image.v1+json", "digest": "sha256:" + String(repeating: "a", count: 64), "size": 3],
            "layers": [
                ["mediaType": "application/vnd.ollama.image.model", "digest": "sha256:" + String(repeating: "b", count: 64), "size": 100],
                ["mediaType": "application/vnd.ollama.image.template", "digest": "sha256:" + String(repeating: privateBlob, count: 64), "size": size],
            ],
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
    }
}
