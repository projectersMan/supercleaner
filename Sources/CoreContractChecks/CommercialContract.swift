import CleanerCore
import CryptoKit
import Foundation

func runCommercialContracts() throws {
    let key = Curve25519.Signing.PrivateKey()
    let now = Date(timeIntervalSince1970: 40_000_000)
    let claims = LicenseClaims(licenseID: UUID(), tier: .trial, issuedAt: now.addingTimeInterval(-10_000), expiresAt: now.addingTimeInterval(-1), capabilities: [.standardScan, .agentScan, .newCleanup])
    let claimsData = try JSONEncoder().encode(claims)
    let licenseStore = LicenseStore(publicKey: key.publicKey.rawRepresentation, signedLicense: SignedLicense(claimsData: claimsData, signature: try key.signature(for: claimsData)))
    require(!licenseStore.isAllowed(.newCleanup, now: now), "expired trial allowed new cleanup")
    for safetyRight in [CommercialFeature.history, .restore, .removeHelper, .exportReceipts] {
        require(licenseStore.isAllowed(safetyRight, now: now), "expired trial blocked safety right: \(safetyRight)")
    }

    try runApplicationUpdatePolicyContracts()
}
