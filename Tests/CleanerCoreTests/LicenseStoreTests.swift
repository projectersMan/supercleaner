import CryptoKit
import Foundation
import XCTest
@testable import CleanerCore

final class LicenseStoreTests: XCTestCase {
    func testExpiredTrialKeepsSafetyRights() throws {
        let key = Curve25519.Signing.PrivateKey(); let now = Date()
        let claims = LicenseClaims(licenseID: UUID(), tier: .trial, issuedAt: now.addingTimeInterval(-100), expiresAt: now.addingTimeInterval(-1), capabilities: [.newCleanup])
        let data = try JSONEncoder().encode(claims)
        let store = LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: SignedLicense(claimsData: data, signature: try key.signature(for: data)))
        XCTAssertFalse(store.isAllowed(.newCleanup, now: now)); XCTAssertTrue(store.isAllowed(.history, now: now)); XCTAssertTrue(store.isAllowed(.restore, now: now))
    }
}
