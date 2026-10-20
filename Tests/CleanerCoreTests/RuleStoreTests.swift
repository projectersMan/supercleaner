import CryptoKit
import Foundation
import XCTest
@testable import CleanerCore

final class RuleStoreTests: XCTestCase {
    func testRejectsInvalidSignatureAndOnDiskTampering() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let store = RuleStore(directory: root, publicKey: key.publicKey.rawRepresentation)
        let pack = RulePack(version: "1", issuedAt: Date(), rules: [], revokedRuleIDs: [])
        let data = try JSONEncoder().encode(pack)
        try await store.install(update: SignedRuleUpdate(packData: data, signature: try key.signature(for: data)))
        do { try await store.install(update: SignedRuleUpdate(packData: data, signature: Data(repeating: 0, count: 64))); XCTFail("invalid signature accepted") } catch {}
        let currentVersion = try await store.currentVersion()
        XCTAssertEqual(currentVersion, "1")
        let tampered = try JSONEncoder().encode(RulePack(version: "999", issuedAt: Date(), rules: [], revokedRuleIDs: []))
        let stateURL = root.appendingPathComponent("state.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
        state["current"] = try JSONSerialization.jsonObject(with: tampered)
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
        do { _ = try await store.currentVersion(); XCTFail("on-disk tampering accepted") } catch {}
    }
}
