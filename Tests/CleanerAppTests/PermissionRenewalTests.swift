import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class PermissionRenewalTests: XCTestCase {
    @MainActor
    func testDetectedDenialPresentsAuthorizationAndCannotBeBypassed() async {
        let model = makeModel { snapshot(.actionRequired) }
        defer { model.cancelScan() }
        await model.loadPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation)
        model.continueScanWithCurrentPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation)
        XCTAssertFalse(model.isScanRunning)
        model.dismissScanPermissionPreparation()
        model.continueScanWithCurrentPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation)
        XCTAssertFalse(model.isScanRunning)
    }

    @MainActor
    func testPermissionLostBetweenStartCheckAndScanCannotRun() async {
        let reads = PermissionReads([snapshot(.granted), snapshot(.actionRequired)])
        let model = makeModel { await reads.next() }
        defer { model.cancelScan() }
        await model.loadPermissions()
        model.continueScanWithCurrentPermissions()
        for _ in 0..<100 {
            if await reads.count >= 2 && !model.isScanRunning && !model.checkingScanPermissions { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let readCount = await reads.total()
        XCTAssertGreaterThanOrEqual(readCount, 2)
        XCTAssertTrue(model.showsScanPermissionPreparation)
        XCTAssertFalse(model.isScanRunning)
    }

    @MainActor
    func testRevocationStopsRefreshAndKeepsExistingReport() async throws {
        let model = makeModel { snapshot(.actionRequired) }
        defer { model.cancelScan() }
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        let ids = Set(report.generalCandidates.map(\.id))
        model.selectedIDs = ids
        model.refreshModule(.projects)
        await model.loadPermissions()
        XCTAssertFalse(model.isScanRunning)
        XCTAssertTrue(model.showsScanPermissionPreparation)
        XCTAssertEqual(model.systemReport?.generationID, report.generationID)
        XCTAssertEqual(model.selectedIDs, ids)
    }

    @MainActor
    func testCancellationIsRespectedUntilANewFailureOrScanAttempt() async {
        let reads = PermissionReads([snapshot(.actionRequired), snapshot(.actionRequired),
                                     snapshot(.granted), snapshot(.actionRequired)])
        let model = makeModel { await reads.next() }
        await model.loadPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation)
        model.dismissScanPermissionPreparation()
        await model.loadPermissions()
        XCTAssertFalse(model.showsScanPermissionPreparation, "Do not repeatedly reopen the same cancelled prompt")
        await model.loadPermissions()
        await model.loadPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation, "A later revocation must ask again")
    }

    @MainActor
    func testGrantAfterRenewalCanStartScan() async {
        let reads = PermissionReads([snapshot(.actionRequired), snapshot(.granted)])
        let model = makeModel { await reads.next() }
        defer { model.cancelScan() }
        await model.loadPermissions()
        XCTAssertTrue(model.showsScanPermissionPreparation)
        model.preparePermissionsAndScan()
        for _ in 0..<100 {
            if !model.preparingScanPermissions { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.permissionSnapshot?.fullDiskAccess.status, .granted)
        XCTAssertFalse(model.showsScanPermissionPreparation)
        XCTAssertTrue(model.isScanRunning)
    }

    @MainActor
    func testModuleRefreshPerformsPermissionCheckBeforeScanning() async throws {
        let model = makeModel { snapshot(.actionRequired) }
        defer { model.cancelScan() }
        let report = try ResourceCleanupPresentationFixture.report()
        model.install(report)
        model.refreshModule(.projects)
        for _ in 0..<100 {
            if !model.isScanRunning { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.permissionSnapshot?.fullDiskAccess.status, .actionRequired)
        XCTAssertTrue(model.showsScanPermissionPreparation)
        XCTAssertFalse(model.isScanRunning)
        XCTAssertEqual(model.systemReport?.generationID, report.generationID)
    }

    @MainActor
    func testUnknownAccessIsNotMisreportedAsAnExplicitDenial() async {
        let model = makeModel { snapshot(.unverified) }
        await model.loadPermissions()
        XCTAssertFalse(model.showsScanPermissionPreparation)
        XCTAssertTrue(model.canScanWithCurrentPermissions)
    }

    @MainActor
    private func makeModel(read: @escaping @Sendable () async -> PermissionSnapshot) -> AppModel {
        AppModel(home: URL(fileURLWithPath: "/tmp/PermissionRenewalFixture"),
                 preferences: UserDefaults(suiteName: "PermissionRenewalTests.\(UUID())")!,
                 readRunningApplicationIDs: { [] }, readPermissionSnapshot: read)
    }
}

private func snapshot(_ status: PermissionCapabilityStatus) -> PermissionSnapshot {
    .init(level: status == .granted ? .full : .limited, availableCategories: [], affectedCategories: [],
          settingsURL: PermissionStatusService.fullDiskAccessSettingsURL, explanation: "Fixture",
          fullDiskAccess: .init(status: status, settingsURL: PermissionStatusService.fullDiskAccessSettingsURL, explanation: "Fixture"),
          appManagement: .init(status: .unverified, settingsURL: PermissionStatusService.appManagementSettingsURL, explanation: "Fixture"))
}

private actor PermissionReads {
    let values: [PermissionSnapshot]
    private(set) var count = 0
    init(_ values: [PermissionSnapshot]) { self.values = values }
    func next() -> PermissionSnapshot {
        defer { count += 1 }
        return values[min(count, values.count - 1)]
    }
    func total() -> Int { count }
}
