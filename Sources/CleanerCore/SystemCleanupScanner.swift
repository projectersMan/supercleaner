import Foundation

/// The GUI and read-only CLI use the same discovery, bounds and selection facts.
public struct SystemCleanupScanner: Sendable {
    public let applicationScanner: ApplicationScanner
    public let coordinator: ScanCoordinator
    public init(applicationScanner: ApplicationScanner = ApplicationScanner(), coordinator: ScanCoordinator = ScanCoordinator()) {
        self.applicationScanner = applicationScanner; self.coordinator = coordinator
    }

    public func scan(context: ScanContext, pack: RulePack?) async -> ScanReport {
        let startedAt = Date()
        let effectivePack: RulePack
        do { effectivePack = try pack ?? BundledCleanupRules.pack() }
        catch {
            return ScanReport(candidates: [], failures: [ScanFailure(scannerID: "rules.current-pack",
                message: L10n.text("清理规则暂时无法读取"), reason: .access)], startedAt: startedAt, completedAt: Date())
        }
        let cleanupScanner = ApplicationCleanupScanner()
        let cleanupApps = await applicationScanner.installedApplications(context: context,
            runningBundleIdentifiers: context.runningBundleIdentifiers,
            maximumDepth: 12, maximumEntries: 30_000)
        var discovery = await cleanupScanner.discover(applications: cleanupApps.applications, context: context)
        // Keep reserved roots so a revoked app rule cannot reappear via the
        // broader generic cache rule.
        discovery.targets.removeAll { effectivePack.revokedRuleIDs.contains($0.ruleID) }
        discovery.failures += cleanupApps.coverage.unavailableRoots.map {
            ScanFailure(scannerID: "system-cleanup.apps", message: L10n.text("应用列表部分不可访问"), path: $0, reason: .access)
        }
        if !cleanupApps.coverage.budgetLimitedModules.isEmpty {
            discovery.failures.append(.init(scannerID: "system-cleanup.apps", message: L10n.text("达到扫描数量上限"), reason: .budget))
        }
        // Precise packaged rules keep priority over automatic app adaptation.
        do {
            let engine = CleanupRuleEngine(pack: effectivePack)
            let precise = effectivePack.rules.filter { !effectivePack.revokedRuleIDs.contains($0.ruleID)
                && engine.supportsOS($0) && $0.ruleID != "discovery.user-caches" && $0.ruleID != "general.logs" }
                .flatMap { $0.relativePaths }.map { context.homeDirectory.appendingPathComponent($0).path }
            discovery.targets.removeAll { target in precise.contains { target.url.path == $0 || target.url.path.hasPrefix($0 + "/") || $0.hasPrefix(target.url.path + "/") } }
            discovery.reservedRoots.removeAll { url in precise.contains { url.path == $0 || url.path.hasPrefix($0 + "/") || $0.hasPrefix(url.path + "/") } }
        }
        let dynamic: ScannerResult
        do { dynamic = try await cleanupScanner.scan(discovery: discovery, context: context) }
        catch { dynamic = ScannerResult(failures: [ScanFailure.from(error: error, scannerID: "system-cleanup.apps")]) }
        let scanned = await coordinator.scan(
            using: [
                CleanupRuleEngine(pack: effectivePack, excludedRoots: discovery.reservedRoots),
                InstallerScanner(), IncompleteDownloadScanner()
            ], context: context
        )
        let consolidated = scanned.candidates + dynamic.candidates
        let historicalResidues = await HistoricalResidueScanner().scan(context: context).filter { residue in
            !(consolidated.map(\.url) + discovery.reservedRoots).contains { root in
                residue.url.path == root.path || residue.url.path.hasPrefix(root.path + "/") || root.path.hasPrefix(residue.url.path + "/")
            }
        }
        let report = ScanReport(
            candidates: consolidated + historicalResidues,
            failures: scanned.failures + dynamic.failures, startedAt: startedAt, completedAt: Date()
        )
        return report
    }
}
