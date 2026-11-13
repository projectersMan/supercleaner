import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationGeneratedDataTests: XCTestCase {
    func testWeChatMessageFilesAreDiscoveredPerAccountAndRemainManual() async throws {
        let f = try Fixture(); defer { f.remove() }
        for account in ["account-a", "account-b"] {
            for leaf in ["attach", "file", "video", "migrate"] {
                try f.put("Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/\(account)/msg/\(leaf)/2026/payload.bin")
            }
            try f.put("Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/\(account)/db_storage/message.db")
        }
        let scanner = ApplicationCleanupScanner()
        let context = ScanContext(homeDirectory: f.home)
        let discovery = await scanner.discover(applications: [f.app("com.tencent.xinWeChat", version: nil)], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        XCTAssertEqual(result.candidates.count, 8)
        XCTAssertTrue(result.candidates.allSatisfy { $0.category == .applicationSupport && $0.requiresExplicitSelection == true && $0.defaultSelection == false && $0.bytes == 7 })
        XCTAssertTrue(result.candidates.allSatisfy { CleanupRecommendationPolicy().disposition(for: $0) == .retain })
        for mode in [CleanupMode.smart, .deep] {
            XCTAssertTrue(CleanupRecommendationPolicy().selectedIDs(for: result.candidates, mode: mode, currentSelection: []).isEmpty)
        }
        XCTAssertFalse(result.candidates.contains { $0.url.path.contains("db_storage") || $0.url.lastPathComponent == "msg" })
    }

    func testRegenerableApplicationCacheIsKeptForManualSelection() async throws {
        let f = try Fixture(); defer { f.remove() }
        try f.put("Library/Caches/com.example.generated/nested/payload")
        let scanner = ApplicationCleanupScanner(), context = ScanContext(homeDirectory: f.home)
        let discovery = await scanner.discover(applications: [f.app("com.example.generated")], context: context)
        XCTAssertEqual(discovery.targets.count, 1)
        let result = try await scanner.scan(discovery: discovery, context: context)
        let cache = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(cache.bytes, 7)
        XCTAssertEqual(cache.requiresExplicitSelection, true)
        XCTAssertEqual(cache.defaultSelection, false)
        XCTAssertEqual(CleanupRecommendationPolicy().disposition(for: cache), .retain)
        try await scanner.validateForExecution(cache, context: context, applications: [f.app("com.example.generated")])
    }

    func testEmptyApplicationCacheDoesNotCreateZeroByteRows() async throws {
        let f = try Fixture(); defer { f.remove() }
        try FileManager.default.createDirectory(at: f.home.appendingPathComponent("Library/Caches/com.example.generated"), withIntermediateDirectories: true)
        let scanner = ApplicationCleanupScanner(), context = ScanContext(homeDirectory: f.home)
        let discovery = await scanner.discover(applications: [f.app("com.example.generated")], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testNestedSandboxAndPartitionCachesAreDiscoveredWithoutUserDataRoots() async throws {
        let f = try Fixture(); defer { f.remove() }
        let leaves = ["Library/Application Support/com.example.generated/Partitions/session/Code Cache",
            "Library/Containers/com.example.generated/Data/Library/Application Support/Fixture/Cache",
            "Library/Containers/com.example.generated/Data/Library/Application Support/Fixture/Partitions/session/GPUCache"]
        for leaf in leaves { try f.put(leaf + "/payload") }
        try f.put("Library/Application Support/com.example.generated/User/settings.json")
        let scanner = ApplicationCleanupScanner(), context = ScanContext(homeDirectory: f.home)
        let discovery = await scanner.discover(applications: [f.app("com.example.generated")], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        XCTAssertEqual(Set(result.candidates.map { $0.url.path }), Set(leaves.map { f.home.appendingPathComponent($0).path }))
        XCTAssertTrue(result.candidates.allSatisfy { $0.bytes == 7 && $0.requiresExplicitSelection == true })
    }

    func testWeChatChatFileExecutionRequiresStoppedApplication() async throws {
        let f = try Fixture(); defer { f.remove() }
        try f.put("Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/account-a/msg/video/payload")
        let scanner = ApplicationCleanupScanner(), app = f.app("com.tencent.xinWeChat")
        let active = ScanContext(homeDirectory: f.home, runningBundleIdentifiers: [app.bundleIdentifier])
        let discovery = await scanner.discover(applications: [app], context: active)
        let result = try await scanner.scan(discovery: discovery, context: active)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertTrue(candidate.isActive)
        do {
            try await scanner.validateForExecution(candidate, context: active, applications: [app])
            XCTFail("Live chat-file cleanup must wait for WeChat to quit")
        } catch { }
        try await scanner.validateForExecution(candidate, context: .init(homeDirectory: f.home), applications: [app])
    }

    func testChatDatabaseAndLinkedMessageDirectoryAreNotSelectedAsUserFileRoots() async throws {
        let f = try Fixture(); defer { f.remove() }
        let base = "Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/account-a"
        try f.put(base + "/db_storage/message.db")
        try f.put("Documents/private/payload")
        let link = f.home.appendingPathComponent(base + "/msg/file")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.home.appendingPathComponent("Documents/private"))
        let scanner = ApplicationCleanupScanner(), context = ScanContext(homeDirectory: f.home)
        let discovery = await scanner.discover(applications: [f.app("com.tencent.xinWeChat")], context: context)
        let result = try await scanner.scan(discovery: discovery, context: context)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.home.appendingPathComponent(base + "/db_storage/message.db").path))
    }

    private struct Fixture {
        let home: URL
        init() throws {
            home = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent(".application-cleanup-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: home) }
        func put(_ relative: String) throws {
            let url = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("payload".utf8).write(to: url)
        }
        func app(_ id: String, version: String? = "4.1") -> InstalledApplication {
            .init(bundleURL: home.appendingPathComponent("Applications/Fixture.app"), bundleIdentifier: id,
                name: "Fixture", version: version, isRunning: false, isSystem: false)
        }
    }
}
