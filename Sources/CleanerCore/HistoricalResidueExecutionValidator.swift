import Foundation

public enum HistoricalResidueExecutionRejection: Error, Sendable {
    case missingEvidence
    case applicationReappeared
    case pathOutsideResidueRoots
    case identityChanged
    case active
}

public struct HistoricalResidueExecutionValidator: Sendable {
    public init() {}

    public func validate(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard candidate.source == .historicalApplicationResidue else { return }
        guard let identifier = candidate.evidence.first(where: { $0.code == "residue-bundle-id" })?.summary,
              !identifier.isEmpty else { throw HistoricalResidueExecutionRejection.missingEvidence }

        let installed = await ApplicationScanner().installedApplications(
            context: context,
            runningBundleIdentifiers: context.runningBundleIdentifiers,
            maximumDepth: 12,
            maximumEntries: 30_000
        )
        guard !installed.applications.contains(where: { $0.bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame }) else {
            throw HistoricalResidueExecutionRejection.applicationReappeared
        }
        let allowedRoots = ["Caches", "Application Support", "Preferences", "Saved Application State", "Containers", "Group Containers"]
            .map { context.homeDirectory.appendingPathComponent("Library/\($0)").standardizedFileURL.path }
        let path = candidate.url.standardizedFileURL.path
        guard allowedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            throw HistoricalResidueExecutionRejection.pathOutsideResidueRoots
        }
        guard !context.isActive(candidate.url) else { throw HistoricalResidueExecutionRejection.active }
        guard let current = try? await context.fileSystem.identity(at: candidate.url), current == candidate.identity else {
            throw HistoricalResidueExecutionRejection.identityChanged
        }
    }
}
