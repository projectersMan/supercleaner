import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class ScanDashboardResponsivenessTests: XCTestCase {
    @MainActor
    func testProgressivePublicationDoesNotBlockTheMainActor() async throws {
        var finished = false
        var tickerStarted = false
        let ticker = Task { @MainActor in
            var previous = ContinuousClock.now
            var longestGap = Duration.zero
            tickerStarted = true
            while !finished {
                try? await Task.sleep(nanoseconds: 5_000_000)
                let now = ContinuousClock.now
                longestGap = max(longestGap, previous.duration(to: now))
                previous = now
            }
            return longestGap
        }
        while !tickerStarted { await Task.yield() }
        do { try await AppModel.checkScanPublicationRemainsResponsive() }
        catch { finished = true; _ = await ticker.value; throw error }
        finished = true
        let longestGap = await ticker.value
        XCTAssertLessThan(longestGap, .milliseconds(100), "The main actor must keep servicing events throughout all report publications")
        print("PASS: main-actor heartbeat maximum gap during retained report publications: \(longestGap)")
    }

    @MainActor
    func testThresholdChecksDoNotRebuildTheLargeFileReviewTree() throws {
        let base = try ResourceCleanupPresentationFixture.installerReport()
        let home = ResourceCleanupPresentationFixture.home
        let identity = FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .file)
        let unrelated = (0..<40_000).map { index in
            DiskUsageNode(url: home.appendingPathComponent("Documents/file-\(index)"), kind: .file,
                ownBytes: 1, recursiveBytes: 1, childCount: 0, modifiedAt: Date(timeIntervalSince1970: 0), isReadable: true,
                children: .unloaded, identity: identity)
        }
        let docs = DiskUsageNode(url: home.appendingPathComponent("Documents"), kind: .directory,
            ownBytes: 0, recursiveBytes: 40_000, childCount: unrelated.count, modifiedAt: Date(),
            isReadable: true, children: .loaded(unrelated))
        let installer = try XCTUnwrap(base.largeFileCandidates.first)
        let file = DiskUsageNode(url: installer.url, kind: .file, ownBytes: 100, recursiveBytes: 100,
            childCount: 0, modifiedAt: Date(), isReadable: true, children: .unloaded, identity: identity)
        let root = DiskUsageNode(url: home, kind: .directory, ownBytes: 0, recursiveBytes: 40_100,
            childCount: 2, modifiedAt: Date(), isReadable: true, children: .loaded([docs, file]))
        let tree = DiskUsageTree(roots: [root], largeFiles: [file],
            minimumFileBytes: LargeFileThreshold.mb100.bytes, coverage: .init(), scannedAt: Date())
        let report = base.replacing(moduleResult: .init(generationID: base.generationID,
            status: .init(module: .largeFiles, state: .completed), payload: .largeFiles(tree, base.largeFileCandidates)))
        let suite = "ScanDashboardResponsivenessTests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(home: home, preferences: preferences, readRunningApplicationIDs: { [] }, readDiskCapacity: { _ in .unavailable(2) })
        model.install(report)
        let started = ContinuousClock.now
        for _ in 0..<20 { XCTAssertFalse(model.largeFileThresholdNeedsRefresh) }
        let elapsed = started.duration(to: .now)
        XCTAssertLessThan(elapsed, .milliseconds(100), "Dashboard status reads must not recursively rebuild a 40,000-node tree")
        let review = try XCTUnwrap(model.diskUsageTree)
        XCTAssertTrue(review.largeFiles.isEmpty)
        XCTAssertEqual(review.roots.first?.recursiveBytes, 40_000)
        let cachedStarted = ContinuousClock.now
        for _ in 0..<20 { XCTAssertEqual(model.diskUsageTree?.roots.count, 1) }
        XCTAssertLessThan(cachedStarted.duration(to: .now), .milliseconds(100), "Repeated view reads must reuse the filtered tree")
        let refreshed = report.replacing(module: .projects,
            payload: .projects(.init(startedAt: Date(), completedAt: Date(), roots: [], artifacts: [], limitations: [])), completedAt: Date())
        model.install(refreshed)
        XCTAssertEqual(model.diskUsageTree?.largeFiles.count, 1, "Ownership changes must invalidate the cached review tree")
    }
}
