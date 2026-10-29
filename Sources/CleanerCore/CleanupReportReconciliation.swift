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
            let path = result.originalURL.standardizedFileURL.path
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
        let removed = Set(results.filter(\.removesSourceFromScan).map { $0.originalURL.standardizedFileURL.path })
        guard !removed.isEmpty else { return self }
        func isRemoved(_ url: URL) -> Bool {
            removed.contains { ApplicationOwnershipGraphBuilder.isWithin(url.standardizedFileURL.path, $0) }
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
                let observation = analysis.runtimeObservation.map {
                    ApplicationRuntimeObservation(directories: $0.directories.filter { !isRemoved($0) },
                        sampleCount: $0.sampleCount, state: $0.state, observedAt: $0.observedAt)
                }
                return ApplicationUninstallAnalysis(application: analysis.application, plan: plan, state: analysis.state,
                    message: analysis.message, limitations: analysis.limitations, ownership: analysis.ownership, runtimeObservation: observation)
            }, associationCoverage: applicationUninstallInventory.associationCoverage,
            ownershipGraph: applicationUninstallInventory.ownershipGraph)
        return SystemScanReport(metadata: metadata, modules: modules,
            generalCandidates: generalCandidates.filter { !isRemoved($0.url) },
            applicationInventory: apps, applicationUninstallInventory: uninstall, diskUsageTree: disk,
            largeFileCandidates: largeFileCandidates.filter { !isRemoved($0.url) },
            agentAssets: agentAssets.filter { !isRemoved($0.candidate.url) },
            agentSkills: agentSkills.filter { !isRemoved($0.skillRootURL) },
            agentMCPConfigurations: agentMCPConfigurations, agentProviderCoverage: agentProviderCoverage,
            agentSkillDuplicatesCollapsedCount: agentSkillDuplicatesCollapsedCount, agentScanCoverage: agentScanCoverage)
    }
}
