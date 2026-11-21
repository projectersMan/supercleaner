import CleanerCore
import Foundation

private struct CommercialInteropFixture: Decodable {
    let publicKey: Data
    let productID: String
    let deviceID: UUID
    let signedLicense: SignedLicense
}

func runCommercialInteropContract(path: String) throws {
    let data = try UpdateFileContent.read(URL(fileURLWithPath: path), maximumBytes: 65_536)
    let fixture = try JSONDecoder().decode(CommercialInteropFixture.self, from: data)
    let now = Date()
    let store = try LicenseStore(publicKey: fixture.publicKey, signedLicense: fixture.signedLicense,
        productID: fixture.productID, deviceID: fixture.deviceID, now: now, lastTrustedTime: nil)
    try store.require(.newCleanup, now: now)
    require(store.claims?.deviceID == fixture.deviceID, "service and Swift must share the identical signed device binding")
    print("PASS: Node service Ed25519 lease verified unchanged by Swift CryptoKit")
}
