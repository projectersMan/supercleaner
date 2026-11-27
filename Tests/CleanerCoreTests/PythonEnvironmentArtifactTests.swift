import CryptoKit
import Foundation
import XCTest
@testable import CleanerCore

@MainActor final class PythonEnvironmentArtifactTests: XCTestCase {
    private static let certificate = """
-----BEGIN CERTIFICATE-----
MIICiTCCAg+gAwIBAgIQH0evqmIAcFBUTAGem2OZKjAKBggqhkjOPQQDAzCBhTEL
MAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UE
BxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxKzApBgNVBAMT
IkNPTU9ETyBFQ0MgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMDgwMzA2MDAw
MDAwWhcNMzgwMTE4MjM1OTU5WjCBhTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdy
ZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgGA1UEChMRQ09N
T0RPIENBIExpbWl0ZWQxKzApBgNVBAMTIkNPTU9ETyBFQ0MgQ2VydGlmaWNhdGlv
biBBdXRob3JpdHkwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQDR3svdcmCFYX7deSR
FtSrYpn1PlILBs5BAH+X4QokPB0BBO490o0JlwzgdeT6+3eKKvUDYEs2ixYjFq0J
cfRK9ChQtP6IHG4/bC8vCVlbpVsLM5niwz2J+Wos77LTBumjQjBAMB0GA1UdDgQW
BBR1cacZSBm8nZ3qQUfflMRId5nTeTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/
BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjEA7wNbeqy3eApyt4jf/7VGFAkK+qDm
fQjGGoe9GKhzvSbKYAydzpmfz1wPMOG+FDHqAjAU9JM8SaczepBGR7NjfRObTrdv
GDeAU/7dIOA1mjbRxwG55tzd8/8dLDoWV9mSOdY=
-----END CERTIFICATE-----
""" + "\n"
    private static let privateFixture = "-----BEGIN PRIVATE KEY-----\nZml4dHVyZQ==\n-----END PRIVATE KEY-----\n"

