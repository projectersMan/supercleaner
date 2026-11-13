import Foundation

/// Retain confirmed source removals for one scan generation. Later module
/// publications may have read those paths before cleanup completed.
public struct ScanCleanupReconciliation: Sendable {
    public let generationID: UUID
    public private(set) var revision = 0
    private var removals: [String: OperationResult] = [:]

    public init(generationID: UUID) { self.generationID = generationID }

    public mutating func record(_ results: [OperationResult]) {
        for result in results where result.removesSourceFromScan {
            let path = CleanupPathIndex.path(result.originalURL)
            if removals.updateValue(result, forKey: path) == nil { revision += 1 }
        }
    }

    public func applying(to report: SystemScanReport) -> SystemScanReport {
        guard report.generationID == generationID, !removals.isEmpty else { return report }
        return report.reconcilingCleanup(Array(removals.values))
    }
}

private extension OperationResult {
    var removesSourceFromScan: Bool {
        countsAsCleanedContent || (status == .sourceMissing && disposition == .skipped)
    }
}

extension SystemScanReport {
    /// Apply confirmed file effects to the existing snapshot without a new scan
    /// or new ownership decisions. Confirmed absent sources are removed without
    /// counting as cleanup; other failed/skipped/uncertain items remain visible.
    public func reconcilingCleanup(_ receipt: OperationReceipt) -> SystemScanReport {
        reconcilingCleanup(receipt.results)
    }

