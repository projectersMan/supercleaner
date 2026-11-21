import CryptoKit
import Foundation
import XCTest
@testable import CleanerCore

final class LicenseStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let deviceID = UUID(uuidString: "88A9BB72-653A-48F9-B0B8-34EE5B421337")!
    private let productID = "com.supercleaner.mac"

    func testFiniteLeaseUsesUnixSecondsAndRetainsSignedBytes() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("{\"licenseID\":\"26D5C634-7DB7-40DC-825B-0D0B69F69743\",\"productID\":\"com.supercleaner.mac\",\"email\":\"buyer@supercleaner.dev\",\"deviceID\":\"88A9BB72-653A-48F9-B0B8-34EE5B421337\",\"issuedAt\":1799999940,\"offlineValidUntil\":1800003600,\"capabilities\":[\"standardScan\",\"agentScan\",\"newCleanup\"]}".utf8)
        let signed = SignedLicense(claimsData: data, signature: try key.signature(for: data))
        let store = try makeStore(key: key, signed: signed)
        try store.require(.newCleanup, now: now)
        XCTAssertEqual(store.claims?.issuedAt, 1_799_999_940)
        XCTAssertEqual(store.claims?.offlineValidUntil, 1_800_003_600)
        XCTAssertTrue(store.isAllowed(.standardScan, now: now))
        XCTAssertTrue(store.isAllowed(.agentScan, now: now))
    }

    func testExpiredLeaseRetainsEverySafetyRightButRequiresOnlineRefresh() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try sign(key: key, issuedAt: 1_799_999_000, offlineValidUntil: 1_799_999_999)
        let store = try makeStore(key: key, signed: signed)
        XCTAssertFalse(store.isAllowed(.newCleanup, now: now))
        XCTAssertThrowsError(try store.require(.newCleanup, now: now)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .offlineLeaseExpired)
        }
        for feature in [CommercialFeature.history, .restore, .removeHelper, .exportReceipts] {
            XCTAssertTrue(store.isAllowed(feature, now: now))
            try store.require(feature, now: now)
        }
    }

    func testMissingLicenseRequiresPurchaseWhileSafetyRightsRemainAvailable() throws {
        let key = Curve25519.Signing.PrivateKey()
        let store = try makeStore(key: key, signed: nil)
        XCTAssertThrowsError(try store.require(.newCleanup, now: now)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .licenseRequired)
        }
        for feature in [CommercialFeature.history, .restore, .removeHelper, .exportReceipts] {
            XCTAssertTrue(store.isAllowed(feature, now: now))
        }
    }

    func testInvalidSignatureIsRejectedBeforeClaimsAreDecoded() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = SignedLicense(claimsData: Data("not JSON".utf8), signature: Data(repeating: 0, count: 64))
        XCTAssertThrowsError(try makeStore(key: key, signed: signed)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .invalidSignature)
        }
    }

    func testTrustedSignatureCannotCrossProductOrDeviceBoundary() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try sign(key: key, issuedAt: 1_799_999_000, offlineValidUntil: 1_800_003_600)
        XCTAssertThrowsError(try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: "other.product", deviceID: deviceID, now: now, lastTrustedTime: nil)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .wrongProduct)
        }
        XCTAssertThrowsError(try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: UUID(), now: now, lastTrustedTime: nil)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .wrongDevice)
        }
    }

    func testFutureIssuedAndUnreasonableLeaseAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let future = try sign(key: key, issuedAt: 1_800_000_001, offlineValidUntil: 1_800_003_600)
        XCTAssertThrowsError(try makeStore(key: key, signed: future)) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .futureIssued)
        }
        for deadline in [Int64(1_799_999_000), 1_840_000_000] {
            let invalid = try sign(key: key, issuedAt: 1_799_999_000, offlineValidUntil: deadline)
            XCTAssertThrowsError(try makeStore(key: key, signed: invalid)) { error in
                XCTAssertEqual(error as? LicenseAuthorizationError, .invalidLease)
            }
        }
    }

    func testClockRollbackIsRejectedAtLoadingAndAtUse() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try sign(key: key, issuedAt: 1_799_999_000, offlineValidUntil: 1_800_003_600)
        XCTAssertThrowsError(try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: now.addingTimeInterval(1))) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .clockRollback)
        }
        let store = try makeStore(key: key, signed: signed)
        XCTAssertFalse(store.isAllowed(.newCleanup, now: now.addingTimeInterval(-1)))
        XCTAssertThrowsError(try store.require(.newCleanup, now: now.addingTimeInterval(-1))) { error in
            XCTAssertEqual(error as? LicenseAuthorizationError, .clockRollback)
        }
        try store.require(.restore, now: now.addingTimeInterval(-1))
    }

    func testSignedButMalformedClaimsAndInvalidPublicKeyAreRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let invalidData = Data("{}".utf8)
        let signed = SignedLicense(claimsData: invalidData, signature: try key.signature(for: invalidData))
        XCTAssertThrowsError(try makeStore(key: key, signed: signed))
        XCTAssertThrowsError(try LicenseStore(publicKey: Data(repeating: 0, count: 32), signedLicense: nil,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil))
    }

    private func makeStore(key: Curve25519.Signing.PrivateKey, signed: SignedLicense?) throws -> LicenseStore {
        try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
    }

    private func sign(key: Curve25519.Signing.PrivateKey, issuedAt: Int64, offlineValidUntil: Int64) throws -> SignedLicense {
        let claims = LicenseClaims(licenseID: UUID(), productID: productID, email: "buyer@supercleaner.dev",
            deviceID: deviceID, issuedAt: issuedAt, offlineValidUntil: offlineValidUntil,
            capabilities: [.standardScan, .agentScan, .newCleanup])
        let data = try JSONEncoder().encode(claims)
        return SignedLicense(claimsData: data, signature: try key.signature(for: data))
    }
}
