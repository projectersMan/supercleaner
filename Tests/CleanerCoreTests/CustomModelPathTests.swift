import Foundation
import XCTest
@testable import CleanerCore

final class CustomModelPathTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        fixture = root.appendingPathComponent("Tests/temporary/custom-model-paths/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: fixture) }

    func testSavedCustomRootSupplementsBuiltInModelDiscoveryAndRemovalRevokesExecution() async throws {
        let home = fixture.appendingPathComponent("home")
        let external = fixture.appendingPathComponent("custom-whisper")
        let fixed = try put("home/.cache/whisper/base.pt")
        let custom = try put("custom-whisper/large.pt")
        try saveRoots([external], home: home)
        let coordinator = SystemScanCoordinator()
        let scanned = await coordinator.scan(context: .init(homeDirectory: home), modules: [.localAIModels])
        let report = try XCTUnwrap(scanned)
        let models = try XCTUnwrap(report.localAIModelInventory).candidates
        XCTAssertEqual(Set(models.map(\.url.path)), [fixed.path, custom.path])
        XCTAssertTrue(models.allSatisfy { $0.defaultSelection == false && $0.requiresExplicitSelection == true })
        let candidate = try XCTUnwrap(models.first { $0.url.path == custom.path })
        let runtime = CleanupRuntime(home: home)
        try await runtime.validateForExecution(candidate)
        try saveRoots([], home: home)
        let validation = await Task { try await runtime.validateForExecution(candidate) }.result
        if case .success = validation { XCTFail("Removing a configured root must revoke its old candidate") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: custom.path))
    }

    func testInvalidConfigurationFailsOnlyModelModuleAndDoesNotRewriteFile() async throws {
        let home = fixture.appendingPathComponent("home")
        let config = try put("home/Library/Application Support/SuperCleaner/model-scan-roots.json")
        let invalid = Data("{\"schemaVersion\":1}".utf8)
        try invalid.write(to: config)
        let coordinator = SystemScanCoordinator(applicationScanner: ApplicationScanner(applicationRoots: [home.appendingPathComponent("Applications")]))
        let scanned = await coordinator.scan(context: .init(homeDirectory: home), modules: [.general, .localAIModels])
        let report = try XCTUnwrap(scanned)
        XCTAssertEqual(report.modules[.localAIModels]?.state, .failed)
        XCTAssertTrue([ScanModuleState.completed, .limited].contains(try XCTUnwrap(report.modules[.general]?.state)))
        XCTAssertEqual(try Data(contentsOf: config), invalid)
        let configuration = try await CleanupRuntime(home: home).configuration(includeProcessActivity: false)
        XCTAssertTrue(configuration.context.modelRoots.isEmpty)
    }

    func testStoreNormalizesDuplicatesAndRejectsBroadOrInvalidRootsWithoutOverwriting() async throws {
        let home = fixture.appendingPathComponent("home")
        let config = home.appendingPathComponent("Library/Application Support/SuperCleaner/model-scan-roots.json")
        let store = ModelStorageRootsStore(url: config, home: home)
        let path = fixture.appendingPathComponent("whisper")
        let roots = try await store.save([
            .init(provider: .whisper, url: URL(fileURLWithPath: path.path)),
            .init(provider: .whisper, url: URL(fileURLWithPath: path.path, isDirectory: true)),
        ])
        XCTAssertEqual(roots.count, 1)
        let reopened = try await ModelStorageRootsStore(url: config, home: home).roots()
        XCTAssertEqual(reopened, roots)
        let saved = try Data(contentsOf: config)
        for invalid in [home, URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes"), URL(string: "https://example.com/models")!] {
            let result = await Task { try await store.save([.init(provider: .whisper, url: invalid)]) }.result
            if case .success = result { XCTFail("Invalid root must fail: \(invalid)") }
            XCTAssertEqual(try Data(contentsOf: config), saved)
        }
    }

    func testMissingCustomRootAndSymlinkAreReportedWithoutScanningTarget() async throws {
        let home = fixture.appendingPathComponent("home")
        let model = try put("real-whisper/model.pt")
        let link = fixture.appendingPathComponent("linked-whisper")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: model.deletingLastPathComponent())
        let missing = fixture.appendingPathComponent("missing-whisper")
        let inventory = try await LocalAIModelScanner().scan(context: .init(homeDirectory: home, modelRoots: [
            .init(provider: .whisper, url: link), .init(provider: .whisper, url: missing),
        ]))
        XCTAssertTrue(inventory.candidates.isEmpty)
        XCTAssertEqual(Set(inventory.limitations.compactMap(\.path).map(\.path)), [link.path, missing.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.path))
    }

    func testModelScopeAndComfyUIUseOnlyExplicitRootsAndKeepManualSelection() async throws {
        let home = fixture.appendingPathComponent("home")
        _ = try put("home/ComfyUI/models/checkpoints/ignored.safetensors")
        _ = try put("home/.cache/modelscope/hub/models/org/ignored/model.safetensors")
        let scope = try put("modelscope/org/chat/model.safetensors")
        let comfy = try put("comfy/checkpoints/nested/image.safetensors")
        let context = ScanContext(homeDirectory: home, modelRoots: [
            .init(provider: .modelScope, url: fixture.appendingPathComponent("modelscope")),
            .init(provider: .comfyUI, url: fixture.appendingPathComponent("comfy")),
        ])
        let inventory = try await LocalAIModelScanner().scan(context: context)
        XCTAssertEqual(Set(inventory.candidates.map(\.url.path)), [scope.deletingLastPathComponent().path, comfy.path])
        XCTAssertTrue(inventory.limitations.isEmpty)
        for candidate in inventory.candidates {
            XCTAssertEqual(candidate.defaultSelection, false)
            XCTAssertEqual(candidate.requiresExplicitSelection, true)
            try await LocalAIModelScanner().validateForExecution(candidate, context: context)
        }
    }

    private func put(_ relative: String) throws -> URL {
        let path = fixture.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: path)
        return path
    }

    private func saveRoots(_ roots: [URL], home: URL) throws {
        let path = home.appendingPathComponent("Library/Application Support/SuperCleaner/model-scan-roots.json")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entries = roots.map { ["provider": "whisper", "url": $0.absoluteString] }
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "roots": entries], options: [.sortedKeys]).write(to: path, options: .atomic)
    }
}
