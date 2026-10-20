import Foundation
import XCTest
@testable import CleanerCore

final class SystemScanPrimitivesTests: XCTestCase {
    func testWaitingAndScanningAreTheOnlyNonTerminalModuleStates() {
        XCTAssertFalse(ScanModuleState.waiting.isTerminal)
        XCTAssertFalse(ScanModuleState.scanning.isTerminal)
        XCTAssertTrue(ScanModuleState.completed.isTerminal)
        XCTAssertTrue(ScanModuleState.limited.isTerminal)
        XCTAssertTrue(ScanModuleState.failed.isTerminal)
        XCTAssertTrue(ScanModuleState.cancelled.isTerminal)
    }

    func testCoverageStandardizesAndDeduplicatesRoots() {
        let duplicated = URL(fileURLWithPath: "/Users/tester/Documents/../Downloads")
        let standardized = URL(fileURLWithPath: "/Users/tester/Downloads")

        let coverage = CoverageSummary(
            scannedRoots: [duplicated, standardized],
            unavailableRoots: [duplicated, standardized],
            budgetLimitedModules: [.largeFiles]
        )

        XCTAssertEqual(coverage.scannedRoots, [standardized])
        XCTAssertEqual(coverage.unavailableRoots, [standardized])
        XCTAssertEqual(coverage.budgetLimitedModules, [.largeFiles])
    }
}
