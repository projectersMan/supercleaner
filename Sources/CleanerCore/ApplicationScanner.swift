import Foundation

public struct ApplicationScanner: Sendable {
    private let metadataProvider: any ApplicationMetadataProviding
    private let ownershipBuilder: ApplicationOwnershipGraphBuilder
    private let applicationRoots: [URL]?
    private let diagnosticScanner: ApplicationDiagnosticScanner

    public init(metadataProvider: (any ApplicationMetadataProviding)? = nil, ownershipBuilder: ApplicationOwnershipGraphBuilder = ApplicationOwnershipGraphBuilder(), applicationRoots: [URL]? = nil, diagnosticScanner: ApplicationDiagnosticScanner = ApplicationDiagnosticScanner()) {
        self.metadataProvider = metadataProvider ?? MemoizingApplicationMetadataProvider.shared
        self.ownershipBuilder = ownershipBuilder
        self.applicationRoots = applicationRoots
        self.diagnosticScanner = diagnosticScanner
    }

    /// Check a selected app directly without rediscovering every installed app.
    func installedApplication(at url: URL, context: ScanContext) async -> InstalledApplication? {
        guard (try? await context.fileSystem.identity(at: url))?.kind == .directory,
              let metadata = metadataProvider.metadata(for: url) else { return nil }
        return InstalledApplication(bundleURL: url, bundleIdentifier: metadata.bundleIdentifier,
            name: metadata.name, version: metadata.version,
            isRunning: context.runningBundleIdentifiers.contains(metadata.bundleIdentifier),
            isSystem: url.standardizedFileURL.path.hasPrefix("/System/") || InputMethodProtection.contains(url, home: context.homeDirectory),
            teamIdentifier: metadata.teamIdentifier, applicationGroups: metadata.applicationGroups,
            associatedBundleIdentifiers: metadata.associatedBundleIdentifiers, applicationGroupsComplete: metadata.applicationGroupsComplete)
    }

