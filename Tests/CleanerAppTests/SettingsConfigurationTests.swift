import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class SettingsConfigurationTests: XCTestCase {
    func testThresholdDropdownOptionsAndNormalization() {
        XCTAssertEqual(AgentOverlapThresholdOption.allCases.map(\.rawValue), [80, 85, 90, 95, 100])
        for option in AgentOverlapThresholdOption.allCases {
            XCTAssertEqual(AgentOverlapThresholdOption.nearest(to: option.fraction), option)
        }
        XCTAssertEqual(AgentOverlapThresholdOption.nearest(to: 0.5), .eighty)
        XCTAssertEqual(AgentOverlapThresholdOption.nearest(to: 1.5), .hundred)
        XCTAssertEqual(AgentOverlapThresholdOption.nearest(to: .nan), .eightyFive)
    }

    @MainActor
    func testProjectFolderPersistenceAndIdleRefresh() async throws {
        try await AppModel.checkProjectScanRootsSettings()
    }

    @MainActor
    func testRecalculationCanBeRequestedDuringAnActiveScan() async throws {
        try await AppModel.checkAgentContainmentRecalculationQueue()
    }

    @MainActor
    func testProjectSettingsRemainEditableDuringAnUnrelatedAgentScan() async throws {
        try await AppModel.checkProjectConfigurationDuringAgentScan()
    }

    @MainActor
    func testSavedThresholdIsLoadedFromTheSelectedPreferences() {
        let suite = "SettingsConfigurationTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(0.95, forKey: "agentOverlap.coverageThreshold")
        let model = AppModel(home: FileManager.default.temporaryDirectory, preferences: preferences,
            readRunningApplicationIDs: { [] })
        XCTAssertEqual(model.agentOverlapThreshold, 0.95)
        model.updateAgentOverlapThreshold(0.90)
        XCTAssertEqual(preferences.double(forKey: "agentOverlap.coverageThreshold"), 0.90)
    }

    @MainActor
    func testLegacyThresholdMigratesToAnAvailableDropdownOption() {
        let suite = "SettingsConfigurationTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(0.83, forKey: "agentOverlap.coverageThreshold")
        let model = AppModel(home: FileManager.default.temporaryDirectory, preferences: preferences,
            readRunningApplicationIDs: { [] })
        XCTAssertEqual(model.agentOverlapThreshold, 0.85)
        XCTAssertEqual(preferences.double(forKey: "agentOverlap.coverageThreshold"), 0.85)
    }
}
