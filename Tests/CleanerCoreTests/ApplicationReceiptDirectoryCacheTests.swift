import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationReceiptDirectoryCacheTests: XCTestCase {
    func testMutationDuringParsingIsRejectedAndNeverCached() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cleanup-execution-repair/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bom = root.appendingPathComponent("receipt.bom")
        try Data("before".utf8).write(to: bom)
        let reader = ReceiptDirectoryReader(mutateOnFirstRead: true)
        let cache = ApplicationReceiptDirectoryCache(read: { url, _ in try await reader.read(url) })
        let context = ScanContext(fileSystem: LocalFileSystem())
        let outcome = await Task { try await cache.directories(in: bom, context: context, timeout: 2) }.result
        if case .success = outcome { XCTFail("Changed receipt bytes must not authorize a cached parse") }
        let current = try await cache.directories(in: bom, context: context, timeout: 2)
        XCTAssertEqual(current, "modified during parsing")
        let reads = await reader.calls
        XCTAssertEqual(reads, 2)
    }
    func testUnchangedReceiptReusesParseAndChangedReceiptIsReadAgain() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cleanup-execution-repair/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bom = root.appendingPathComponent("receipt.bom")
        try Data("first".utf8).write(to: bom)
        let reader = ReceiptDirectoryReader(mutateOnFirstRead: false)
        let cache = ApplicationReceiptDirectoryCache(read: { url, _ in try await reader.read(url) })
        let context = ScanContext(fileSystem: LocalFileSystem())
        let first = try await cache.directories(in: bom, context: context, timeout: 2)
        let repeated = try await cache.directories(in: bom, context: context, timeout: 2)
        XCTAssertEqual(first, repeated)
        let initialReads = await reader.calls
        XCTAssertEqual(initialReads, 1)
        try Data("changed receipt".utf8).write(to: bom, options: .atomic)
        let changed = try await cache.directories(in: bom, context: context, timeout: 2)
        XCTAssertNotEqual(first, changed)
        let totalReads = await reader.calls
        XCTAssertEqual(totalReads, 2)
    }
}

private actor ReceiptDirectoryReader {
    private(set) var calls = 0
    let mutateOnFirstRead: Bool
    init(mutateOnFirstRead: Bool) { self.mutateOnFirstRead = mutateOnFirstRead }
    func read(_ url: URL) throws -> String {
        calls += 1
        let value = try String(contentsOf: url, encoding: .utf8)
        if mutateOnFirstRead && calls == 1 { try Data("modified during parsing".utf8).write(to: url, options: .atomic) }
        return value
    }
}
