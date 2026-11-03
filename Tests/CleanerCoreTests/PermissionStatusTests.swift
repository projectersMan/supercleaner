import Foundation
import XCTest
import Darwin
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

    func testProtectedProbeReadableDoesNotRequireOtherAppDirectories() async {
        let fileSystem = PermissionProbeFixture(mode: .readable)
        let snapshot = await PermissionStatusService(fileSystem: fileSystem, homeDirectory: URL(fileURLWithPath: "/Users/tester")).snapshot()
        XCTAssertEqual(snapshot.fullDiskAccess.status, .granted)
        let paths = await fileSystem.inspectedPaths
        XCTAssertEqual(paths, ["/Users/tester/Library/Application Support/com.apple.TCC"])
    }

    func testExplicitAccessDenialRemainsActionable() async {
        let snapshot = await PermissionStatusService(fileSystem: PermissionProbeFixture(mode: .denied), homeDirectory: URL(fileURLWithPath: "/Users/tester")).snapshot()
        XCTAssertEqual(snapshot.fullDiskAccess.status, .actionRequired)
    }

    func testMissingUserProbeUsesReadableSystemProbe() async {
        let fileSystem = PermissionProbeFixture(mode: .userMissingSystemReadable)
        let snapshot = await PermissionStatusService(fileSystem: fileSystem, homeDirectory: URL(fileURLWithPath: "/Users/tester")).snapshot()
        XCTAssertEqual(snapshot.fullDiskAccess.status, .granted)
        let paths = await fileSystem.inspectedPaths
        XCTAssertEqual(paths, [
            "/Users/tester/Library/Application Support/com.apple.TCC",
            "/Library/Application Support/com.apple.TCC",
        ])
    }

    func testMissingAndOtherReadErrorsAreNotReportedAsMissingAuthorization() async {
        for mode in [PermissionProbeFixture.Mode.missing, .failed] {
            let snapshot = await PermissionStatusService(fileSystem: PermissionProbeFixture(mode: mode), homeDirectory: URL(fileURLWithPath: "/Users/tester")).snapshot()
            XCTAssertEqual(snapshot.fullDiskAccess.status, .unverified)
            XCTAssertTrue(PermissionScanStartPolicy.shouldStartFullScan(fullDiskAccess: snapshot.fullDiskAccess.status))
        }
    }
}

private actor PermissionProbeFixture: FileSystemAccess {
    enum Mode: Sendable { case readable, denied, missing, failed, userMissingSystemReadable }
    let mode: Mode
    private(set) var inspectedPaths: [String] = []

    init(mode: Mode) { self.mode = mode }
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) throws -> [URL] {
        inspectedPaths.append(url.path)
        guard url.lastPathComponent == "com.apple.TCC" else { throw POSIXError(.EACCES) }
        switch mode {
        case .readable: return []
        case .denied: throw POSIXError(.EPERM)
        case .missing: throw FileSystemError.missing(url)
        case .failed: throw POSIXError(.EIO)
        case .userMissingSystemReadable:
            if url.path.hasPrefix("/Users/") { throw FileSystemError.missing(url) }
            return []
        }
    }
    func isReadable(_ url: URL) -> Bool { false }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { false }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor PermissionFixtureFS: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) throws -> [URL] { throw FileSystemError.unreadableContent(url) }
    func isReadable(_ url: URL) -> Bool { false }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
