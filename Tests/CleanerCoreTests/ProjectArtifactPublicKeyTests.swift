import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class ProjectArtifactPublicKeyTests: XCTestCase {
    private static let publicPEM = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n-----END PUBLIC KEY-----\n"

    func testPublicKeyPEMsAllowArtifactSelectionAndExecution() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let artifact = home.appendingPathComponent("code/Example/.build")
        try write(Self.publicPEM, to: artifact.appendingPathComponent("test-pubkey.pem"))
        try write("-----BEGIN RSA PUBLIC KEY-----\nMAYCAQMCAQM=\n-----END RSA PUBLIC KEY-----\n", to: artifact.appendingPathComponent("rsa.PEM"))
        let context = ScanContext(homeDirectory: home)
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url == artifact }?.candidate)
        XCTAssertTrue(ResourceCleanupListPolicy.isSelectable(candidate))
        XCTAssertFalse(candidate.evidence.contains { $0.code == "deployment-key" })
        try await scanner.validateForExecution(candidate, context: context)
        let plan = try PlanBuilder(ruleVersion: "public-key-test").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: home), quarantineRoot: home.appendingPathComponent("quarantine"),
            currentRuleVersion: "public-key-test", validateCandidate: { try await scanner.validateForExecution($0, context: context) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.disposition, .quarantined)
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.disposition, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.appendingPathComponent("test-pubkey.pem").path))
    }

    func testPrivateMixedMalformedAndCredentialFilesStillProtectArtifacts() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let inputs = [
            ("private.pem", "-----BEGIN PRIVATE KEY-----\nZml4dHVyZQ==\n-----END PRIVATE KEY-----\n"),
            ("mixed.pem", Self.publicPEM + "-----BEGIN PRIVATE KEY-----\nZml4dHVyZQ==\n-----END PRIVATE KEY-----\n"),
            ("invalid.pem", "-----BEGIN PUBLIC KEY-----\nnot base64!\n-----END PUBLIC KEY-----\n"),
            ("empty.pem", "-----BEGIN PUBLIC KEY-----\n-----END PUBLIC KEY-----\n"),
            ("deploy.key", Self.publicPEM), (".env", "TEST_FIXTURE=1"),
            ("large.pem", Self.publicPEM + String(repeating: " ", count: 65_536)),
        ]
        for (index, input) in inputs.enumerated() {
            let project = home.appendingPathComponent("code/Case\(index)")
            try write("// fixture", to: project.appendingPathComponent("Package.swift"))
            try write(input.1, to: project.appendingPathComponent(".build/" + input.0))
        }
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: ScanContext(homeDirectory: home))
        let blocked = report.artifacts.filter { $0.projectURL.lastPathComponent.hasPrefix("Case") }
        XCTAssertEqual(blocked.count, inputs.count)
        XCTAssertTrue(blocked.allSatisfy { !ResourceCleanupListPolicy.isSelectable($0.candidate)
            && $0.candidate.evidence.contains { $0.code == "deployment-key" } })
    }

    func testRecordedSwiftPMCheckoutsDoNotLockBuildButNewPrivateKeyStillRefusesExecution() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let artifact = home.appendingPathComponent("code/Example/.build")
        for scratch in [artifact, artifact.appendingPathComponent("release-scratch")] {
            try FileManager.default.createDirectory(at: scratch.appendingPathComponent("checkouts/Sparkle/.git"), withIntermediateDirectories: true)
            try write(Self.publicPEM, to: scratch.appendingPathComponent("checkouts/Sparkle/Tests/test-pubkey.pem"))
            try workspace(at: scratch, subpath: "Sparkle", state: "sourceControlCheckout")
        }
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let context = ScanContext(homeDirectory: home)
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first { $0.candidate.url == artifact }?.candidate)
        XCTAssertTrue(ResourceCleanupListPolicy.isSelectable(candidate))
        XCTAssertFalse(candidate.evidence.contains { $0.code == "nested-git" || $0.code == "deployment-key" })
        try await scanner.validateForExecution(candidate, context: context)
        try write("-----BEGIN PRIVATE KEY-----\nZml4dHVyZQ==\n-----END PRIVATE KEY-----\n",
            to: artifact.appendingPathComponent("checkouts/Sparkle/deploy.pem"))
        let validation = await Task { try await scanner.validateForExecution(candidate, context: context) }.result
        guard case .failure = validation else { return XCTFail("New private keys must still refuse execution") }
    }

    func testUnrecordedEditedAndUnmanagedRepositoriesRemainProtected() async throws {
        let home = try fixture()
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        for (index, state) in ["missing", "unrecorded", "edited", "manual"].enumerated() {
            let project = home.appendingPathComponent("code/Case\(index)")
            let artifact = project.appendingPathComponent(".build")
            try write("// fixture", to: project.appendingPathComponent("Package.swift"))
            let repository = state == "manual" ? artifact.appendingPathComponent("work/MyRepo") : artifact.appendingPathComponent("checkouts/Sparkle")
            try FileManager.default.createDirectory(at: repository.appendingPathComponent(".git"), withIntermediateDirectories: true)
            if state != "missing" { try workspace(at: artifact, subpath: state == "unrecorded" ? "Different" : "Sparkle",
                state: state == "edited" ? "edited" : "sourceControlCheckout") }
        }
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: ScanContext(homeDirectory: home))
        let blocked = report.artifacts.filter { $0.projectURL.lastPathComponent.hasPrefix("Case") }
        XCTAssertEqual(blocked.count, 4)
        XCTAssertTrue(blocked.allSatisfy { !ResourceCleanupListPolicy.isSelectable($0.candidate)
            && $0.candidate.evidence.contains { $0.code == "nested-git" } })
    }

    private func fixture() throws -> URL {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/project-artifact-public-keys/fixtures/\(UUID())")
        try write("// fixture", to: home.appendingPathComponent("code/Example/Package.swift"))
        try write("output", to: home.appendingPathComponent("code/Example/.build/output"))
        return home
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func workspace(at url: URL, subpath: String, state: String) throws {
        let data: [String: Any] = ["version": 7, "object": ["dependencies": [["subpath": subpath,
            "packageRef": ["kind": "remoteSourceControl"], "state": ["name": state]]]]]
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: data).write(to: url.appendingPathComponent("workspace-state.json"))
    }
}
