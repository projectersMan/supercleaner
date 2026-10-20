import Foundation
import XCTest
@testable import CleanerCore

final class ApplicationUpdatePolicyTests: XCTestCase {
    func testBuildNumbersAreStrictAndDowngradesRejected() throws {
        let configuration = ReleaseConfiguration(bundleIdentifier: "com.test.Cleaner", teamIdentifier: "ABCDE12345", allowedHosts: ["updates.example.com"])
        let policy = ApplicationUpdatePolicy(configuration: configuration)
        XCTAssertEqual(try ApplicationUpdatePolicy.buildNumber("12"), 12)
        for invalid in ["0", "01", "1.0", "1a", "18446744073709551616"] {
            XCTAssertThrowsError(try ApplicationUpdatePolicy.buildNumber(invalid))
        }
        XCTAssertThrowsError(try policy.validate(version: "1", currentVersion: "2", archiveURL: URL(string: "https://updates.example.com/app.dmg"), length: 1, installationType: "application", feedIsSigned: true))
        XCTAssertThrowsError(try policy.validate(version: "3", currentVersion: "2", archiveURL: URL(string: "https://updates.example.com/app.dmg"), length: 1, installationType: "application", feedIsSigned: false))
    }
}
