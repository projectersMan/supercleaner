import CleanerCore
import CryptoKit
import Foundation

private struct CommercialFixtureStorage: CommercialCredentialStorage {
    let data: Result<Data, Error>
    func read() throws -> Data? { try data.get() }
    func write(_ data: Data) throws {}
}

/// Explicitly injected by existing read-only self-checks. Production construction
/// always uses CommercialAccess.live() and never selects credentials from argv.
enum CommercialLicenseFixture {
    static func make() -> CommercialAccess {
        let setup = Result { try makeCredentials() }
        return CommercialAccess(configuration: setup.map(\.configuration),
            storage: CommercialFixtureStorage(data: setup.map(\.data)))
    }

    static func missingConfiguration() -> CommercialAccess {
        CommercialAccess(configuration: .failure(CommercialConfigurationError.missing),
            storage: CommercialFixtureStorage(data: .success(Data())))
    }

    private static func makeCredentials() throws -> (configuration: CommercialConfiguration, data: Data) {
        let key = Curve25519.Signing.PrivateKey()
        let deviceID = UUID()
        let now = Int64(Date().timeIntervalSince1970)
        let claims = LicenseClaims(licenseID: UUID(), productID: "commercial-fixture", email: "fixture@example.invalid",
            deviceID: deviceID, issuedAt: now - 1, offlineValidUntil: now + 3_600,
            capabilities: [.standardScan, .agentScan, .newCleanup])
        let claimsData = try JSONEncoder().encode(claims)
        let signed = SignedLicense(claimsData: claimsData, signature: try key.signature(for: claimsData))
        let configurationData = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "productID": "commercial-fixture", "apiBaseURL": "https://commerce.supercleaner.dev",
            "licensePublicKey": key.publicKey.rawRepresentation.base64EncodedString()])
        let configuration = try CommercialConfiguration(data: configurationData)
        let state = CommercialCredentialState(deviceID: deviceID, email: "fixture@example.invalid", licenseKey: "fixture-key",
            signedLicense: signed, lastTrustedTime: Date(), pendingOrder: nil)
        return (configuration, try JSONEncoder().encode(state))
    }
}
