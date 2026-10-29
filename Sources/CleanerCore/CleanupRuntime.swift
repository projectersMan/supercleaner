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
        activePaths: Set<URL> = [], runningBundleIdentifiers: Set<String> = [], includeProjectActivity: Bool = false,
        includeProcessActivity: Bool = true
    ) async throws -> (context: ScanContext, pack: RulePack) {
        let pack = try await rules.currentPack()
        let protection: ProtectionPolicy
        do { protection = try await protections.snapshot() }
        catch { protection = ProtectionPolicy(homeDirectory: home, isAvailable: false) }
        return try await configuration(
            pack: pack,
            protection: protection,
            activePaths: activePaths,
            runningBundleIdentifiers: runningBundleIdentifiers,
            includeProjectActivity: includeProjectActivity,
            includeProcessActivity: includeProcessActivity
        )
    }

    private func configuration(
        pack: RulePack,
        protection: ProtectionPolicy,
        activePaths: Set<URL> = [],
        runningBundleIdentifiers: Set<String> = [],
        includeProjectActivity: Bool = false,
        includeProcessActivity: Bool = true
    ) async throws -> (context: ScanContext, pack: RulePack) {
        let activity = includeProcessActivity || includeProjectActivity
            ? await ActivitySnapshot.capture()
            : ActivitySnapshot(processNames: [], isAvailable: false, buildProcessIDs: [])
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

    public func prepareExecutionValidationBatch(
        candidates: [CleanupCandidate],
        maximumConcurrentValidations: Int = 4
    ) async throws -> CleanupValidationBatch {
        let snapshot = try await rules.executionSnapshot()
        let protection: ProtectionPolicy
        do { protection = try await protections.snapshot() }
        catch { protection = ProtectionPolicy(homeDirectory: home, isAvailable: false) }
        let needsProjectActivity = candidates.contains { $0.source == .projectArtifacts }
        let needsProcessActivity = candidates.contains { $0.source == .projectArtifacts || $0.source == .agentWorkspace }
        let configuration = try await configuration(
            pack: snapshot.pack,
            protection: protection,
            includeProjectActivity: needsProjectActivity,
            includeProcessActivity: needsProcessActivity
        )
        guard try await rules.executionStateFingerprint() == snapshot.fingerprint else {
            throw RuleStoreError.interruptedCommit
        }

        if candidates.isEmpty {
            let expectedFingerprint = snapshot.fingerprint
            let rules = rules
            return CleanupValidationBatch(
                ruleVersion: snapshot.pack.executionVersion,
                results: [:],
                verifyRuleState: {
                    guard try await rules.executionStateFingerprint() == expectedFingerprint else {
                        throw RuleStoreError.interruptedCommit
                    }
                }
            )
        }

        let width = max(1, min(maximumConcurrentValidations, 4, candidates.count))
        let results = try await withThrowingTaskGroup(
            of: (UUID, CleanupCandidateValidation).self,
            returning: [UUID: CleanupCandidateValidation].self
        ) { group in
            var next = 0
            var output: [UUID: CleanupCandidateValidation] = [:]
            func submit(_ candidate: CleanupCandidate) {
                group.addTask {
                    do {
                        try await validateForExecution(candidate, configuration: configuration)
                        return (candidate.id, .valid)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (candidate.id, .refused(String(describing: error)))
                    }
                }
            }
            for _ in 0..<width {
                submit(candidates[next])
                next += 1
            }
            while let (id, result) = try await group.next() {
                output[id] = result
                if next < candidates.count {
                    submit(candidates[next])
                    next += 1
                }
            }
            return output
        }
        let expectedFingerprint = snapshot.fingerprint
        let rules = rules
        return CleanupValidationBatch(
            ruleVersion: snapshot.pack.executionVersion,
            results: results,
            verifyRuleState: {
                guard try await rules.executionStateFingerprint() == expectedFingerprint else {
                    throw RuleStoreError.interruptedCommit
                }
            }
        )
    }

    public func validateForExecution(_ candidate: CleanupCandidate) async throws {
        // General cleanup treats process activity as advisory. App ownership uses
        // live NSWorkspace state and its own targeted process checks. Neither
        // needs a fresh system-wide process listing for every individual file.
        let configuration = try await configuration(includeProjectActivity: candidate.source == .projectArtifacts,
            includeProcessActivity: candidate.source == .projectArtifacts || candidate.source == .agentWorkspace)
        try await validateForExecution(candidate, configuration: configuration)
    }

    private func validateForExecution(
        _ candidate: CleanupCandidate,
        configuration: (context: ScanContext, pack: RulePack)
    ) async throws {
        try configuration.context.protectionPolicy.validate(candidate.url)
        if let ruleID = candidate.ruleID, configuration.pack.revokedRuleIDs.contains(ruleID) {
            throw RuleScanError.ruleUnavailable(ruleID)
        }
        if candidate.ruleID?.hasPrefix("system-cleanup.v1.") == true {
            guard let owner = candidate.cleanupApplication, let url = owner.bundleURL,
                  let metadata = BundleApplicationMetadataProvider().metadata(for: url),
                  metadata.bundleIdentifier == owner.bundleIdentifier else {
                throw RuleScanError.executionRefused(candidate.ruleID ?? "system-cleanup")
            }
            let app = InstalledApplication(bundleURL: url, bundleIdentifier: metadata.bundleIdentifier, name: metadata.name,
                version: metadata.version, isRunning: configuration.context.runningBundleIdentifiers.contains(metadata.bundleIdentifier),
                isSystem: false, applicationGroups: metadata.applicationGroups, associatedBundleIdentifiers: metadata.associatedBundleIdentifiers)
            try await ApplicationCleanupScanner().validateForExecution(candidate, context: configuration.context, applications: [app])
        } else {
            try await CleanupRuleEngine(pack: configuration.pack).validateForExecution(candidate, context: configuration.context)
        }
        if candidate.source == .historicalApplicationResidue {
            try await HistoricalResidueExecutionValidator().validate(candidate, context: configuration.context)
        }
        if candidate.source == .projectArtifacts {
            try await ProjectArtifactScanner(roots: projectRoots.roots()).validateForExecution(candidate, context: configuration.context)
        }
        if candidate.source == .application {
            try await ApplicationExecutionValidator().validate(candidate, context: configuration.context)
        }
    }
}
