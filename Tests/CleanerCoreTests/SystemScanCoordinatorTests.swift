import Foundation
import XCTest
@testable import CleanerCore

final class SystemScanCoordinatorTests: XCTestCase {
    func testAllModulesShareOneGenerationAndReachTerminalStates() async {
        let recorder = SystemScanTestRecorder()
        let context = ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
            fileSystem: EmptySystemScanFileSystem()
        )

        let report = await SystemScanCoordinator().scan(context: context) { event in
            await recorder.append(event)
        }

        XCTAssertNotNil(report)
        XCTAssertTrue(report?.isCommitEligible == true)
        XCTAssertTrue(ScanModuleID.allCases.allSatisfy { report?.modules[$0]?.state.isTerminal == true })
        let events = await recorder.values()
        XCTAssertEqual(Set(events.map(\.generationID)), [report!.generationID])
    }

    func testCancelledTaskDoesNotReturnPartialReport() async {
        let context = ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
            fileSystem: EmptySystemScanFileSystem()
        )
        let report = await Task<SystemScanReport?, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            return await SystemScanCoordinator().scan(context: context)
        }.value

        XCTAssertNil(report)
    }

    func testModuleReplacementPreservesGenerationAndStartedAt() {
        let started = Date(timeIntervalSince1970: 100)
        let old = emptyCompletedReport(at: started)
        let replacementTime = started.addingTimeInterval(60)
        let replacementTree = DiskUsageTree(roots: [], largeFiles: [], coverage: CoverageSummary(), scannedAt: replacementTime)

        let refreshed = old.replacing(
            module: .largeFiles,
            payload: .largeFiles(replacementTree, []),
            completedAt: replacementTime
        )

        XCTAssertEqual(refreshed.generationID, old.generationID)
        XCTAssertEqual(refreshed.startedAt, old.startedAt)
        XCTAssertEqual(refreshed.modules[.applications]?.completedAt, old.modules[.applications]?.completedAt)
        XCTAssertEqual(refreshed.modules[.largeFiles]?.completedAt, replacementTime)
    }

    private func emptyCompletedReport(at date: Date) -> SystemScanReport {
        let statuses = Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
            ($0, ScanModuleStatus(module: $0, state: .completed, startedAt: date, completedAt: date))
        })
        return SystemScanReport(
            metadata: ScanGenerationMetadata(startedAt: date, completedAt: date, rulesetVersion: "test"),
            modules: statuses,
            generalCandidates: [],
            applicationInventory: ApplicationInventory(applications: [], coverage: CoverageSummary(), scannedAt: date),
            diskUsageTree: DiskUsageTree(roots: [], largeFiles: [], coverage: CoverageSummary(), scannedAt: date),
            largeFileCandidates: [],
            agentAssets: [],
            agentSkills: []
        )
    }
}

private actor SystemScanTestRecorder {
    private var events: [SystemScanProgressEvent] = []
    func append(_ event: SystemScanProgressEvent) { events.append(event) }
    func values() -> [SystemScanProgressEvent] { events }
}

private actor EmptySystemScanFileSystem: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { false }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { false }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
