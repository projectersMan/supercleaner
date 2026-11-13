import Foundation
import XCTest
@testable import CleanerCore

final class UninstallAssociationBudgetTests: XCTestCase {
    func testAssociatedChecksShareABudgetAndCannotStarveTheSelectedApplication() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        func candidate(_ index: Int, body: Bool = false) -> CleanupCandidate {
            .init(url: body ? home.appendingPathComponent("Applications/Fixture.app")
                    : home.appendingPathComponent("Library/Application Support/org.example.fixture/item-\(index)"),
                displayName: "Fixture", category: body ? .application : .applicationSupport, bytes: 1, risk: .review,
                evidence: [], identity: .init(device: 1, inode: UInt64(index + 1), size: 1, modificationTime: 1, kind: .directory),
                source: .application, lastAccessDate: nil, isActive: false)
        }
        let data = (0..<80).map { candidate($0) }, body = candidate(80, body: true)
        let candidates = data + [body]
        let plan = try PlanBuilder(ruleVersion: "rules-1", protectionPolicy: .init(homeDirectory: home))
            .build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        let fileSystem = BudgetFileSystem(candidates)
        let calls = BudgetCalls()
        let executor = CleanupExecutor(fileSystem: fileSystem, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("quarantine"), currentRuleVersion: "rules-1",
            validateCandidate: { item in
                if item.category != .application {
                    await calls.record()
                    try await Task.sleep(for: .milliseconds(10))
                }
            }, applicationValidationTimeout: 0.1)
        let receipt = await executor.execute(plan: plan)
        let validationCount = await calls.count
        XCTAssertLessThan(validationCount, data.count, "A fresh timeout for every association still accumulates into minutes")
        XCTAssertEqual(receipt.results.count, candidates.count)
        XCTAssertEqual(receipt.results.first { $0.candidateID == body.id }?.status, .succeeded)
        let bodyStillExists = await fileSystem.has(body.url)
        XCTAssertFalse(bodyStillExists, "The selected app must be moved even when remaining associated checks are skipped")
    }
}

private actor BudgetCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor BudgetFileSystem: FileSystemAccess {
    private var files: [URL: FileIdentity]
    init(_ candidates: [CleanupCandidate]) { files = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url, $0.identity) }) }
    func has(_ url: URL) -> Bool { files[url] != nil }
    func identity(at url: URL) throws -> FileIdentity {
        guard let value = files[url] else { throw FileSystemError.missing(url) }; return value
    }
    func children(of url: URL) -> [URL] { [] }
    func fileExists(_ url: URL) -> Bool { files[url] != nil }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) throws {
        guard let identity = files.removeValue(forKey: source) else { throw FileSystemError.missing(source) }
        files[destination] = identity
    }
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
