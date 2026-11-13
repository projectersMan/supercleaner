import CleanerCore
import Foundation

/// Prepared scan results, including two running apps, without real application operations.
enum ApplicationPresentationFixture {
    static let home = URL(fileURLWithPath: "/tmp/SuperCleaner-Application-Presentation-Fixture")

    static func report() -> SystemScanReport {
        let applications = (0..<114).map { index in
            InstalledApplication(bundleURL: home.appendingPathComponent("Applications/App-\(index).app"),
                bundleIdentifier: "org.example.app-\(index)", name: "App \(index)", version: "1",
                isRunning: index < 2, isSystem: false)
        }
        let analyses = applications.enumerated().map { index, application in
            let items = (0..<40).map { itemIndex in
                let url = itemIndex == 0 ? application.bundleURL
                    : home.appendingPathComponent("Library/Application Support/\(application.bundleIdentifier)/item-\(itemIndex)")
                let candidate = CleanupCandidate(url: url, displayName: url.lastPathComponent,
                    category: itemIndex == 0 ? .application : .applicationSupport,
                    bytes: 1_000, risk: .review, evidence: [],
                    identity: .init(device: 1, inode: UInt64(index * 40 + itemIndex + 1), size: 1_000,
                        modificationTime: 1, kind: .directory), source: .application, lastAccessDate: nil, isActive: false)
                return UninstallItem(candidate: candidate, containsUserData: false, isShared: false)
            }
            return ApplicationUninstallAnalysis(application: application.withRunningState(false),
                plan: UninstallPlan(application: application.withRunningState(false), items: items), state: .complete)
                .withRunningState(application.isRunning)
        }
        let inventory = ApplicationInventory(applications: applications, coverage: .init(), scannedAt: Date())
        return SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [.applications: .init(module: .applications, state: .completed)], generalCandidates: [],
            applicationInventory: inventory,
            applicationUninstallInventory: .init(applicationInventory: inventory, analyses: analyses),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: [])
    }
}
