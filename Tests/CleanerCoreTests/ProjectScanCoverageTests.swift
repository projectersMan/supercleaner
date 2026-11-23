import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class ProjectScanCoverageTests: XCTestCase {
    func testFullScanDoesNotLetOneArtifactExhaustCoverageOfOtherProjectsAndRoots() async throws {
        let home = try fixture()
        try project("code/First", marker: "Package.swift", output: ".build", home: home, files: 20)
        try project("code/Containers/Nested/zflow", marker: "package.json", output: "dist", home: home)
        try project("Other/moleapp", marker: "Package.swift", output: "build", home: home)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code"), home.appendingPathComponent("Other")], maximumDepth: 1, maximumEntries: 1)
        let context = ScanContext(homeDirectory: home, enforcesEntryBudgets: false)
        let report = try await scanner.scan(context: context)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(Set(report.artifacts.map { $0.projectURL.lastPathComponent }), ["First", "zflow", "moleapp"])
        XCTAssertTrue(report.artifacts.allSatisfy { !$0.candidate.evidence.contains { $0.code == "inspection-budget" } })
        for artifact in report.artifacts {
            try await scanner.validateForExecution(artifact.candidate, context: context)
        }
    }

    func testFullScanIgnoresLegacyTimeLimitButStillSupportsCancellation() async throws {
        let home = try fixture()
        try project("code/zflow", marker: "package.json", output: "dist", home: home)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")], timeLimit: 0.01)
        let context = ScanContext(homeDirectory: home, fileSystem: SlowProjectFS())
        let report = try await scanner.scan(context: context)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.artifacts.count, 1)
        let task = Task { try await scanner.scan(context: context) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must remain available") }
        catch is CancellationError {}
    }

    func testDefaultContextAlsoIgnoresLegacyBudgets() async throws {
        let home = try fixture()
        try project("code/zflow", marker: "package.json", output: "dist", home: home)
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")], maximumEntries: 1)
            .scan(context: ScanContext(homeDirectory: home, enforcesEntryBudgets: true))
        XCTAssertTrue(report.isComplete)
        XCTAssertTrue(report.limitations.isEmpty)
        XCTAssertEqual(report.artifacts.count, 1)
    }

    func testRequirementsProjectsAndVerifiedVirtualEnvironmentsAreDiscovered() async throws {
        let home = try fixture()
        try project("code/ImageViewer", marker: "requirements.txt", output: "dist", home: home)
        try project("code/aitone", marker: "requirements.txt", output: ".venv", home: home)
        try write("home = /fixture/python", to: home.appendingPathComponent("code/aitone/.venv/pyvenv.cfg"))
        try project("code/iqalabel", marker: "setup.py", output: "venv", home: home)
        try write("home = /fixture/python", to: home.appendingPathComponent("code/iqalabel/venv/pyvenv.cfg"))
        try write("not a virtual environment", to: home.appendingPathComponent("code/aitone/env/config.txt"))
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
            .scan(context: ScanContext(homeDirectory: home, enforcesEntryBudgets: false))
        XCTAssertEqual(Set(report.artifacts.map { $0.candidate.url.lastPathComponent }), ["dist", ".venv", "venv"])
        XCTAssertEqual(Set(report.artifacts.map { $0.projectURL.lastPathComponent }), ["ImageViewer", "aitone", "iqalabel"])
        for artifact in report.artifacts {
            try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
                .validateForExecution(artifact.candidate, context: ScanContext(homeDirectory: home, enforcesEntryBudgets: false))
        }
    }

    func testUnlimitedInspectionKeepsCredentialAndUserProtectionChecks() async throws {
        let home = try fixture()
        try project("code/Private", marker: "package.json", output: "dist", home: home)
        try write("fixture", to: home.appendingPathComponent("code/Private/dist/credentials.json"))
        let artifact = home.appendingPathComponent("code/Private/dist")
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")], maximumEntries: 1)
        let context = ScanContext(homeDirectory: home, enforcesEntryBudgets: false)
        let report = try await scanner.scan(context: context)
        XCTAssertEqual(report.artifacts.first?.candidate.risk, .blocked)
        do { try await scanner.validateForExecution(try XCTUnwrap(report.artifacts.first?.candidate), context: context); XCTFail("Credentials remain protected") }
        catch is RuleScanError {}
        let protected = try await scanner.scan(context: ScanContext(homeDirectory: home,
            protectionPolicy: ProtectionPolicy(entries: [.init(url: artifact)], homeDirectory: home), enforcesEntryBudgets: false))
        XCTAssertEqual(protected.artifacts.first?.candidate.risk, .blocked)
    }

    func testInstallerContentBudgetCanBeDisabledWithoutLosingCancellation() async throws {
        var limited = LargeFileContentBudget(bytes: 0, entries: 0, time: .zero)
        XCTAssertFalse(limited.take(bytes: 1, entries: 1))
        var unlimited = LargeFileContentBudget(bytes: 0, entries: 0, time: .zero, enforced: false)
        XCTAssertTrue(unlimited.take(bytes: .max, entries: .max))
        XCTAssertFalse(unlimited.limited)
        let task = Task {
            var budget = LargeFileContentBudget(bytes: 0, entries: 0, time: .zero, enforced: false)
            while !Task.isCancelled { await Task.yield() }
            return budget.take(bytes: 1, entries: 1)
        }
        task.cancel()
        let accepted = await task.value
        XCTAssertFalse(accepted)
    }

    func testProjectGitProcessCanReadCompleteOutputAndStillCancel() async throws {
        do {
            _ = try await BoundedProcess.run("/usr/bin/head", arguments: ["-c", "1100000", "/dev/zero"], maximumOutputBytes: 1024)
            XCTFail("Default bounded callers retain their output guard")
        } catch ProcessFailure.outputLimit {}
        let result = try await BoundedProcess.run("/usr/bin/head", arguments: ["-c", "1100000", "/dev/zero"], timeout: nil, maximumOutputBytes: nil)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 1_100_000)
        let task = Task { try await BoundedProcess.run("/bin/sleep", arguments: ["5"], timeout: nil, maximumOutputBytes: nil) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Unbounded Git work must remain cancellable") }
        catch ProcessFailure.cancelled {}
    }

    private func fixture() throws -> URL {
        let home = URL(fileURLWithPath: "/Users/Shared").appendingPathComponent("ProjectCoverage-\(UUID())").standardizedFileURL
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return home
    }
    private func project(_ relative: String, marker: String, output: String, home: URL, files: Int = 1) throws {
        let root = home.appendingPathComponent(relative)
        try write("fixture", to: root.appendingPathComponent(marker))
        for index in 0..<files { try write("output", to: root.appendingPathComponent(output + "/file-\(index)")) }
    }
    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }
}

private struct SlowProjectFS: FileSystemAccess {
    let base = LocalFileSystem()
    func children(of url: URL) async throws -> [URL] {
        try await Task.sleep(nanoseconds: 20_000_000)
        return try await base.children(of: url)
    }
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func isReadable(_ url: URL) async -> Bool { await base.isReadable(url) }
    func isDeletable(_ url: URL) async -> Bool { await base.isDeletable(url) }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func readData(at url: URL, maximumBytes: Int) async throws -> Data { try await base.readData(at: url, maximumBytes: maximumBytes) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func readText(at url: URL, maximumBytes: Int) async throws -> String { try await base.readText(at: url, maximumBytes: maximumBytes) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}