    public func reconcilingCleanup(_ results: [OperationResult]) -> SystemScanReport {
        let removed = Set(results.filter(\.removesSourceFromScan).map { CleanupPathIndex.path($0.originalURL) })
        let changed = Set(results.filter { $0.status == .skippedIdentityChanged }.map(\.candidateID))
        guard !removed.isEmpty || largeFileCandidates.contains(where: { $0.largeFileProof != nil && changed.contains($0.id) })
        else { return self }
        let removedPaths = CleanupPathIndex(paths: removed)
        var removalCache = [String: Bool]()
        func isRemoved(_ url: URL) -> Bool {
            let path = url.path
            if let cached = removalCache[path] { return cached }
            let result = removedPaths.contains(url)
            removalCache[path] = result
            return result
        }
        func remainingNode(_ node: DiskUsageNode) -> DiskUsageNode? {
            guard !isRemoved(node.url) else { return nil }
            guard case let .loaded(children) = node.children else { return node }
            let remaining = children.compactMap(remainingNode)
            let previousBytes = children.reduce(UInt64(0)) { $0 + $1.recursiveBytes }
            let remainingBytes = remaining.reduce(UInt64(0)) { $0 + $1.recursiveBytes }
            let removedBytes = previousBytes - min(previousBytes, remainingBytes)
            return DiskUsageNode(url: node.url, kind: node.kind, ownBytes: node.ownBytes,
                recursiveBytes: node.recursiveBytes - min(node.recursiveBytes, removedBytes),
                childCount: max(0, node.childCount - (children.count - remaining.count)),
                modifiedAt: node.modifiedAt, isReadable: node.isReadable, children: .loaded(remaining), identity: node.identity)
        }
        let disk = DiskUsageTree(roots: diskUsageTree.roots.compactMap(remainingNode),
            largeFiles: diskUsageTree.largeFiles.filter { !isRemoved($0.url) },
            minimumFileBytes: diskUsageTree.minimumFileBytes, coverage: diskUsageTree.coverage,
            scannedAt: diskUsageTree.scannedAt, analysisState: diskUsageTree.analysisState)
        let apps = ApplicationInventory(applications: applicationInventory.applications.filter { !isRemoved($0.id) },
            coverage: applicationInventory.coverage, scannedAt: applicationInventory.scannedAt)
        let uninstall = ApplicationUninstallInventory(applicationInventory: apps,
            analyses: applicationUninstallInventory.analyses.filter { !isRemoved($0.id) }.map { analysis in
                let plan = analysis.plan.map {
                    UninstallPlan(id: $0.id, application: $0.application, items: $0.items.filter { !isRemoved($0.candidate.url) })
                }
                let preparedPlan = analysis.preparedPlan.map {
                    UninstallPlan(id: $0.id, application: $0.application, items: $0.items.filter { !isRemoved($0.candidate.url) })
                }
                let observation = analysis.runtimeObservation.map {
                    ApplicationRuntimeObservation(directories: $0.directories.filter { !isRemoved($0) },
                        sampleCount: $0.sampleCount, state: $0.state, observedAt: $0.observedAt)
                }
                return ApplicationUninstallAnalysis(application: analysis.application, plan: plan, state: analysis.state,
                    message: analysis.message, limitations: analysis.limitations, ownership: analysis.ownership, runtimeObservation: observation,
                    preparedPlan: preparedPlan, preparedState: analysis.preparedState, preparedMessage: analysis.preparedMessage)
            }, associationCoverage: applicationUninstallInventory.associationCoverage,
            ownershipGraph: applicationUninstallInventory.ownershipGraph,
            associationIndex: applicationUninstallInventory.associationIndex.map { index in
                ApplicationAssociationIndex(associations: index.associations.filter { !isRemoved($0.key) }
                    .mapValues { $0.filter { !isRemoved($0.url) } }, coverage: index.coverage, ownershipGraph: index.ownershipGraph)
            })
        func updatingProof(_ candidate: CleanupCandidate) -> CleanupCandidate {
            guard let proof = candidate.largeFileProof,
                  changed.contains(candidate.id) || proof.retained.contains(where: { $0.isWithin(any: removed) })
            else { return candidate }
            return candidate.withLargeFileProof(nil)
        }
        let general = generalCandidates.filter { !isRemoved($0.url) }
        let removedGeneralRoots = Set(generalCandidates.filter { isRemoved($0.url) }.map { $0.url.standardizedFileURL.path })
        let otherScannedRoots = Set((applicationInventory.coverage.scannedRoots + diskUsageTree.coverage.scannedRoots
            + agentScanCoverage.scannedRoots).map(\.path))
        return SystemScanReport(snapshot: self,
            generalCandidates: general,
            applicationInventory: apps, applicationUninstallInventory: uninstall, diskUsageTree: disk,
            largeFileCandidates: largeFileCandidates.filter { !isRemoved($0.url) }.map(updatingProof),
            agentAssets: agentAssets.filter { !isRemoved($0.candidate.url) },
            agentSkills: agentSkills.filter { !isRemoved($0.skillRootURL) },
            candidates: candidates.filter { !isRemoved($0.url) }.map(updatingProof),
            coverage: coverage.removingScannedRoots(removedGeneralRoots.subtracting(otherScannedRoots)))
    }
}

/// Snapshot reconciliation is lexical: it must never query paths that have just been removed.
struct CleanupPathIndex {
    private final class Node {
        var removesSubtree = false
        var children: [Substring: Node] = [:]
    }
    private let root = Node()

    init(paths: Set<String>) {
        for path in paths {
            var node = root
            for part in path.split(separator: "/") {
                if let child = node.children[part] { node = child }
                else {
                    let child = Node()
                    node.children[part] = child
                    node = child
                }
            }
            node.removesSubtree = true
        }
    }
    static func path(_ url: URL) -> String {
        var components: [Substring] = []
        for part in url.path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(part) }
        }
        return "/" + components.joined(separator: "/")
    }
    func contains(_ url: URL) -> Bool {
        let parts = url.path.split(separator: "/")
        var components = [Substring]()
        for part in parts {
            if part == "." { continue }
            if part == ".." { if !components.isEmpty { components.removeLast() } }
            else { components.append(part) }
        }
        var node = root
        if node.removesSubtree { return true }
        for part in components {
            guard let child = node.children[part] else { return false }
            node = child
            if node.removesSubtree { return true }
        }
        return false
    }
}
