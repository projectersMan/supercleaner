import CleanerCore
import Foundation

/// Read-only synthetic data for the navigation performance regression check.
enum NavigationPresentationFixture {
    static let home = URL(fileURLWithPath: "/tmp/SuperCleaner-Navigation-Fixture")

    static func report() -> SystemScanReport {
        func candidate(_ index: Int, agent: Bool) -> CleanupCandidate {
            let url = home.appendingPathComponent(agent ? "agent/cache/item-\(index)" : "Library/Logs/item-\(index).log")
            return CleanupCandidate(url: url, displayName: url.lastPathComponent,
                category: agent ? .agentSandbox : .log, bytes: 100, risk: .safe, evidence: [],
                identity: .init(device: 1, inode: UInt64(index + 1), size: 100, modificationTime: 1, kind: .file),
                source: agent ? .agentWorkspace : .general, lastAccessDate: nil, isActive: false)
        }
        let assets = (0..<20_000).map { index in
            let item = candidate(index, agent: true)
            return AgentAssetRecord(candidate: item, provider: .codex, scope: .global,
                resourceKind: .buildCache, activity: .completed, cleanupEligibility: .retained,
                cleanupUnitURL: item.url)
        }
        return SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
                ($0, ScanModuleStatus(module: $0, state: .completed))
            }), generalCandidates: (0..<5_000).map { candidate($0, agent: false) },
            applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: assets)
    }
}