    public func installedApplications(
        context: ScanContext,
        runningBundleIdentifiers: Set<String> = [],
        maximumDepth: Int? = nil,
        maximumEntries: Int? = nil,
        additionalRoots: [URL] = []
    ) async -> ApplicationInventory {
        var roots = (applicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            context.homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ] + InputMethodProtection.applicationRoots(home: context.homeDirectory)) + additionalRoots
        // Only local mounted volumes, and only their Applications directories or
        // root-level app bundles. Never recurse through a whole backup/network disk.
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if applicationRoots == nil, let mounted = try? await context.fileSystem.children(of: volumes) {
            for volume in mounted.prefix(context.enforcesEntryBudgets ? 64 : mounted.count) where !volume.lastPathComponent.hasPrefix(".") {
                guard let values = try? volume.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey]),
                      values.volumeIsLocal == true else { continue }
                roots.append(volume.appendingPathComponent("Applications", isDirectory: true))
                if let entries = try? await context.fileSystem.children(of: volume) {
                    roots += entries.filter { $0.pathExtension.lowercased() == "app" }
                }
            }
        }
        var applications: [InstalledApplication] = []
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        if applicationRoots == nil {
            let steam = await LocalApplicationInstallationInspector.steamApplicationRoots(context: context)
            roots += steam.roots
            unavailableRoots += steam.unavailable
        }
        var seenPaths = Set<String>()
        var remainingEntries = context.enforcesEntryBudgets ? maximumEntries.map { max(0, $0) } : nil
        var reachedLimit = false

        rootLoop: for root in roots {
            if Task.isCancelled { break }
            let standardizedRoot = root.standardizedFileURL
            guard await context.fileSystem.fileExists(standardizedRoot) else { continue }
            guard await context.fileSystem.isReadable(standardizedRoot) else {
                unavailableRoots.append(standardizedRoot)
                continue
            }
            guard seenPaths.insert(standardizedRoot.path).inserted else { continue }
            scannedRoots.append(standardizedRoot)
            var queue: [(url: URL, depth: Int)] = [(standardizedRoot, 0)]
            if standardizedRoot.pathExtension.lowercased() == "app" {
                queue = [(standardizedRoot.deletingLastPathComponent(), 0)]
            }
            var nextQueueIndex = 0

            while nextQueueIndex < queue.count {
                if Task.isCancelled { break rootLoop }
                if let remainingEntries, remainingEntries == 0 {
                    reachedLimit = true
                    break
                }
                let current = queue[nextQueueIndex]
                nextQueueIndex += 1
                let children: [URL]
                do {
                    children = try await context.fileSystem.children(of: current.url)
                } catch {
                    unavailableRoots.append(current.url)
                    continue
                }

                for child in children {
                    if standardizedRoot.pathExtension.lowercased() == "app", child.standardizedFileURL != standardizedRoot { continue }
                    if let entriesLeft = remainingEntries {
                        guard entriesLeft > 0 else {
                            reachedLimit = true
                            break
                        }
                        remainingEntries = entriesLeft - 1
                    }
                    let url = child.standardizedFileURL
                    guard seenPaths.insert(url.path).inserted else { continue }

                    if url.pathExtension.lowercased() == "app" {
                        guard let metadata = metadataProvider.metadata(for: url) else { unavailableRoots.append(url); continue }
                        applications.append(InstalledApplication(
                            bundleURL: url,
                            bundleIdentifier: metadata.bundleIdentifier,
                            name: metadata.name,
                            version: metadata.version,
                            isRunning: runningBundleIdentifiers.union(context.runningBundleIdentifiers).contains(metadata.bundleIdentifier),
                            isSystem: url.path.hasPrefix("/System/") || InputMethodProtection.contains(url, home: context.homeDirectory),
                            teamIdentifier: metadata.teamIdentifier,
                            applicationGroups: metadata.applicationGroups,
                            associatedBundleIdentifiers: metadata.associatedBundleIdentifiers,
                            applicationGroupsComplete: metadata.applicationGroupsComplete
                        ))
                        continue
                    }

                    guard let identity = try? await context.fileSystem.identity(at: url),
                          identity.kind == .directory,
                          identity.kind != .symbolicLink,
                          await context.fileSystem.isReadable(url)
                    else { continue }
                    queue.append((url, current.depth + 1))
                }

                if reachedLimit, remainingEntries == 0 { break }
            }
            if reachedLimit, remainingEntries == 0 { break }
        }

        var uniqueByPath: [String: InstalledApplication] = [:]
        for application in applications {
            uniqueByPath[application.bundleURL.standardizedFileURL.path] = application
        }
        let sorted = uniqueByPath.values.sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame
                ? $0.bundleURL.path.localizedStandardCompare($1.bundleURL.path) == .orderedAscending
                : nameOrder == .orderedAscending
        }
        return ApplicationInventory(
            applications: sorted,
            coverage: CoverageSummary(
                scannedRoots: scannedRoots,
                unavailableRoots: unavailableRoots,
                budgetLimitedModules: reachedLimit ? [.applications] : []
            ),
            scannedAt: context.now
        )
    }

    public func associations(for application: InstalledApplication, context: ScanContext) async throws -> [ApplicationAssociation] {
        let inventory = await installedApplications(context: context, maximumEntries: 30_000)
        let applications = inventory.applications + (inventory.applications.contains { $0.id.path == application.id.path } ? [] : [application])
        let index = await associationIndex(for: applications, context: context)
        return index.associations.first { $0.key.path == application.id.path }?.value ?? []
    }

    public func associationIndex(
        for applications: [InstalledApplication],
        context: ScanContext,
        resourceURL: URL? = nil
    ) async -> ApplicationAssociationIndex {
        var output = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, [ApplicationAssociation]()) })
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        var limited = false
        let declarationDeadline = Date().addingTimeInterval(15)
        var declarations: [URL: [ApplicationAssociation]] = [:]
        var declarationsComplete = true
        let needsDeclarations = resourceURL == nil || resourceURL?.deletingLastPathComponent().standardizedFileURL.path
            == context.homeDirectory.appendingPathComponent("Library/Application Support").standardizedFileURL.path
        for application in needsDeclarations ? applications : [] {
            if Task.isCancelled || Date() >= declarationDeadline {
                limited = true; declarationsComplete = false; break
            }
            declarations[application.id] = await ApplicationDataDiscovery().associations(for: application, context: context)
        }
        // A truncated identity pass could miss another owner of a custom root.
        // Do not grant new deletion rights from that partial declaration set.
        if declarationsComplete {
            for (owner, values) in declarations { output[owner, default: []] += values }
        }
        // A declaration does not grant ownership of a shared search boundary.
        let sharedRootPaths = Set(ApplicationAssociationPathRegistry.roots(home: context.homeDirectory).map { $0.url.path })
        output = output.mapValues { $0.filter { !sharedRootPaths.contains($0.url.standardizedFileURL.path)
            && !ApplicationDiagnosticScanner.isDiagnosticDirectory($0.url, home: context.homeDirectory) } }
        let diagnostics = await diagnosticScanner.scan(applications: applications, context: context)
        for (owner, values) in diagnostics.associations { output[owner, default: []] += values }
        if let resourceURL {
            output = output.mapValues { $0.filter { $0.url.standardizedFileURL.path == resourceURL.standardizedFileURL.path } }
        }
        scannedRoots += diagnostics.coverage.scannedRoots
        unavailableRoots += diagnostics.coverage.unavailableRoots
        limited = limited || !diagnostics.coverage.budgetLimitedModules.isEmpty
        return await ownershipBuilder.build(
            applications: applications, associations: output,
            coverage: CoverageSummary(scannedRoots: scannedRoots, unavailableRoots: unavailableRoots, budgetLimitedModules: limited ? [.applications] : []), context: context,
            resourceURL: resourceURL
        )
    }
}
public struct UninstallPlanBuildResult: Sendable {
    public let plan: UninstallPlan
    public let reachedSizeBudget: Bool
    public let limitations: [ScanLimitation]

    public init(plan: UninstallPlan, reachedSizeBudget: Bool, limitations: [ScanLimitation] = []) {
        self.plan = plan
        self.reachedSizeBudget = reachedSizeBudget
        self.limitations = limitations
    }
}
