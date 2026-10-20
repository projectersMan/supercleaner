import AppKit
import CleanerCore
import Foundation

/// Builds the live adapter graph behind one construction seam. AppModel owns
/// product state; it does not need to know how journals, quarantine, Helper
/// authorization and filesystem execution are wired together.
@MainActor struct AppInfrastructure {
    let fileSystem: any FileSystemAccess
    let runtime: CleanupRuntime
    let helper: HelperSettingsModel
    let cleanupCoordinator: CleanupExecutionCoordinator

    static func live(home: URL) -> AppInfrastructure {
        let fileSystem = LocalFileSystem()
        let helper = HelperSettingsModel()
        let runtime = CleanupRuntime(home: home, fileSystem: fileSystem)
        let support = home.appendingPathComponent("Library/Application Support/SuperCleaner", isDirectory: true)
        let logsRoot = home.appendingPathComponent("Library/Logs", isDirectory: true).standardizedFileURL.path.lowercased()
        let activeCheck: @Sendable (URL) async -> Bool = { url in
            await MainActor.run {
                let path = url.standardizedFileURL.path.lowercased()
                if path == logsRoot || path.hasPrefix(logsRoot + "/") { return false }
                return NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).contains { bundleID in
                    path.split(separator: "/").contains(Substring(bundleID.lowercased()))
                }
            }
        }
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: home),
            quarantineRoot: support.appendingPathComponent("Quarantine", isDirectory: true),
            currentRuleVersion: "loading",
            isActive: activeCheck,
            loadProtection: { try await runtime.protections.snapshot() },
            loadRuleVersion: { try await runtime.rules.currentPack().executionVersion },
            validateCandidate: { try await runtime.validateForExecution($0) },
            privilegedApplications: helper.authorizedApplicationOperations(fileSystem: fileSystem)
        )
        let history = HistoryStore(url: support.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: support.appendingPathComponent("quarantine-schedules.json"))
        let resolutions = ResolutionJournalStore(url: support.appendingPathComponent("resolution-journal.json"))
        let maintenance = QuarantineMaintenanceCoordinator(
            historyStore: history,
            scheduleStore: schedules,
            executor: executor,
            resolutionJournalStore: resolutions
        )
        let coordinator = CleanupExecutionCoordinator(
            executor: executor,
            historyStore: history,
            journalStore: ExecutionJournalStore(url: support.appendingPathComponent("execution-journal.json")),
            resolutionJournalStore: resolutions,
            scheduleStore: schedules,
            maintenanceCoordinator: maintenance,
            now: Date.init
        )
        return AppInfrastructure(
            fileSystem: fileSystem,
            runtime: runtime,
            helper: helper,
            cleanupCoordinator: coordinator
        )
    }
}
