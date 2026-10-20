import Foundation
import XCTest
@testable import CleanerCore

final class PermissionStatusTests: XCTestCase {
    func testDeniedFullDiskAccessDegradesWithoutDisablingAllScanning() async {
        let snapshot = await PermissionStatusService(fileSystem: PermissionFixtureFS(), homeDirectory: URL(fileURLWithPath: "/Users/tester")).snapshot()
        XCTAssertEqual(snapshot.level, .limited)
        XCTAssertTrue(snapshot.availableCategories.contains(.cache))
        XCTAssertFalse(snapshot.affectedCategories.isEmpty)
        XCTAssertTrue(snapshot.appManagement.settingsURL.absoluteString.contains("Privacy_AppBundles"))
    }

    func testLimitedPermissionStartsScanningInsteadOfOpeningACustomAssistant() {
        XCTAssertTrue(
            PermissionScanStartPolicy.shouldStartFullScan(fullDiskAccess: .actionRequired)
        )
    }
}

private actor PermissionFixtureFS: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { false }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
