import CleanerCore
import Foundation

/// Read-only synthetic resources for the navigation regression check; no filesystem operation is performed.
enum ResourceCleanupPresentationFixture {
    static let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tests/dashboard-compact-trash/presentation-home")

    static func report() throws -> SystemScanReport {
        let models = [candidate("models/alpha", source: .localAIModels, bytes: 100),
            candidate("models/beta", source: .localAIModels, bytes: 200)]
        let projects = [candidate("code/Example/.build", source: .projectArtifacts, bytes: 300),
            candidate("code/Example/node_modules", source: .projectArtifacts, bytes: 400)]
        let entries = projects.map { ProjectEntry(projectURL: home.appendingPathComponent("code/Example"), candidate: $0) }
        let artifacts = try JSONDecoder().decode([ProjectArtifact].self, from: JSONEncoder().encode(entries))
        return SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
            modules: [.general: .init(module: .general, state: .completed),
                .localAIModels: .init(module: .localAIModels, state: .limited),
                .projects: .init(module: .projects, state: .completed)],
            generalCandidates: [candidate("Library/Logs/removed", source: .general, bytes: 500),
                candidate("Library/Logs/retained", source: .general, bytes: 600)],
            applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
            diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
            largeFileCandidates: [], agentAssets: [],
            localAIModelInventory: .init(models: models.map { LocalAIModelRecord(provider: .gpt4All, candidate: $0) },
                coverage: .init(), limitations: [], scannedAt: Date()),
            projectScanReport: .init(startedAt: Date(), completedAt: Date(), roots: [home.appendingPathComponent("code")],
                artifacts: artifacts, limitations: []))
    }

    static func installerReport() throws -> SystemScanReport {
        let url = home.appendingPathComponent("code/Example/.build/Release.dmg")
        let identity = FileIdentity(device: 1, inode: 42, size: 100, modificationTime: 1, kind: .file)
        let installer = CleanupCandidate(url: url, displayName: "Release.dmg", category: .installerArtifact,
            bytes: 100, risk: .review, evidence: [], identity: identity, source: .projectArtifacts,
            lastAccessDate: nil, isActive: false, defaultSelection: false)
        let large = CleanupCandidate(url: url, displayName: "Release.dmg", category: .largeFile,
            bytes: 100, risk: .review, evidence: [.init(code: "installer-type", summary: "DMG")],
            identity: identity, source: .diskAnalysis, lastAccessDate: nil, isActive: false, defaultSelection: true)
        let entries = [ProjectEntry(projectURL: home.appendingPathComponent("code/Example"), candidate: installer),
            ProjectEntry(projectURL: home.appendingPathComponent("code/Example"),
                candidate: candidate("code/Example/.build", source: .projectArtifacts, bytes: 300))]
        let artifacts = try JSONDecoder().decode([ProjectArtifact].self, from: JSONEncoder().encode(entries))
        let baseline = try report()
        return SystemScanReport(metadata: baseline.metadata, modules: [
            .projects: .init(module: .projects, state: .completed), .largeFiles: .init(module: .largeFiles, state: .completed)],
            generalCandidates: [], applicationInventory: baseline.applicationInventory,
            diskUsageTree: baseline.diskUsageTree, largeFileCandidates: [large], agentAssets: [],
            localAIModelInventory: .init(models: [], coverage: .init(), limitations: [], scannedAt: Date()),
            projectScanReport: .init(startedAt: Date(), completedAt: Date(), roots: [home.appendingPathComponent("code")],
                artifacts: artifacts, limitations: []))
    }

    private static func candidate(_ path: String, source: CandidateSource, bytes: UInt64) -> CleanupCandidate {
        let url = home.appendingPathComponent(path)
        return CleanupCandidate(url: url, displayName: url.lastPathComponent,
            category: source == .localAIModels ? .agentModelCache : source == .projectArtifacts ? .developerCache : .log,
            bytes: bytes, risk: source == .general ? .safe : .review, evidence: [],
            identity: .init(device: 1, inode: bytes, size: bytes, modificationTime: 1, kind: .directory),
            source: source, lastAccessDate: nil, isActive: false, defaultSelection: false,
            requiresExplicitSelection: source == .localAIModels || (source == .projectArtifacts && url.lastPathComponent == ".build"))
    }

    private struct ProjectEntry: Encodable {
        let projectURL: URL
        let candidate: CleanupCandidate
    }
}
