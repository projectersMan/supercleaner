import Foundation

public enum ApplicationExecutionRejection: Error, Sendable {
    case missingOwnership, ownershipChanged, managedInstallation, stillReferenced
}

/// Rebuild ownership at execution time. A plan cannot bypass a newly installed
/// second copy, a new service reference, running state or package-manager receipt.
public struct ApplicationExecutionValidator: Sendable {
    private let scanner: ApplicationScanner
    public init(scanner: ApplicationScanner = ApplicationScanner()) { self.scanner = scanner }
    public func validate(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard candidate.source == .application else { return }
        func fact(_ code: String) -> String? { candidate.evidence.first { $0.code == code }?.summary }
        guard let ownerPath = fact("owner-bundle"), let identifier = fact("owner-bundle-id"), let name = fact("owner-name"), ownerPath.hasPrefix("/"), !identifier.isEmpty else {
            throw ApplicationExecutionRejection.missingOwnership
        }
        let ownerURL = URL(fileURLWithPath: ownerPath).standardizedFileURL
        let inventory = await scanner.installedApplications(context: context, runningBundleIdentifiers: context.runningBundleIdentifiers, maximumDepth: 12, maximumEntries: 30_000)
        let actual = inventory.applications.first { $0.id.standardizedFileURL.path == ownerURL.path }
        if candidate.category == .application {
            guard let actual, actual.bundleIdentifier == identifier, !actual.isRunning, !actual.isSystem else {
                throw ApplicationExecutionRejection.ownershipChanged
            }
            // The user selected the app bundle itself. Revalidate its identity,
            // running state, and system status, then let the executor quarantine
            // it. Installation receipts and service references govern associated
            // files; they do not silently cancel this explicit uninstall action.
        } else {
            // The body may already have been moved by this same transaction.
            // Retain its recorded identity solely as an ownership anchor; never
            // mistake an absent body for permission to delete another copy's data.
            let anchor = actual ?? InstalledApplication(bundleURL: ownerURL, bundleIdentifier: identifier, name: name, version: nil, isRunning: context.runningBundleIdentifiers.contains(identifier), isSystem: false)
            guard anchor.bundleIdentifier == identifier, !anchor.isRunning else { throw ApplicationExecutionRejection.ownershipChanged }
            let index = await scanner.associationIndex(for: inventory.applications + (actual == nil ? [anchor] : []), context: context)
            guard index.ownershipGraph?.application(at: ownerURL)?.blocksAssociationDeletion == false else {
                throw ApplicationExecutionRejection.managedInstallation
            }
            guard let associations = index.associations.first(where: { $0.key.path == ownerURL.path })?.value,
                  let association = associations.first(where: { $0.url.standardizedFileURL.path == candidate.url.standardizedFileURL.path }),
                  association.risk.isSelectable, !association.isShared,
                  association.isSystemResource != true, association.references?.isEmpty != false else {
                throw ApplicationExecutionRejection.stillReferenced
            }
        }
    }
}
