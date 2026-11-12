import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class DuplicateLargeFileTests: XCTestCase {
    func testScanRecommendsOneCopyOfAnyFormatAndACompleteSiblingZIP() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let a = try write(Data(repeating: 42, count: 8_192), to: "a.rip", in: root)
        let b = try write(Data(repeating: 42, count: 8_192), to: "b.other", in: root)
        let c = try write(Data(repeating: 42, count: 8_192), to: "c.rar", in: root)
        _ = try write(Data(repeating: 43, count: 8_192), to: "different.rip", in: root)
        _ = try write(Data(repeating: 7, count: 32_768), to: "Extracted elsewhere/payload.bin", in: root)
        let zip = try makeZIP("Download.zip", inputs: ["Extracted elsewhere"], in: root)

        let recursive = try await scan(root)
        let indexed = try await scan(root, index: DuplicateFixtureIndex(urls: recursive.diskUsageTree.largeFiles.map(\.url)))
        XCTAssertEqual(indexed.diskUsageTree.analysisState, .indexedResults)
        for report in [recursive, indexed] {
            let selected = DefaultCleanupPolicy().selection(for: report).largeFiles
            XCTAssertEqual(Set(selected.map(\.url)), [b, zip])
            XCTAssertEqual(selected.first { $0.url == b }?.largeFileProof?.retained.first?.url, a)
            XCTAssertTrue(report.largeFileCandidates.contains { $0.url == c })
            XCTAssertTrue(selected.allSatisfy { $0.defaultSelection == true })
        }
    }

    func testZIPUsesFolderTotalAndStillVerifiesSmallMembers() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        _ = try write(Data(repeating: 11, count: 32_768), to: "Extra/payload.bin", in: root)
        let extra = try makeZIP("extra.zip", inputs: ["Extra"], in: root)
        _ = try write(Data([1]), to: "Extra/local-only.txt", in: root)
        _ = try write(Data(repeating: 12, count: 32_768), to: "Mixed/payload.bin", in: root)
        let small = try write(Data([2]), to: "Mixed/small.txt", in: root)
        let empty = try write(Data(), to: "Mixed/empty.txt", in: root)
        let mixed = try makeZIP("mixed.zip", inputs: ["Mixed"], in: root)
        _ = try write(Data(repeating: 13, count: 32_768), to: "Changed/payload.bin", in: root)
        let changed = try write(Data([3]), to: "Changed/small.txt", in: root)
        let changedZIP = try makeZIP("changed.zip", inputs: ["Changed"], in: root)
        try Data([4]).write(to: changed)
        let storedBytes = Data(repeating: 14, count: 32_768)
        _ = try write(storedBytes, to: "Stored/payload.bin", in: root)
        let stored = try makeZIP("stored.zip", inputs: ["Stored"], in: root, compression: "-0")
        let storedIdentity = try await LocalFileSystem().identity(at: stored)
        XCTAssertGreaterThan(storedIdentity.size, UInt64(storedBytes.count))

        let report = try await scan(root)
        let recommendations = DefaultCleanupPolicy().selection(for: report).largeFiles
        XCTAssertFalse(recommendations.contains { [extra, changedZIP, stored].contains($0.url) })
        let recommendation = try XCTUnwrap(recommendations.first { $0.url == mixed })
        XCTAssertEqual(recommendation.largeFileProof?.reason, .extractedZIP)
        let retainedURLs = Set(recommendation.largeFileProof?.retained.map(\.url) ?? [])
        XCTAssertTrue(retainedURLs.isSuperset(of: [small, empty]))
    }

    func testOverlappingZIPAndCopyEvidenceKeepsOneRecommendationPerGroup() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let data = Data(repeating: 31, count: 32_768)
        let copy = try write(data, to: "a-copy.bin", in: root)
        let kept = try write(data, to: "z-extracted/payload.bin", in: root)
        let zip = try makeZIP("a.zip", inputs: ["z-extracted"], in: root)
        try FileManager.default.copyItem(at: zip, to: root.appendingPathComponent("b.zip"))

        let report = try await scan(root)
        let recommendations = DefaultCleanupPolicy().selection(for: report).largeFiles
        XCTAssertEqual(Set(recommendations.map(\.url)), [copy, zip])
        XCTAssertEqual(recommendations.first { $0.url == copy }?.largeFileProof?.retained.first?.url, kept)
    }

    func testLargeInstallerDefaultsKeepVerifiedCopiesAndExcludeBlockedFiles() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let dmg = try write(Data(repeating: 51, count: 8_192), to: "setup.DMG", in: root)
        let pkg = try write(Data(repeating: 52, count: 8_192), to: "setup.pkg", in: root)
        let duplicate = Data(repeating: 53, count: 8_192)
        let kept = try write(duplicate, to: "a-copy.dmg", in: root)
        let copy = try write(duplicate, to: "b-copy.dmg", in: root)
        let third = try write(duplicate, to: "c-copy.dmg", in: root)
        let protected = try write(Data(repeating: 54, count: 8_192), to: "protected.iso", in: root)
        let active = try write(Data(repeating: 55, count: 8_192), to: "active.xip", in: root)
        let small = try write(Data([1]), to: "small.mpkg", in: root)
        let payload = try write(Data(repeating: 56, count: 8_192), to: "Extracted/package.pkg", in: root)
        let extracted = try makeZIP("extracted.zip", inputs: ["Extracted"], in: root)
        let ordinary = try write(Data(repeating: 57, count: 8_192), to: "ordinary.txt", in: root)
        let archive = try makeZIP("ordinary.zip", inputs: ["ordinary.txt"], in: root)
        let context = ScanContext(homeDirectory: root.deletingLastPathComponent(), activePaths: [active],
            protectionPolicy: ProtectionPolicy(entries: [ProtectedPath(url: protected)], homeDirectory: root.deletingLastPathComponent()))
        let recursive = try await scan(context)
        let indexed = try await scan(context, index: DuplicateFixtureIndex(urls: recursive.diskUsageTree.largeFiles.map(\.url)))
        XCTAssertEqual(indexed.diskUsageTree.analysisState, .indexedResults)
        for report in [recursive, indexed] {
            let defaults = DefaultCleanupPolicy().selection(for: report)
            XCTAssertEqual(Set(defaults.largeFiles.map(\.url)), [dmg, pkg, copy, extracted])
            XCTAssertTrue(defaults.systemCleanup.isEmpty)
            XCTAssertTrue(Set(report.largeFileCandidates.map(\.url)).isSuperset(of: [kept, third, protected, active, payload, ordinary, archive]))
            XCTAssertFalse(report.largeFileCandidates.contains { $0.url == small })
            XCTAssertNoThrow(try PlanBuilder().build(candidates: report.largeFileCandidates, selectedIDs: Set(defaults.largeFiles.map(\.id))))
        }
        let optOut = try await scan(context, preselectLargeFileInstallers: false)
        XCTAssertEqual(Set(DefaultCleanupPolicy().selection(for: optOut).largeFiles.map(\.url)), [copy, extracted])
        for url in [dmg, pkg] {
            let installer = try XCTUnwrap(optOut.largeFileCandidates.first { $0.url == url })
            XCTAssertTrue(installer.risk.isSelectable)
            XCTAssertEqual(installer.largeFileRecommendation?.code, "installer-type")
        }
    }

    func testVerifiedZIPCanBeQuarantinedAndRestoredWhileKeepingExtractedFiles() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let payload = try write(Data(repeating: 55, count: 32_768), to: "Payload/file.bin", in: root)
        let zip = try makeZIP("backup.zip", inputs: ["Payload"], in: root)
        let report = try await scan(root)
        let candidate = try XCTUnwrap(DefaultCleanupPolicy().selection(for: report).largeFiles.first { $0.url == zip })
        let builder = PlanBuilder()
        let plan = try builder.build(candidates: [candidate], selectedIDs: [candidate.id])
        let decoded = try JSONDecoder().decode(CleanupPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.selectedItems.first?.candidate.largeFileProof, candidate.largeFileProof)
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: root.deletingLastPathComponent()),
            quarantineRoot: root.appendingPathComponent("Quarantine"), currentRuleVersion: builder.ruleVersion)
        let receipt = await executor.execute(plan: decoded)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.path))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
    }

    func testExecutionSkipsCopyWhenRetainedFileChangesAndRejectsRemovingBoth() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let a = try write(Data(repeating: 42, count: 8_192), to: "a.bin", in: root)
        let b = try write(Data(repeating: 42, count: 8_192), to: "b.bin", in: root)
        let report = try await scan(root)
        let selected = try XCTUnwrap(report.largeFileCandidates.first { $0.url == b && $0.largeFileProof != nil })
        let retained = try XCTUnwrap(report.largeFileCandidates.first { $0.url == a })
        let builder = PlanBuilder()
        XCTAssertThrowsError(try builder.build(candidates: [selected, retained], selectedIDs: [selected.id, retained.id]))
        let plan = try builder.build(candidates: [selected], selectedIDs: [selected.id])
        try Data(repeating: 43, count: 8_192).write(to: a)
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: root.deletingLastPathComponent()),
            quarantineRoot: root.appendingPathComponent("Quarantine"), currentRuleVersion: builder.ruleVersion)
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .skippedIdentityChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testRuntimeCopiesAreManualOnlyInBothScanPaths() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        let paths = [
            "miniconda3/envs/py312/lib/python3.12/site-packages/torch/libtorch_cpu.dylib",
            "miniconda3/envs/py310/lib/python3.10/site-packages/torch/libtorch_cpu.dylib",
            "Library/Android/sdk/ndk/bin/clang++",
            "Downloads/project/.venv/lib/runtime.dat",
            "Documents/custom-env/weights.dat",
            "Downloads/tool.app/Contents/Resources/data.dat",
        ]
        let files = try paths.map { try write(Data(repeating: 71, count: 8192), to: $0, in: home) }
        _ = try write(Data(), to: "Documents/custom-env/pyvenv.cfg", in: home)
        for index: any LargeFileMetadataIndexing in [UnavailableDuplicateFixtureIndex(), DuplicateFixtureIndex(urls: files)] {
            let report = try await scan(ScanContext(homeDirectory: home), index: index)
            let candidates = report.largeFileCandidates.filter { files.contains($0.url) }
            XCTAssertFalse(candidates.isEmpty)
            XCTAssertTrue(candidates.allSatisfy { $0.risk.isSelectable && $0.requiresExplicitSelection == true && $0.largeFileProof == nil })
            XCTAssertTrue(DefaultCleanupPolicy().selection(for: report).largeFiles.isEmpty)
            for candidate in candidates {
                XCTAssertNoThrow(try PlanBuilder().build(candidates: candidates, selectedIDs: [candidate.id]))
            }
        }
    }

    func testExecutionAllowsExplicitlySelectedRuntimeFile() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        let file = try write(Data(repeating: 1, count: 8192), to: "miniconda3/lib/runtime.dat", in: home)
        let identity = try await LocalFileSystem().identity(at: file)
        let candidate = CleanupCandidate(url: file, displayName: "runtime.dat", category: .largeFile,
            bytes: identity.size, risk: .review, evidence: [], identity: identity, source: .diskAnalysis,
            lastAccessDate: nil, isActive: false)
        let builder = PlanBuilder()
        let plan = try builder.build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: builder.ruleVersion)
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testScopeAllowsPersonalFoldersButRejectsSymlinkEscapeAndExecutables() throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        let scope = LargeFileCleanupScope(homeDirectory: home)
        for folder in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"] {
            let file = try write(Data([1]), to: "\(folder)/personal/archive.zip", in: home)
            XCTAssertTrue(scope.allows(file), file.path)
        }
        let runtime = try write(Data([1]), to: "miniconda3/runtime.dat", in: home)
        let link = root.appendingPathComponent("linked.zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: runtime)
        XCTAssertFalse(scope.allows(link))
        let executable = try write(Data([1]), to: "Downloads/compiler", in: home)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertFalse(scope.allows(executable))
        XCTAssertFalse(scope.allows(home.appendingPathComponent("Downloads-old/archive.zip")))
        XCTAssertFalse(scope.allows(home.appendingPathComponent("archive.zip")))
    }

    func testProjectBuildInstallersArePreselectedWithoutSelectingProjectData() async throws {
        let root = try makeFixtureDirectory(); defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        _ = try write(Data(), to: "code/project/Package.swift", in: home)
        let dmg = try write(Data(repeating: 42, count: 8192), to: "code/project/build/SuperCleaner.dmg", in: home)
        let data = try write(Data(repeating: 43, count: 8192), to: "code/project/build/data.bin", in: home)
        let runtime = try write(Data(repeating: 44, count: 8192), to: "code/project/node_modules/runtime.dmg", in: home)
        let report = try await scan(ScanContext(homeDirectory: home), index: DuplicateFixtureIndex(urls: [dmg, data, runtime]))
        XCTAssertEqual(Set(DefaultCleanupPolicy().selection(for: report).largeFiles.map(\.url)), [dmg])
        XCTAssertEqual(report.largeFileCandidates.first { $0.url == dmg }?.largeFileRecommendation?.code, "installer-type")
    }

    func testProjectDataIsManualOnlyAndCanBeQuarantinedAndRestored() async throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        _ = try write(Data(), to: "code/aitone/.git/HEAD", in: home)
        _ = try write(Data(), to: "code/aitone/pyproject.toml", in: home)
        let dataFiles = try ["hdr.exr", "sdr-reference.npz", "copy.npz"].map {
            try write(Data(repeating: 42, count: 8192), to: "code/aitone/dataoutput/experiments/\($0)", in: home)
        }
        let runtime = try write(Data(repeating: 42, count: 8192),
            to: "CascadeProjects/VLM2Business/venv/lib/python3.13/site-packages/torch/lib/libtorch_cpu.dylib", in: home)
        let report = try await scan(ScanContext(homeDirectory: home), index: DuplicateFixtureIndex(urls: dataFiles + [runtime]))
        let candidates = report.largeFileCandidates.filter { dataFiles.contains($0.url) }
        XCTAssertEqual(candidates.count, 3)
        XCTAssertTrue(candidates.allSatisfy { $0.risk.isSelectable && $0.requiresExplicitSelection == true })
        XCTAssertTrue(candidates.allSatisfy { $0.largeFileProof == nil && $0.defaultSelection != true })
        XCTAssertTrue(DefaultCleanupPolicy().selection(for: report).largeFiles.isEmpty)
        XCTAssertEqual(report.largeFileCandidates.first { $0.url == runtime }?.risk, .review)
        let builder = PlanBuilder(protectionPolicy: .init(homeDirectory: home))
        let plan = try builder.build(candidates: candidates, selectedIDs: Set(candidates.map(\.id)))
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: builder.ruleVersion)
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.count, 3)
        XCTAssertTrue(receipt.results.allSatisfy { $0.status == .succeeded })
        let restored = await executor.restore(receipt: receipt)
        XCTAssertTrue(restored.results.allSatisfy { $0.status == .restored })
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtime.path))
    }

    func testManualScopeAllowsCustomDirectoriesButRejectsHomeEscape() throws {
        let root = try makeFixtureDirectory()
        defer { removeFixtureDirectory(root) }
        let home = root.deletingLastPathComponent()
        let scope = LargeFileCleanupScope(homeDirectory: home)
        let runtime = try write(Data([1]), to: "tools/custom-python/runtime.dat", in: home)
        _ = try write(Data(), to: "tools/custom-python/pyvenv.cfg", in: home)
        let link = root.appendingPathComponent("linked.dat")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: runtime)
        for file in [runtime, link, home.appendingPathComponent(".ssh/key.dat"),
                     home.appendingPathComponent("Library/data.dat"), home.appendingPathComponent("code/project/.git/objects/data") ] {
            XCTAssertTrue(scope.allows(file, forManualSelection: true), file.path)
        }
        let data = try write(Data([1]), to: "datasets/experiment/result.npz", in: home)
        XCTAssertTrue(scope.allows(data, forManualSelection: true))
        XCTAssertFalse(scope.allows(data))
        let outside = home.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).dat")
        try Data([1]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let escape = root.appendingPathComponent("escape.dat")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        XCTAssertFalse(scope.allows(escape, forManualSelection: true))
        XCTAssertThrowsError(try ProtectionPolicy(homeDirectory: home).validate(home.appendingPathComponent(".ssh/key.dat")))
    }

    private func scan(_ root: URL, index: any LargeFileMetadataIndexing = UnavailableDuplicateFixtureIndex()) async throws -> SystemScanReport {
        try await scan(ScanContext(homeDirectory: root.deletingLastPathComponent()), index: index)
    }

    private func scan(_ context: ScanContext, index: any LargeFileMetadataIndexing = UnavailableDuplicateFixtureIndex(),
                      preselectLargeFileInstallers: Bool = true) async throws -> SystemScanReport {
        let coordinator = SystemScanCoordinator(diskUsageScanner: DiskUsageScanner(minimumFileBytes: 128),
            largeFileIndex: index)
        let report = await coordinator.scan(context: context, modules: [.largeFiles],
            preselectLargeFileInstallers: preselectLargeFileInstallers)
        return try XCTUnwrap(report)
    }

    private func makeFixtureDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".duplicate-fixture-\(UUID().uuidString)/Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeFixtureDirectory(_ root: URL) {
        XCTAssertNoThrow(try FileManager.default.removeItem(at: root.deletingLastPathComponent()))
    }

    private func write(_ data: Data, to path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func makeZIP(_ name: String, inputs: [String], in root: URL, compression: String = "-6") throws -> URL {
        let zip = root.appendingPathComponent(name)
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = [compression, "-q", "-X", "-r", zip.path] + inputs
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }
}

private struct UnavailableDuplicateFixtureIndex: LargeFileMetadataIndexing {
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] {
        throw LargeFileMetadataIndexError.queryUnavailable
    }
}

private struct DuplicateFixtureIndex: LargeFileMetadataIndexing {
    let urls: [URL]
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] { urls }
}
