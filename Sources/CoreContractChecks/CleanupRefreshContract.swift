import CleanerCore
import Foundation

func runCleanupRefreshContracts() {
    func candidate(_ path: String, category: CleanupCategory = .largeFile, source: CandidateSource = .diskAnalysis) -> CleanupCandidate {
        .init(url: URL(fileURLWithPath: path), displayName: URL(fileURLWithPath: path).lastPathComponent,
            category: category, bytes: 100, risk: .review, evidence: [],
            identity: .init(device: 1, inode: 2, size: 100, modificationTime: 1, kind: category == .application ? .directory : .file),
            source: source, lastAccessDate: nil, isActive: false)
    }
    func node(_ c: CleanupCandidate) -> DiskUsageNode {
        .init(url: c.url, kind: .file, ownBytes: c.bytes, recursiveBytes: c.bytes, childCount: 0,
            modifiedAt: Date(), isReadable: true, children: .loaded([]), identity: c.identity)
    }
    let log = candidate("/tmp/refresh/log.txt")
    let failed = candidate("/tmp/refresh/failed.txt")
    let cancelled = candidate("/tmp/refresh/cancelled.txt")
    let uncertain = candidate("/tmp/refresh/uncertain.txt")
    let appBody = candidate("/Applications/Refresh.app", category: .application, source: .application)
    let cache = candidate("/tmp/refresh/app-cache", category: .cache, source: .application)
    let nested = candidate("/tmp/refresh/app-cache/large.bin")
    let sibling = candidate("/tmp/refresh/app-cache-other.bin")
    let app = InstalledApplication(bundleURL: appBody.url, bundleIdentifier: "com.contract.refresh", name: "Refresh", version: "1", isRunning: false, isSystem: false)
    let other = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Other.app"), bundleIdentifier: "com.contract.other", name: "Other", version: "1", isRunning: false, isSystem: false)
    let inventory = ApplicationInventory(applications: [app, other], coverage: .init(), scannedAt: Date())
    let plan = UninstallPlan(application: app, items: [appBody, cache].map { .init(candidate: $0, containsUserData: false, isShared: false) })
    let apps = ApplicationUninstallInventory(applicationInventory: inventory, analyses: [
        .init(application: app, plan: plan, state: .complete), .init(application: other, plan: nil, state: .unavailable)
    ])
    let files = [log, failed, cancelled, uncertain, nested, sibling]
    let children = files.map(node)
    let directory = DiskUsageNode(url: URL(fileURLWithPath: "/tmp/refresh"), kind: .directory, ownBytes: 10,
        recursiveBytes: 610, childCount: 6, modifiedAt: Date(), isReadable: true, children: .loaded(children))
    func report(indexed: Bool) -> SystemScanReport {
        .init(metadata: .init(generationID: UUID(), startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [.largeFiles: .init(module: .largeFiles, state: .limited)], generalCandidates: [log],
            applicationInventory: inventory, applicationUninstallInventory: apps,
            diskUsageTree: .init(roots: indexed ? children : [directory], largeFiles: children, minimumFileBytes: 50,
                coverage: .init(unavailableRoots: [URL(fileURLWithPath: "/tmp/unreadable")]), scannedAt: Date(),
                analysisState: indexed ? .indexedResults : .complete),
            largeFileCandidates: files, agentAssets: [])
    }
    func receipt(_ results: [OperationResult]) -> OperationReceipt {
        .init(planID: UUID(), startedAt: Date(), completedAt: Date(), results: results, overallStatus: .partial)
    }
    func success(_ c: CleanupCandidate) -> OperationResult {
        .init(candidateID: c.id, originalURL: c.url, disposition: .quarantined, status: .succeeded, bytes: c.bytes)
    }
    let partial = receipt([success(log), success(cache),
        .init(candidateID: failed.id, originalURL: failed.url, disposition: .failed, status: .failed, bytes: 100),
        .init(candidateID: cancelled.id, originalURL: cancelled.url, disposition: .skipped, status: .skippedCancelled, bytes: 100),
        .init(candidateID: uncertain.id, originalURL: uncertain.url, disposition: .failed, status: .failed, bytes: 100, verificationNotBefore: Date().addingTimeInterval(150))])
    for indexed in [true, false] {
        let original = report(indexed: indexed)
        let refreshed = original.reconcilingCleanup(partial)
        var overlay = ScanCleanupReconciliation(generationID: original.generationID)
        overlay.record(partial.results)
        overlay.record([success(appBody)])
        let latePublication = overlay.applying(to: original)
        require(latePublication.applicationInventory.applications.map(\.id) == [other.id]
            && latePublication.diskUsageTree.node(at: log.url) == nil,
                "a late scan publication must retain all confirmed cleanup effects")
        require([failed, cancelled, uncertain, sibling].allSatisfy { latePublication.diskUsageTree.node(at: $0.url) != nil },
                "a progressive cleanup overlay must preserve failed, canceled and uncertain sources")
        let revision = overlay.revision
        overlay.record(partial.results)
        require(overlay.revision == revision, "repeated execution callbacks do not create new removal revisions")
        let newGeneration = report(indexed: indexed)
        require(overlay.applying(to: newGeneration).diskUsageTree.node(at: log.url) != nil,
                "cleanup effects cannot hide files discovered by a later scan generation")
        require(refreshed.diskUsageTree.largeFiles.count == 4 && refreshed.largeFileCandidates.count == 4,
                "delete success removes both disk rows and actionable candidates, including directory descendants")
        require(refreshed.diskUsageTree.node(at: log.url) == nil && refreshed.diskUsageTree.node(at: nested.url) == nil,
                "deleted log and nested aliases must disappear immediately")
        require([failed, cancelled, uncertain, sibling].allSatisfy { refreshed.diskUsageTree.node(at: $0.url) != nil },
                "failed, cancelled, uncertain and similarly prefixed sibling files remain visible")
        require(refreshed.applicationInventory.applications.count == 2 && refreshed.applicationUninstallInventory.plans.first?.items.map(\.id) == [appBody.id],
                "deleting associated data removes that item while preserving the installed app")
        require(refreshed.diskUsageTree.roots.reduce(0) { $0 + $1.recursiveBytes } == (indexed ? 400 : 410),
                "displayed bytes must update for both indexed and hierarchical trees")
        require(refreshed.metadata == original.metadata && refreshed.modules == original.modules
            && refreshed.diskUsageTree.coverage == original.diskUsageTree.coverage,
                "reconciliation preserves scan age and limitations instead of pretending to rescan")
        let repeated = refreshed.reconcilingCleanup(partial)
        require(repeated.diskUsageTree == refreshed.diskUsageTree, "reapplying a receipt cannot subtract bytes twice")
        let uninstalled = refreshed.reconcilingCleanup(receipt([success(appBody)]))
        require(uninstalled.applicationInventory.applications.map(\.id) == [other.id]
            && uninstalled.applicationUninstallInventory.analysis(for: app.id) == nil,
                "confirmed app-body removal updates the app inventory and expanded list together")
        require(original.reconcilingCleanup(receipt([])).diskUsageTree == original.diskUsageTree, "empty receipts leave snapshots unchanged")
        let absent = OperationResult(candidateID: log.id, originalURL: log.url, disposition: .skipped, status: .sourceMissing, bytes: log.bytes)
        let withoutAbsent = original.reconcilingCleanup([absent])
        require(withoutAbsent.diskUsageTree.node(at: log.url) == nil && withoutAbsent.generalCandidates.isEmpty,
                "confirmed missing sources disappear across system and disk views")
        var cleaned = CleanupSessionSummary()
        cleaned.record(receipt([absent]))
        require(cleaned.itemCount == 0 && cleaned.bytes == 0, "missing files must never count as cleaned content")
    }
    print("PASS: cleanup refresh reconciles app lists, indexed/hierarchical disk rows, counts, bytes and partial/uncertain outcomes")
}
