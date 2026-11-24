import XCTest
@testable import CleanerCore

final class ApplicationCleanupExecutionMetadataTests: XCTestCase {
    func testDeeplyEmbeddedComponentPassesBatchAndImmediateExecutionValidation() async throws {
        let fixture = try await fixture()
        let shallow = try XCTUnwrap(BundleApplicationMetadataProvider().metadata(for: fixture.app))
        XCTAssertFalse(shallow.associatedBundleIdentifiers?.contains(Self.componentID) == true)
        let runtime = CleanupRuntime(home: fixture.home)
        try await runtime.validateForExecution(fixture.candidate)
        let batch = try await runtime.prepareExecutionValidationBatch(candidates: [fixture.candidate])
        XCTAssertEqual(batch.results[fixture.candidate.id], .valid)
        try await runtime.validateImmediatelyBeforeMove(fixture.candidate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.candidate.url.path), "Validation must not delete user content")
    }

    func testRemovedComponentDeclarationDoesNotKeepItsOldAuthority() async throws {
        let fixture = try await fixture()
        let batch = try await CleanupRuntime(home: fixture.home).prepareExecutionValidationBatch(candidates: [fixture.candidate])
        XCTAssertEqual(batch.results[fixture.candidate.id], .valid)
        try FileManager.default.removeItem(at: fixture.component)
        await assertRefused(fixture)
    }

    func testNewSensitiveFileStillBlocksARecognizedComponentCache() async throws {
        let fixture = try await fixture()
        try Data("fixture-secret".utf8).write(to: fixture.candidate.url.appendingPathComponent("auth.json"))
        await assertRefused(fixture)
    }

    func testUnrelatedComponentCannotUseAnotherApplicationsOwnership() async throws {
        let fixture = try await fixture(declared: "org.example.other.component", claimed: Self.componentID)
        await assertRefused(fixture)
    }

    func testIncompleteCurrentDeclarationsDoNotAuthorizeTheFallback() async throws {
        let fixture = try await fixture()
        let external = fixture.home.appendingPathComponent("External.app")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.app.appendingPathComponent("Contents/Resources/External.app"), withDestinationURL: external)
        let metadata = try XCTUnwrap(BundleApplicationMetadataProvider(includeSharedDeclarations: true).metadata(for: fixture.app))
        XCTAssertEqual(metadata.applicationGroupsComplete, false)
        await assertRefused(fixture)
    }

    private static let componentID = "org.example.independent.component"
    private struct Fixture {
        let home: URL
        let app: URL
        let component: URL
        let candidate: CleanupCandidate
    }

    private func fixture(declared: String = componentID, claimed: String = componentID) async throws -> Fixture {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/application-metadata-fixture-\(UUID())")
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/Main.app")
        let component = app.appendingPathComponent("Contents/Resources/Services/Component.app")
        try bundle(component, identifier: declared)
        try bundle(app, identifier: "org.example.main")
        let cache = home.appendingPathComponent("Library/Caches/\(claimed)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("regenerable cache".utf8).write(to: cache.appendingPathComponent("cache.bin"))
        let metadata = try XCTUnwrap(BundleApplicationMetadataProvider(includeSharedDeclarations: true).metadata(for: app))
        XCTAssertEqual(metadata.applicationGroupsComplete, true)
        let application = InstalledApplication(bundleURL: app, bundleIdentifier: metadata.bundleIdentifier,
            name: metadata.name, version: metadata.version, isRunning: false, isSystem: false,
            teamIdentifier: metadata.teamIdentifier, applicationGroups: metadata.applicationGroups,
            associatedBundleIdentifiers: Array(Set((metadata.associatedBundleIdentifiers ?? []) + [claimed])),
            applicationGroupsComplete: metadata.applicationGroupsComplete)
        let scanner = ApplicationCleanupScanner()
        let context = ScanContext(homeDirectory: home)
        let discovery = await scanner.discover(applications: [application], context: context)
        let scanned = try await scanner.scan(discovery: discovery, context: context)
        let candidate = try XCTUnwrap(scanned.candidates.first { $0.url.standardizedFileURL.path == cache.standardizedFileURL.path }, "targets=\(discovery.targets.map { $0.url.path }) failures=\(scanned.failures)")
        XCTAssertEqual(candidate.risk, .review)
        return Fixture(home: home, app: app, component: component, candidate: candidate)
    }

    private func assertRefused(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async {
        let runtime = CleanupRuntime(home: fixture.home)
        do {
            try await runtime.validateImmediatelyBeforeMove(fixture.candidate)
            XCTFail("Changed or unknown ownership and sensitive content must still refuse execution", file: file, line: line)
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.candidate.url.path), file: file, line: line)
    }

    private func bundle(_ url: URL, identifier: String) throws {
        let binary = url.appendingPathComponent("Contents/MacOS/Main")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Main", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", url.path]
        let output = Pipe(); sign.standardError = output
        try sign.run(); sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
