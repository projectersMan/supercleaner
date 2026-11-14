import Foundation
import XCTest
@testable import CleanerCore

final class HelperProtocolTests: XCTestCase {
    func testInputMethodHelperScopeAllowsOnlyThirdPartyAppBundles() throws {
        let scope = try HelperFileScope(userID: 501, homePath: "/Users/tester")
        XCTAssertTrue(scope.isApplication("/Library/Input Methods/SogouInput.app"))
        for path in ["/System/Library/Input Methods/Apple.app", "/Library/Other.app", "/Library/Input Methods",
                     "/Library/Input Methods/Host.app/Contents/Nested.app", "/Library/Input Methods/../Other.app"] {
            XCTAssertFalse(scope.isApplication(path))
        }
        let request = UninstallPermissionRequest(url: URL(fileURLWithPath: "/Library/Input Methods/SogouInput.app"),
            resource: .applicationBundle, cause: .filePermissions, attempt: 1)
        XCTAssertTrue(request.supportsPrivilegedHelper)
        XCTAssertNil(request.settingsURL)
    }

    func testTokenCannotAuthorizeDifferentPathOrReplay() async throws {
        let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
        let allowed = HelperOperation.moveToQuarantine(path: "/Library/Caches/example", destination: "/Library/Application Support/SuperCleaner/Quarantine/example")
        let token = CapabilityToken.issueForTesting(operation: allowed, identity: identity, callerRequirement: "anchor apple generic", expiresAt: Date(timeIntervalSince1970: 200))
        let authorizer = HelperAuthorizer(expectedCallerRequirement: "anchor apple generic")

        let wrong = await authorizer.authorize(operation: .moveToQuarantine(path: "/Library/Caches/other", destination: "/Library/Application Support/SuperCleaner/Quarantine/example"), token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(wrong, .rejected(.operationMismatch))
        let accepted = await authorizer.authorize(operation: allowed, token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(accepted, .accepted)
        let replayed = await authorizer.authorize(operation: allowed, token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(replayed, .rejected(.replayedNonce))
    }
}
