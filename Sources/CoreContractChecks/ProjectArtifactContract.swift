import CleanerCore
import Foundation

func runProjectArtifactContracts() async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("project-contract-\(UUID().uuidString)")
    let projects = home.appendingPathComponent("Projects")
    let project = projects.appendingPathComponent("example")
    let names = ["node_modules", "target", ".build", "build", "dist"]
    for name in names {
        let directory = project.appendingPathComponent(name)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: directory.appendingPathComponent("payload"))
    }
    defer { try? manager.removeItem(at: home) }
    try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
    let nested = project.appendingPathComponent(".build/.git")
    try manager.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("deployment fixture".utf8).write(to: project.appendingPathComponent("dist/deploy.key"))
    let outside = home.appendingPathComponent("outside")
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("external payload must survive".utf8).write(to: outside.appendingPathComponent("data"))
    try manager.createSymbolicLink(at: project.appendingPathComponent("node_modules/linked-package"), withDestinationURL: outside)
    let initialized = try await BoundedProcess.run("/usr/bin/git", arguments: ["-C", project.path, "init", "--quiet"])
    require(initialized.status == 0, "Git project fixture init failed")
    let added = try await BoundedProcess.run("/usr/bin/git", arguments: ["-C", project.path, "add", "--", "build/payload"])
    require(added.status == 0, "Git tracked fixture creation failed")
    let old = Date().addingTimeInterval(-40 * 86_400)
    try ageProjectFixture(project, at: old)
    try manager.setAttributes([.modificationDate: Date()], ofItemAtPath: project.appendingPathComponent("target/payload").path)
    // Link metadata is part of the artifact activity measurement, but its target
    // is never traversed or treated as owned project data.
    try manager.setAttributes([.modificationDate: old], ofItemAtPath: project.appendingPathComponent("node_modules").path)
    let context = ScanContext(homeDirectory: home)
    let scanner = ProjectArtifactScanner(roots: [projects])
    let report = try await scanner.scan(context: context)
    require(Set(report.artifacts.map { $0.candidate.displayName }) == Set(names), "project scanner must find all five requested artifact classes")
    require(report.artifacts.allSatisfy { $0.projectURL.lastPathComponent == "example" && $0.candidate.defaultSelection == false }, "project results must retain ownership and require explicit selection")
    func candidate(_ name: String) -> CleanupCandidate { report.artifacts.first { $0.candidate.displayName == name }!.candidate }
    require(candidate("build").risk == .blocked && candidate("build").evidence.contains { $0.code == "git-status" && $0.summary.contains("包含 Git") }, "Git tracked artifacts must be protected")
    require(candidate(".build").risk == .blocked && candidate(".build").evidence.contains { $0.code == "nested-git" }, "nested repositories must be protected")
    require(candidate("dist").risk == .blocked && candidate("dist").evidence.contains { $0.code == "deployment-key" }, "deployment keys must protect artifact directory")
    require(candidate("target").risk == .review && candidate("target").evidence.contains { $0.code == "recent-activity" }, "recent artifacts must remain unselected but manually reviewable")
    let safe = candidate("node_modules")
    require(safe.risk == .review && safe.bytes == 7, "dependency links must not traverse or count external data")
    let active = try await scanner.scan(context: ScanContext(homeDirectory: home, activePaths: [project]))
    require(active.artifacts.allSatisfy { $0.candidate.risk == .blocked }, "active project must be protected")
    let unknown = try await scanner.scan(context: ScanContext(homeDirectory: home, projectActivityAvailable: false))
    require(unknown.artifacts.allSatisfy { $0.candidate.risk == .blocked }, "unknown project activity must be protected")
    let protected = try await scanner.scan(context: ScanContext(homeDirectory: home, protectionPolicy: ProtectionPolicy(entries: [ProtectedPath(url: project.appendingPathComponent("node_modules/payload"))], homeDirectory: home)))
    require(protected.artifacts.first { $0.candidate.displayName == "node_modules" }?.candidate.risk == .blocked, "project artifacts must obey persistent protection")
    let limited = try await ProjectArtifactScanner(roots: [projects], maximumEntries: 1).scan(context: context)
    require(!limited.isComplete, "budgeted project scan must report partial state")
    let rootsStore = ProjectScanRootsStore(url: home.appendingPathComponent("settings/project-roots.json"), home: home)
    let custom = try await rootsStore.save([projects, projects])
    require(custom.count == 1, "custom project roots must deduplicate")
    let reloaded = try await rootsStore.roots()
    require(reloaded == custom, "custom project roots must persist")
    let defaults = try await ProjectScanRootsStore(url: home.appendingPathComponent("absent.json"), home: home).roots()
    require(defaults.contains { $0.path.hasSuffix(".codex/worktrees") }, "Agent worktrees must be valid discovery containers")
    let plan = try PlanBuilder(ruleVersion: "project-test").build(candidates: [safe], selectedIDs: [safe.id])
    let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: home), quarantineRoot: home.appendingPathComponent("quarantine"), currentRuleVersion: "project-test",
                                   validateCandidate: { try await scanner.validateForExecution($0, context: context) })
    let receipt = await executor.execute(plan: plan)
    require(receipt.results.first?.disposition == .quarantined, "verified project artifact must use normal isolation flow: \(receipt.results)")
    require(manager.fileExists(atPath: outside.appendingPathComponent("data").path), "project cleanup must not affect link target")
    let restored = await executor.restore(receipt: receipt)
    require(restored.results.first?.disposition == .restored && manager.fileExists(atPath: safe.url.path), "project artifact must restore through normal recovery flow")
    try Data("new key".utf8).write(to: safe.url.appendingPathComponent("new.key"))
    do { try await scanner.validateForExecution(safe, context: context); require(false, "execution must recheck newly introduced protected files") } catch is RuleScanError {}
    let cancelled = Task { try await scanner.scan(context: context) }
    cancelled.cancel()
    do { _ = try await cancelled.value; require(false, "cancelled project scan cannot publish results") } catch is CancellationError {}
    print("PASS: grouped project artifacts, Git/nested-repo/key/activity protection, roots and recoverable execution")
}

private func ageProjectFixture(_ project: URL, at date: Date) throws {
    let manager = FileManager.default
    guard let enumerator = manager.enumerator(at: project, includingPropertiesForKeys: nil) else { return }
    for case let url as URL in enumerator {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType != .typeSymbolicLink {
            try manager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }
}