    func testInstalledCertificatesAndRecordedSSLTestFixturesAllowVirtualEnvironmentCleanup() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = try project("Example", home: home)
        let site = environment.appendingPathComponent("lib/python3.11/site-packages")
        let bundle = String(repeating: "# Public CA certificate\n" + Self.certificate, count: 90)
        XCTAssertGreaterThan(bundle.utf8.count, 65_536)
        try write(bundle, to: site.appendingPathComponent("certifi/cacert.pem"))
        try write("Certificate:\n    Public certificate display\n" + Self.certificate, to: site.appendingPathComponent("grpc/roots.pem"))
        try records(["grpc/roots.pem"], site: site, distribution: "grpc")
        for (name, text) in [("keycert.pem", Self.privateFixture + Self.certificate), ("nullcert.pem", ""),
                             ("dh512.pem", "-----BEGIN DH PARAMETERS-----\nZml4dHVyZQ==\n-----END DH PARAMETERS-----\n")] {
            try write(text, to: site.appendingPathComponent("future/backports/test/" + name))
        }
        try records(["future/backports/test/keycert.pem", "future/backports/test/nullcert.pem", "future/backports/test/dh512.pem"], site: site, distribution: "future")
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let context = ScanContext(homeDirectory: home)
        let inventory = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(inventory.artifacts.first { $0.candidate.url.path == environment.path }?.candidate)
        XCTAssertTrue(ResourceCleanupListPolicy.isSelectable(candidate))
        XCTAssertFalse(candidate.evidence.contains { $0.code == "deployment-key" })
        try await scanner.validateForExecution(candidate, context: context)
        let plan = try PlanBuilder(ruleVersion: "venv-test").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(pathPolicy: .init(homeDirectory: home), quarantineRoot: home.appendingPathComponent("quarantine"),
            currentRuleVersion: "venv-test", validateCandidate: { try await scanner.validateForExecution($0, context: context) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.disposition, .quarantined)
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.disposition, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: site.appendingPathComponent("future/backports/test/keycert.pem").path))
    }

    func testEditedUnrecordedNonTestAndLinkedPrivateFilesRemainProtected() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        for kind in ["edited", "edited-same-size", "unrecorded", "non-test", "environment-credential", "linked", "outside-venv"] {
            let environment = try project(kind, home: home)
            let site = environment.appendingPathComponent("lib/python3.11/site-packages")
            let relative = kind == "non-test" ? "future/user.pem" : kind == "environment-credential" ? "future/test/.env" : "future/test/user.pem"
            let file = site.appendingPathComponent(relative)
            try write(Self.privateFixture, to: file)
            if kind != "unrecorded" { try records([relative], site: site, distribution: "future") }
            if kind == "edited" { try write(Self.privateFixture + "# changed after installation\n", to: file) }
            if kind == "edited-same-size" { try write(Self.privateFixture.replacingOccurrences(of: "Zml4", with: "Yml4"), to: file) }
            if kind == "linked" {
                let target = home.appendingPathComponent("private-fixture.pem")
                try write(Self.privateFixture, to: target)
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            }
            if kind == "outside-venv" {
                try FileManager.default.moveItem(at: environment, to: environment.deletingLastPathComponent().appendingPathComponent("dist"))
            }
        }
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: .init(homeDirectory: home))
        XCTAssertEqual(report.artifacts.count, 7)
        XCTAssertTrue(report.artifacts.allSatisfy { !ResourceCleanupListPolicy.isSelectable($0.candidate)
            && $0.candidate.evidence.contains { $0.code == "deployment-key" } })
    }

    func testNewPrivateKeyAfterScanStillRefusesExecution() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = try project("Example", home: home)
        try write(Self.certificate, to: environment.appendingPathComponent("lib/python3.11/site-packages/certifi/cacert.pem"))
        let scanner = ProjectArtifactScanner(roots: [home.appendingPathComponent("code")])
        let context = ScanContext(homeDirectory: home)
        let report = try await scanner.scan(context: context)
        let candidate = try XCTUnwrap(report.artifacts.first?.candidate)
        XCTAssertTrue(ResourceCleanupListPolicy.isSelectable(candidate))
        try write(Self.privateFixture, to: environment.appendingPathComponent("lib/python3.11/site-packages/future/test/new-private.pem"))
        do { try await scanner.validateForExecution(candidate, context: context); XCTFail("An unrecorded private key must block cleanup") }
        catch is RuleScanError {}
    }

    func testMalformedAndMixedCertificateBundlesStayProtectedWithoutInstallationProof() async throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        for (name, value) in [("mixed", Self.certificate + Self.privateFixture),
                              ("invalid", "-----BEGIN CERTIFICATE-----\nZml4dHVyZQ==\n-----END CERTIFICATE-----\n"),
                              ("extra", "USER_SECRET=fixture\n" + Self.certificate)] {
            let environment = try project(name, home: home)
            try write(value, to: environment.appendingPathComponent("certificate.pem"))
        }
        let report = try await ProjectArtifactScanner(roots: [home.appendingPathComponent("code")]).scan(context: .init(homeDirectory: home))
        XCTAssertEqual(report.artifacts.count, 3)
        XCTAssertTrue(report.artifacts.allSatisfy { $0.candidate.risk == .blocked })
    }

    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("temporary/python-environment-artifacts/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func project(_ name: String, home: URL) throws -> URL {
        let root = home.appendingPathComponent("code/" + name)
        try write("fixture", to: root.appendingPathComponent("requirements.txt"))
        let environment = root.appendingPathComponent(".venv")
        try write("home = /fixture/python\n", to: environment.appendingPathComponent("pyvenv.cfg"))
        return environment
    }
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func records(_ paths: [String], site: URL, distribution: String) throws {
        let lines = try paths.map { relative -> String in
            let data = try Data(contentsOf: site.appendingPathComponent(relative))
            let hash = Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "\(relative),sha256=\(hash),\(data.count)"
        }
        try write(lines.joined(separator: "\n") + "\n", to: site.appendingPathComponent(distribution + "-1.0.dist-info/RECORD"))
    }
}
