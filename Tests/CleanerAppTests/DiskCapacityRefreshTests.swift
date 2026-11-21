import CleanerCore
import Combine
import Darwin
import Foundation
import XCTest
@testable import CleanerApp

final class DiskCapacityRefreshTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testReturningToAppRefreshesCapacity() async {
        let model = AppModel(home: URL(fileURLWithPath: "/fixture"),
            readDiskCapacity: DiskCapacityRefreshTests.readCapacity)
        model.applicationDidBecomeActive()
        await model.waitForTrashEmptyingCapacityCheck()
        XCTAssertEqual(model.diskCapacityMonitor.snapshot?.availableBytes, 400)
    }

    private static func readCapacity(at url: URL) async -> DiskCapacityReadResult {
        .available(DiskCapacitySnapshot(volumeURL: url, totalBytes: 1_000,
            availableBytes: 400, recordedAt: Date())!)
    }

    @MainActor
    func testHeartbeatPublishesNewCapacityWithoutUserAction() async {
        let reader = CapacityReadFixture()
        let monitor = DiskCapacityMonitor(directory: URL(fileURLWithPath: "/fixture"), refreshInterval: 0.02,
            read: { await reader.read(at: $0) })
        let updated = expectation(description: "Periodic refresh publishes next capacity")
        let subscription = monitor.$snapshot.compactMap { $0 }.first { $0.availableBytes == 200 }
            .sink { _ in updated.fulfill() }
        monitor.start()
        monitor.start()
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertGreaterThanOrEqual(monitor.snapshot?.availableBytes ?? 0, 200)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testSlowReadCoalescesRequestsAndLeavesMainActorAvailable() async {
        let reader = SuspendedCapacityRead()
        let monitor = DiskCapacityMonitor(directory: URL(fileURLWithPath: "/fixture"), refreshInterval: 60,
            read: { await reader.read(at: $0) })
        monitor.refresh()
        await fulfillment(of: [reader.started], timeout: 2)
        monitor.refresh()
        monitor.refresh()
        // This main-actor work must run while the disk reader is still suspended.
        XCTAssertNil(monitor.snapshot)
        await reader.finish()
        await monitor.waitForRefresh()
        XCTAssertEqual(monitor.snapshot?.availableBytes, 700)
        let calls = await reader.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testCapacityRefreshDoesNotInvalidateApplicationModelOrUnchangedSidebar() async {
        let model = AppModel(home: URL(fileURLWithPath: "/fixture"),
            readDiskCapacity: DiskCapacityRefreshTests.readCapacity)
        let initialized = expectation(description: "Unrelated model availability initialization finished")
        let initialization = model.$agentOverlapModelCanRemove.dropFirst().first().sink { _ in initialized.fulfill() }
        await fulfillment(of: [initialized], timeout: 2)
        var appUpdates = 0
        var sidebarUpdates = 0
        let appSubscription = model.objectWillChange.sink { appUpdates += 1 }
        model.refreshDiskCapacity()
        await model.waitForTrashEmptyingCapacityCheck()
        let sidebarSubscription = model.diskCapacityMonitor.objectWillChange.sink { sidebarUpdates += 1 }
        model.refreshDiskCapacity()
        await model.waitForTrashEmptyingCapacityCheck()
        XCTAssertEqual(appUpdates, 0)
        XCTAssertEqual(sidebarUpdates, 0)
        withExtendedLifetime((initialization, appSubscription, sidebarSubscription)) {}
    }

    @MainActor
    func testReadErrorClearsStaleCapacityAndNextReadRecovers() async {
        let reader = CapacityReadFixture()
        let monitor = DiskCapacityMonitor(directory: URL(fileURLWithPath: "/fixture"), refreshInterval: 60,
            read: { await reader.read(at: $0) })
        monitor.refresh()
        await monitor.waitForRefresh()
        XCTAssertEqual(monitor.snapshot?.availableBytes, 100)
        await reader.setFailure(true)
        monitor.refresh()
        await monitor.waitForRefresh()
        XCTAssertNil(monitor.snapshot)
        XCTAssertNotNil(monitor.readError)
        await reader.setFailure(false)
        monitor.refresh()
        await monitor.waitForRefresh()
        XCTAssertEqual(monitor.snapshot?.availableBytes, 300)
        XCTAssertNil(monitor.readError)
    }

    @MainActor
    func testHeartbeatDoesNotRetainMonitor() async {
        var monitor: DiskCapacityMonitor? = DiskCapacityMonitor(directory: URL(fileURLWithPath: "/fixture"),
            refreshInterval: 0.02, read: DiskCapacityRefreshTests.readCapacity)
        weak var releasedMonitor = monitor
        monitor?.start()
        await monitor?.waitForRefresh()
        monitor = nil
        XCTAssertNil(releasedMonitor)
    }
}

private actor CapacityReadFixture {
    private var calls: UInt64 = 0
    private var fails = false

    func setFailure(_ value: Bool) { fails = value }

    func read(at url: URL) -> DiskCapacityReadResult {
        calls += 1
        if fails { return .unavailable(EIO) }
        return .available(DiskCapacitySnapshot(volumeURL: url, totalBytes: 10_000,
            availableBytes: calls * 100, recordedAt: Date())!)
    }
}

private actor SuspendedCapacityRead {
    nonisolated let started = XCTestExpectation(description: "Disk read started")
    private var continuation: CheckedContinuation<DiskCapacityReadResult, Never>?
    private(set) var calls = 0

    func read(at url: URL) async -> DiskCapacityReadResult {
        calls += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish() {
        continuation?.resume(returning: .available(DiskCapacitySnapshot(volumeURL: URL(fileURLWithPath: "/fixture"),
            totalBytes: 1_000, availableBytes: 700, recordedAt: Date())!))
        continuation = nil
    }
}
