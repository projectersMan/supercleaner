import Foundation

extension ApplicationInventory {
    /// Only shared-residue classification needs the full nested-code declaration pass.
    func completingSharedGroupDeclarations(ifNeededFor context: ScanContext? = nil) async -> ApplicationInventory {
        if let context {
            let roots = ["Library/Group Containers", "Library/Containers"].map { context.homeDirectory.appendingPathComponent($0) }
            // An empty/absent/inaccessible container root has no candidates whose
            // classification could benefit from inspecting every nested executable.
            var hasContainers = false
            for root in roots {
                if let entries = try? await context.fileSystem.children(of: root), !entries.isEmpty { hasContainers = true; break }
            }
            guard hasContainers else { return self }
        }
        // A complete declaration pass is useful only for proving that a shared
        // container is orphaned. Bound the aggregate work across all installed
        // applications; exhausted coverage remains conservative and therefore
        // cannot grant deletion eligibility.
        let declarationDeadline = Date().addingTimeInterval(5)
        var inspected: [InstalledApplication] = []
        for app in applications {
            if app.applicationGroupsComplete == true { inspected.append(app); continue }
            guard Date() < declarationDeadline else {
                inspected.append(InstalledApplication(bundleURL: app.bundleURL, bundleIdentifier: app.bundleIdentifier,
                    name: app.name, version: app.version, isRunning: app.isRunning, isSystem: app.isSystem,
                    teamIdentifier: app.teamIdentifier, applicationGroups: app.applicationGroups ?? [],
                    associatedBundleIdentifiers: app.associatedBundleIdentifiers, applicationGroupsComplete: false,
                    uninstallRequiresAdministrator: app.uninstallRequiresAdministrator))
                continue
            }
            let declarations = ApplicationGroupDeclarationScanner().scan(
                app.bundleURL,
                deadline: declarationDeadline,
                maximumEntries: 10_000
            )
            inspected.append(InstalledApplication(bundleURL: app.bundleURL, bundleIdentifier: app.bundleIdentifier,
                name: app.name, version: app.version, isRunning: app.isRunning, isSystem: app.isSystem,
                teamIdentifier: app.teamIdentifier, applicationGroups: Array(Set((app.applicationGroups ?? []) + declarations.groups)).sorted(),
                associatedBundleIdentifiers: Array(Set((app.associatedBundleIdentifiers ?? [])
                    + declarations.bundleIdentifiers.filter { $0 != app.bundleIdentifier })).sorted(),
                applicationGroupsComplete: declarations.complete,
                uninstallRequiresAdministrator: app.uninstallRequiresAdministrator))
        }
        return .init(applications: inspected, coverage: coverage, scannedAt: scannedAt)
    }
}
