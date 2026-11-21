import CleanerCore
import CryptoKit
import Foundation

func runCommercialContracts() throws {
    let key = Curve25519.Signing.PrivateKey()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let deviceID = UUID(uuidString: "88A9BB72-653A-48F9-B0B8-34EE5B421337")!
    let productID = "com.supercleaner.mac"
    // Literal wire JSON verifies Unix seconds and signature over the original bytes.
    let rawClaims = Data("{\"licenseID\":\"26D5C634-7DB7-40DC-825B-0D0B69F69743\",\"productID\":\"com.supercleaner.mac\",\"email\":\"buyer@supercleaner.dev\",\"deviceID\":\"88A9BB72-653A-48F9-B0B8-34EE5B421337\",\"issuedAt\":1799999940,\"offlineValidUntil\":1800003600,\"capabilities\":[\"standardScan\",\"agentScan\",\"newCleanup\"]}".utf8)
    let signed = SignedLicense(claimsData: rawClaims, signature: try key.signature(for: rawClaims))
    let store = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
        productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
    for feature in [CommercialFeature.standardScan, .agentScan, .newCleanup] {
        try store.require(feature, now: now)
        require(store.isAllowed(feature, now: now), "valid offline lease denied paid capability")
    }
    require(store.claims?.issuedAt == 1_799_999_940, "license timestamps must be Unix seconds")
    try expectLicenseFailure(.offlineLeaseExpired) {
        try store.require(.newCleanup, now: now.addingTimeInterval(3_600))
    }
    try expectLicenseFailure(.clockRollback) {
        try store.require(.newCleanup, now: now.addingTimeInterval(-1))
    }
    let missing = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: nil,
        productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
    try expectLicenseFailure(.licenseRequired) { try missing.require(.newCleanup, now: now) }
    for safetyRight in [CommercialFeature.history, .restore, .removeHelper, .exportReceipts] {
        try missing.require(safetyRight, now: now)
        try store.require(safetyRight, now: now.addingTimeInterval(4_000))
        try store.require(safetyRight, now: now.addingTimeInterval(-1))
    }
    try expectLicenseFailure(.wrongProduct) {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: "another.product", deviceID: deviceID, now: now, lastTrustedTime: nil)
    }
    try expectLicenseFailure(.wrongDevice) {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: UUID(), now: now, lastTrustedTime: nil)
    }
    try expectLicenseFailure(.clockRollback) {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: now.addingTimeInterval(1))
    }
    try expectLicenseFailure(.futureIssued) {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: signed,
            productID: productID, deviceID: deviceID, now: now.addingTimeInterval(-61), lastTrustedTime: nil)
    }
    try expectLicenseFailure(.invalidPublicKey) {
        _ = try LicenseStore(publicKey: Data(repeating: 0, count: 32), signedLicense: nil,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
    }
    // Malformed JSON must not be decoded before its signature has been verified.
    let forged = SignedLicense(claimsData: Data("not JSON".utf8), signature: Data(repeating: 0, count: 64))
    try expectLicenseFailure(.invalidSignature) {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: forged,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
    }
    for deadline in [Int64(1_799_999_940), 1_840_000_000] {
        let claims = LicenseClaims(licenseID: UUID(), productID: productID, email: "buyer@supercleaner.dev",
            deviceID: deviceID, issuedAt: 1_799_999_940, offlineValidUntil: deadline, capabilities: [.newCleanup])
        let data = try JSONEncoder().encode(claims)
        let invalid = SignedLicense(claimsData: data, signature: try key.signature(for: data))
        try expectLicenseFailure(.invalidLease) {
            _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: invalid,
                productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
        }
    }
    let malformed = Data("{}".utf8)
    let malformedSigned = SignedLicense(claimsData: malformed, signature: try key.signature(for: malformed))
    do {
        _ = try LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: malformedSigned,
            productID: productID, deviceID: deviceID, now: now, lastTrustedTime: nil)
        require(false, "signed malformed claims were accepted")
    } catch is DecodingError {
        // Signature is valid but required claims are absent.
    }
    try runCommercialConfigurationContracts(publicKey: key.publicKey.rawRepresentation)
    try runApplicationUpdatePolicyContracts()
    print("PASS: finite offline leases, signed wire bytes, product/device binding, clock rollback and safety rights")
}

private func expectLicenseFailure(_ expected: LicenseAuthorizationError, operation: () throws -> Void) throws {
    do {
        try operation()
        require(false, "license boundary accepted an invalid request: \(expected)")
    } catch let error as LicenseAuthorizationError {
        require(error == expected, "license boundary returned \(error), expected \(expected)")
    }
}

private func runCommercialConfigurationContracts(publicKey: Data) throws {
    let fields: [String: Any] = ["schemaVersion": 1, "productID": "com.supercleaner.mac",
        "apiBaseURL": "https://license.supercleaner.dev", "licensePublicKey": publicKey.base64EncodedString()]
    let configuration = try CommercialConfiguration(data: JSONSerialization.data(withJSONObject: fields))
    require(configuration.licensePublicKey == publicKey && configuration.schemaVersion == 1,
        "valid public commercial configuration rejected")
    for name in ["schemaVersion", "productID", "apiBaseURL", "licensePublicKey"] {
        var missing = fields
        missing.removeValue(forKey: name)
        try expectConfigurationFailure(missing)
    }
    var unknown = fields
    unknown["licensePrivateKey"] = "must-never-ship"
    try expectConfigurationFailure(unknown)
    for invalidURL in ["http://license.supercleaner.dev", "https://example.com", "https://localhost",
        "https://commerce.supercleaner.test", "https://commerce.supercleaner.example",
        "https://user:secret@license.supercleaner.dev", "https://license.supercleaner.dev?token=secret"] {
        var invalid = fields
        invalid["apiBaseURL"] = invalidURL
        try expectConfigurationFailure(invalid)
    }
    for invalidKey in ["", "REPLACE_ME", Data(repeating: 0, count: 32).base64EncodedString()] {
        var invalid = fields
        invalid["licensePublicKey"] = invalidKey
        try expectConfigurationFailure(invalid)
    }
    print("PASS: strict required commercial configuration, HTTPS and public key validation")
}

private func expectConfigurationFailure(_ fields: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: fields)
    do {
        _ = try CommercialConfiguration(data: data)
        require(false, "commercial configuration accepted missing, unknown or insecure fields")
    } catch is CommercialConfigurationError {
        // All configuration failures remain explicit and actionable.
    } catch is DecodingError {
        // Required field/type failures are explicit decoder failures.
    }
}
