import Foundation
import AppKit

/// Shared production configuration for GUI, read-only CLI and final execution.
/// Stores reload durable state; UI snapshots cannot grant authority after a
/// rule or protection entry changes on disk.
public struct CleanupRuntime: Sendable {
    public let home: URL
    public let rules: RuleStore
    public let protections: ProtectionStore
    public let fileSystem: any FileSystemAccess
    public let projectRoots: ProjectScanRootsStore

    public init(home: URL, fileSystem: any FileSystemAccess = LocalFileSystem(), rulePublicKey: Data? = nil) {
        self.home = home
        self.fileSystem = fileSystem
        let support = home.appendingPathComponent("Library/Application Support/SuperCleaner")
        let configuredKey = rulePublicKey ?? (try? ReleaseConfiguration.load())?.rulePublicKey ?? Data()
        rules = RuleStore(directory: support.appendingPathComponent("Rules"), publicKey: configuredKey, bundledURL: BundledCleanupRules.url)
        protections = ProtectionStore(url: support.appendingPathComponent("protected-paths.json"), homeDirectory: home)
        projectRoots = ProjectScanRootsStore(url: support.appendingPathComponent("project-scan-roots.json"), home: home)
    }

    public func configuration(
        activePaths: Set<URL> = [], runningBundleIdentifiers: Set<String> = [], includeProjectActivity: Bool = false
    ) async throws -> (context: ScanContext, pack: RulePack) {
        let pack = try await rules.currentPack()
        let protection: ProtectionPolicy
        do { protection = try await protections.snapshot() }
        catch { protection = ProtectionPolicy(homeDirectory: home, isAvailable: false) }
        let activity = await ActivitySnapshot.capture()
        let applications = await MainActor.run { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) }
        let bundleIDs = runningBundleIdentifiers.union(applications)
        var paths = activePaths.union(bundleIDs.flatMap { id in
            [home.appendingPathComponent("Library/Caches/\(id)")]
        })
        var projectActivityAvailable = true
        if includeProjectActivity {
            let projectActivity = try await ProjectActivityProbe.capture(activity: activity, roots: projectRoots.roots())
            paths.formUnion(projectActivity.paths)
            projectActivityAvailable = projectActivity.isAvailable
        }
        return (ScanContext(
            homeDirectory: home, fileSystem: fileSystem, activePaths: paths,
            protectionPolicy: protection, runningBundleIdentifiers: bundleIDs,
            activeProcessNames: activity.processNames, activityProbeAvailable: activity.isAvailable,
            projectActivityAvailable: projectActivityAvailable
        ), pack)
    }

    public func validateForExecution(_ candidate: CleanupCandidate) async throws {
        let configuration = try await configuration(includeProjectActivity: candidate.source == .projectArtifacts)
        try configuration.context.protectionPolicy.validate(candidate.url)
        try await CleanupRuleEngine(pack: configuration.pack).validateForExecution(candidate, context: configuration.context)
        if candidate.source == .projectArtifacts {
            try await ProjectArtifactScanner(roots: projectRoots.roots()).validateForExecution(candidate, context: configuration.context)
        }
        if candidate.source == .application {
            try await ApplicationExecutionValidator().validate(candidate, context: configuration.context)
        }
    }
}
