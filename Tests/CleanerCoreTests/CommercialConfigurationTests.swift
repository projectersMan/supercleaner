import CryptoKit
import Foundation
import XCTest
@testable import CleanerCore

final class CommercialConfigurationTests: XCTestCase {
    func testCompletePublicConfigurationDecodesAndPrivateUnknownFieldsFail() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = try configurationData(key: key.publicKey.rawRepresentation)
        let config = try CommercialConfiguration(data: data)
        XCTAssertEqual(config.productID, "com.supercleaner.mac")
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://license.supercleaner.dev")
        XCTAssertEqual(config.licensePublicKey, key.publicKey.rawRepresentation)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["licensePrivateKey"] = "secret"
        XCTAssertThrowsError(try CommercialConfiguration(data: JSONSerialization.data(withJSONObject: fields)))
        fields.removeValue(forKey: "licensePrivateKey")
        fields.removeValue(forKey: "productID")
        XCTAssertThrowsError(try CommercialConfiguration(data: JSONSerialization.data(withJSONObject: fields)))
    }

    func testInsecurePlaceholderAndCredentialURLsFail() throws {
        let key = Curve25519.Signing.PrivateKey()
        for url in ["http://license.supercleaner.dev", "https://example.com", "https://localhost",
            "https://commerce.supercleaner.test", "https://commerce.supercleaner.example",
            "https://user:secret@license.supercleaner.dev", "https://license.supercleaner.dev?token=secret"] {
            let data = try configurationData(key: key.publicKey.rawRepresentation, url: url)
            XCTAssertThrowsError(try CommercialConfiguration(data: data), url)
        }
        XCTAssertThrowsError(try CommercialConfiguration(data: configurationData(key: Data(repeating: 0, count: 32))))
    }

    private func configurationData(key: Data, url: String = "https://license.supercleaner.dev") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "productID": "com.supercleaner.mac",
            "apiBaseURL": url, "licensePublicKey": key.base64EncodedString()])
    }
}
