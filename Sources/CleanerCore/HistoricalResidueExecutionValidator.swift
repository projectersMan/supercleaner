import Foundation

public enum HistoricalResidueExecutionRejection: Error, Sendable {
    case missingEvidence
    case applicationReappeared
    case incompleteInventory
    case pathOutsideResidueRoots
    case identityChanged
    case active
}

public struct HistoricalResidueExecutionValidator: Sendable {
    public init() {}

    public func inventory(context: ScanContext, includeSharedDeclarations: Bool) async -> ApplicationInventory {
        let installed = await ApplicationScanner().installedApplications(
            context: context, runningBundleIdentifiers: context.runningBundleIdentifiers)
        return includeSharedDeclarations ? await installed.completingSharedGroupDeclarations() : installed
    }

    public func validate(_ candidate: CleanupCandidate, context: ScanContext, inventory: ApplicationInventory? = nil) async throws {
        guard candidate.source == .historicalApplicationResidue else { return }
        guard let identifier = candidate.evidence.first(where: { $0.code == "residue-bundle-id" })?.summary,
              !identifier.isEmpty else { throw HistoricalResidueExecutionRejection.missingEvidence }

        let sharedRoot = context.homeDirectory.appendingPathComponent("Library/Group Containers").standardizedFileURL.path
        let containerRoot = context.homeDirectory.appendingPathComponent("Library/Containers").standardizedFileURL.path
        let isShared = candidate.url.standardizedFileURL.path.hasPrefix(sharedRoot + "/")
            || candidate.url.standardizedFileURL.path.hasPrefix(containerRoot + "/")
        let installed: ApplicationInventory
        if let inventory { installed = inventory }
        else { installed = await self.inventory(context: context, includeSharedDeclarations: isShared) }
        guard installed.coverage.unavailableRoots.isEmpty,
              !installed.coverage.budgetLimitedModules.contains(.applications) else {
            throw HistoricalResidueExecutionRejection.incompleteInventory
        }
        if isShared {
            guard HistoricalResidueOwnership.sharedOwnershipComplete(installed, context: context) else {
                throw HistoricalResidueExecutionRejection.incompleteInventory
            }
        }
        guard !HistoricalResidueOwnership.hasOwner(identifier, applications: installed.applications),
              !HistoricalResidueOwnership.hasRunningOwner(identifier, identifiers: context.runningBundleIdentifiers) else {
            throw HistoricalResidueExecutionRejection.applicationReappeared
        }
        let allowedRoots = ["Caches", "Application Support", "Preferences", "Saved Application State", "Containers", "Group Containers"]
            .map { context.homeDirectory.appendingPathComponent("Library/\($0)").standardizedFileURL.path }
        let path = candidate.url.standardizedFileURL.path
        guard allowedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
            throw HistoricalResidueExecutionRejection.pathOutsideResidueRoots
        }
        guard !context.isActive(candidate.url) else { throw HistoricalResidueExecutionRejection.active }
        guard let current = try? await context.fileSystem.identity(at: candidate.url), candidate.matchesExecutionIdentity(current) else {
            throw HistoricalResidueExecutionRejection.identityChanged
        }
    }
}
