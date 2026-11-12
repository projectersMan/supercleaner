import XCTest
@testable import CleanerCore

final class ScanPermissionPreparationTests: XCTestCase {
    func testFullDiskAccessStartsFullScanWithoutUnrelatedPreparation() {
        XCTAssertTrue(ScanPermissionPreparationPolicy.canProceed(diskAccess: .granted))
        XCTAssertFalse(ScanPermissionPreparationPolicy.canProceed(diskAccess: .actionRequired))
        XCTAssertFalse(ScanPermissionPreparationPolicy.canProceed(diskAccess: .unverified))
    }
}
