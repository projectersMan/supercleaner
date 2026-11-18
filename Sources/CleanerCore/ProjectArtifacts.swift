import Foundation

public struct ProjectArtifact: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let projectURL: URL
    public let candidate: CleanupCandidate
}

public struct ProjectScanReport: Codable, Sendable {
    public let startedAt: Date
    public let completedAt: Date
    public let roots: [URL]
    public let artifacts: [ProjectArtifact]
    public let limitations: [ScanLimitation]
    public let scanStatus: String
    public var isComplete: Bool { scanStatus == "complete" }
    public init(startedAt: Date, completedAt: Date, roots: [URL], artifacts: [ProjectArtifact], limitations: [ScanLimitation]) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.roots = roots
        self.artifacts = artifacts
        self.limitations = limitations
        scanStatus = limitations.isEmpty ? "complete" : "partial"
    }
}

public actor ProjectScanRootsStore {
    private let url: URL
    private let home: URL
    public init(url: URL, home: URL) { self.url = url; self.home = home }

    public func roots() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ["Projects", "Developer", "code", "GitHub", "dev", "src", "work", "repos"]
                .map { home.appendingPathComponent($0) }
                + AgentResourcePathRegistry.projectArtifactSeedPaths.map { home.appendingPathComponent($0) }
        }
        let paths = try JSONDecoder().decode([URL].self, from: Data(contentsOf: url))
        guard paths.allSatisfy(Self.valid) else { throw ProtectionError.invalidPath }
        return paths
    }

    @discardableResult public func save(_ paths: [URL]) throws -> [URL] {
        guard paths.allSatisfy(Self.valid) else { throw ProtectionError.invalidPath }
        let normalized = Array(Set(paths.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(normalized).write(to: url, options: .atomic)
        return normalized
    }

    private static func valid(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/") && url.path != "/" && !url.pathComponents.contains("..")
            && !url.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

public struct ProjectArtifactScanner: Sendable {
    public let roots: [URL]
    /// Legacy compatibility only; directory traversal has no depth cutoff.
    public let maximumDepth: Int
    public let maximumEntries: Int
    public let timeLimit: TimeInterval
    private static let artifactNames: Set<String> = ["node_modules", "target", ".build", "build", "dist"]
    private static let manifestNames: Set<String> = ["package.json", "Cargo.toml", "Package.swift", "pyproject.toml", "go.mod", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "pom.xml"]

    public init(roots: [URL], maximumDepth: Int = 8, maximumEntries: Int = 100_000, timeLimit: TimeInterval = 30) {
        self.roots = roots
        self.maximumDepth = max(1, maximumDepth)
        self.maximumEntries = max(1, maximumEntries)
        self.timeLimit = max(0.01, timeLimit)
    }

    public func scan(context: ScanContext) async throws -> ProjectScanReport {
        let startedAt = Date()
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeLimit))
        var remaining = maximumEntries
        var seen = Set<String>()
        var artifacts: [ProjectArtifact] = []
        var limitations: [ScanLimitation] = []
        for configured in roots {
            try Task.checkCancellation()
            guard await context.fileSystem.fileExists(configured) else { continue }
            let root = configured.resolvingSymlinksInPath().standardizedFileURL
            var queue: [(url: URL, depth: Int, project: URL?)] = [(root, 0, nil)]
            while let entry = queue.popLast() {
                try Task.checkCancellation()
                guard remaining > 0, ContinuousClock.now < deadline else {
                    limitations.append(limitation(entry.url, L10n.text("达到项目扫描预算"))); break
                }
                guard seen.insert(entry.url.path).inserted else { continue }
                remaining -= 1
                let children: [URL]
                do { children = try await context.fileSystem.children(of: entry.url) }
                catch { limitations.append(limitation(entry.url, L10n.text("目录无法读取"))); continue }
                let isProject = children.contains { Self.manifestNames.contains($0.lastPathComponent) }
                let project = isProject ? entry.url : entry.project
                for child in children {
                    try Task.checkCancellation()
                    guard remaining > 0, ContinuousClock.now < deadline else {
                        limitations.append(limitation(child, L10n.text("达到项目扫描预算"))); break
                    }
                    remaining -= 1
                    guard let identity = try? await context.fileSystem.identity(at: child) else { continue }
                    if identity.kind == .file, child.pathExtension.lowercased() == "dmg", let project {
                        artifacts.append(ProjectArtifact(projectURL: project,
                            candidate: try await inspectInstaller(child, project: project, context: context)))
                    }
                    guard identity.kind == .directory else { continue }
                    if Self.artifactNames.contains(child.lastPathComponent), let project {
                        let inspection = try await inspect(child, project: project, context: context, remaining: &remaining, deadline: deadline)
                        let candidate = inspection.candidate
                        artifacts.append(ProjectArtifact(projectURL: project, candidate: candidate))
                        artifacts.append(contentsOf: inspection.installers.map { ProjectArtifact(projectURL: project, candidate: $0) })
                        if candidate.evidence.contains(where: { ["inspection-budget", "inspection-failed"].contains($0.code) }) {
                            limitations.append(limitation(child, L10n.text("产物内容未完整验证")))
                        }
                    } else if !child.lastPathComponent.hasPrefix("."), child.pathExtension.lowercased() != "app" {
                        queue.append((child, entry.depth + 1, project))
                    }
                }
            }
        }
        let sorted = artifacts.sorted { $0.candidate.url.path < $1.candidate.url.path }
        let installers = sorted.map(\.candidate).filter { $0.identity.kind == .file && $0.url.pathExtension.lowercased() == "dmg" }
        let analysis = LargeFileContentAnalyzer(context: context, minimumBytes: 1, preselectInstallers: true)
            .analyze(installers.map { candidate in
                CleanupCandidate(id: candidate.id, url: candidate.url, displayName: candidate.displayName,
                    category: .largeFile, bytes: candidate.bytes, risk: candidate.risk, evidence: candidate.evidence,
                    identity: candidate.identity, source: .diskAnalysis, lastAccessDate: candidate.lastAccessDate,
                    isActive: candidate.isActive, requiresExplicitSelection: candidate.requiresExplicitSelection)
            })
        let reviewed = SystemScanReport.preservingProjectInstallerProofs(sorted.map(\.candidate), largeFiles: analysis.candidates)
        if analysis.limited { limitations.append(limitation(context.homeDirectory, L10n.text("重复大文件核验受限"))) }
        let result = zip(sorted, reviewed).map { ProjectArtifact(projectURL: $0.0.projectURL, candidate: $0.1) }
        return ProjectScanReport(startedAt: startedAt, completedAt: Date(), roots: roots, artifacts: result, limitations: limitations)
    }

    func installerPaths(in urls: [URL], context: ScanContext) async throws -> Set<String> {
        let configured = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        var paths = Set<String>()
        for url in urls where url.pathExtension.lowercased() == "dmg" {
            var directory = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            while configured.contains(where: { directory.path == $0 || directory.path.hasPrefix($0 + "/") }) {
                try Task.checkCancellation()
                var found = false
                for marker in Self.manifestNames {
                    if await context.fileSystem.fileExists(directory.appendingPathComponent(marker)) { found = true; break }
                }
                if found { paths.insert(url.standardizedFileURL.path); break }
                directory.deleteLastPathComponent()
            }
        }
        return paths
    }

    public func validateForExecution(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard candidate.source == .projectArtifacts else { return }
        guard let projectPath = candidate.evidence.first(where: { $0.code == "project-root" })?.details else {
            throw RuleScanError.executionRefused("missing-project-owner")
        }
        let project = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().standardizedFileURL
        let artifactPath = normalizedPath(candidate.url)
        let ownerPath = normalizedPath(project)
        let installer = candidate.identity.kind == .file && candidate.url.pathExtension.lowercased() == "dmg"
        guard (installer || Self.artifactNames.contains(candidate.url.lastPathComponent)), artifactPath.hasPrefix(ownerPath + "/"),
              roots.contains(where: { root in
                  let path = normalizedPath(root)
                  return ownerPath == path || ownerPath.hasPrefix(path + "/")
              }) else {
            throw RuleScanError.executionRefused("invalid-project-artifact")
        }
        let manifests = try await context.fileSystem.children(of: project)
        guard manifests.contains(where: { Self.manifestNames.contains($0.lastPathComponent) }) else { throw RuleScanError.executionRefused("project-manifest-missing") }
        if installer {
            let current = try await inspectInstaller(candidate.url, project: project, context: context)
            guard current.risk != .blocked else { throw RuleScanError.executionRefused("project-installer-changed") }
            return
        }
        var remaining = maximumEntries
        let current = try await inspect(candidate.url, project: project, context: context, remaining: &remaining,
                                        deadline: ContinuousClock.now.advanced(by: .seconds(timeLimit))).candidate
        guard current.risk != .blocked else { throw RuleScanError.executionRefused("project-changed") }
    }

    private func inspect(
        _ url: URL, project: URL, context: ScanContext, remaining: inout Int, deadline: ContinuousClock.Instant
    ) async throws -> (candidate: CleanupCandidate, installers: [CleanupCandidate]) {
        let identity = try await context.fileSystem.identity(at: url)
        var evidence = [Evidence(code: "project-root", summary: L10n.text("项目：{0}", String(describing: project.lastPathComponent)), details: project.path),
                        Evidence(code: "rebuildable-artifact", summary: L10n.text("项目工具生成的 {0} 目录，恢复前可能需要重新安装依赖或构建", String(describing: url.lastPathComponent)))]
        var blocked = identity.kind != .directory
        var active = context.isProjectActive(project)
        if !context.activityProbeAvailable || !context.projectActivityAvailable { active = true }
        var newest = identity.modificationTime
        var bytes: UInt64 = 0
        var pending = [(url, 0)]
        var budgetLimited = false
        var installers: [CleanupCandidate] = []
        while let (directory, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard remaining > 0, ContinuousClock.now < deadline else { blocked = true; budgetLimited = true; break }
            do {
                try context.protectionPolicy.validate(directory)
                _ = try context.pathPolicy.validateCandidate(directory)
                for child in try await context.fileSystem.children(of: directory) {
                    try Task.checkCancellation()
                    guard remaining > 0, ContinuousClock.now < deadline else { blocked = true; budgetLimited = true; break }
                    remaining -= 1
                    let childIdentity = try await context.fileSystem.identity(at: child)
                    newest = max(newest, childIdentity.modificationTime)
                    if child.lastPathComponent == ".git" { blocked = true; evidence.append(Evidence(code: "nested-git", summary: L10n.text("产物目录内含版本库，保持保护"))); continue }
                    if sensitive(child) { blocked = true; evidence.append(Evidence(code: "deployment-key", summary: L10n.text("含部署密钥或环境凭证，保持保护"))) }
                    if childIdentity.kind == .directory { pending.append((child, depth + 1)) }
                    else if childIdentity.kind == .file {
                        let (sum, overflow) = bytes.addingReportingOverflow(childIdentity.size)
                        bytes = overflow ? .max : sum
                        if child.pathExtension.lowercased() == "dmg" {
                            installers.append(try await inspectInstaller(child, project: project, context: context))
                        }
                    } else if childIdentity.kind == .other { blocked = true }
                    // Directory moves carry links without following their targets.
                }
            } catch is CancellationError { throw CancellationError() }
            catch { blocked = true; evidence.append(Evidence(code: "inspection-failed", summary: L10n.text("内容未完整验证，保持保护"))) }
        }
        if budgetLimited { evidence.append(Evidence(code: "inspection-budget", summary: L10n.text("达到产物检查预算，保持保护"))) }
        let git = await trackedFiles(in: url, project: project, context: context)
        if git == .unknown { blocked = true }
        evidence.append(Evidence(code: "git-status", summary: git == .untracked ? L10n.text("未包含 Git 跟踪文件") : git == .tracked ? L10n.text("包含 Git 跟踪文件，默认勾选由设置决定") : L10n.text("无法验证 Git 状态，保持保护")))
        let recent = context.now.timeIntervalSince1970 - Double(newest) < 7 * 86_400
        if recent { evidence.append(Evidence(code: "recent-activity", summary: L10n.text("7 天内有文件活动，默认保留；可明确审查后选择"))) }
        if active { blocked = true; evidence.append(Evidence(code: "active-project", summary: L10n.text("构建工具正在运行或活动状态无法验证"))) }
        let candidate = CleanupCandidate(
            url: url, displayName: url.lastPathComponent, category: .developerCache,
            bytes: bytes, risk: blocked ? .blocked : .review, evidence: Array(Set(evidence)).sorted { $0.code < $1.code },
            identity: identity, source: .projectArtifacts, lastAccessDate: Date(timeIntervalSince1970: Double(newest)),
            isActive: active, defaultSelection: false, requiresExplicitSelection: git == .tracked
        )
        return (context.protectionPolicy.applying(to: candidate), installers)
    }

    private func inspectInstaller(_ url: URL, project: URL, context: ScanContext) async throws -> CleanupCandidate {
        let identity = try await context.fileSystem.identity(at: url)
        var repository = url.deletingLastPathComponent()
        while repository.path != project.path && repository.path != "/" {
            if await context.fileSystem.fileExists(repository.appendingPathComponent(".git")) { break }
            repository.deleteLastPathComponent()
        }
        let git = await trackedFiles(in: url, project: repository, context: context)
        let active = context.isActive(url) || !context.activityProbeAvailable || !context.projectActivityAvailable
        let snapshot = LargeFileContentAnalyzer.eligibleSnapshot(url, context: context, installer: true,
            forManualSelection: git == .tracked)
        let eligible = identity.kind == .file && !active && git != .unknown && snapshot != nil
        var evidence = [Evidence(code: "project-root", summary: L10n.text("项目：{0}", project.lastPathComponent), details: project.path),
            InstallerDiscovery.formatEvidence("dmg"),
            Evidence(code: "git-status", summary: git == .untracked ? L10n.text("未包含 Git 跟踪文件")
                : git == .tracked ? L10n.text("包含 Git 跟踪文件，默认勾选由设置决定") : L10n.text("无法验证 Git 状态，保持保护"))]
        if snapshot == nil { evidence.append(Evidence(code: "inspection-failed", summary: L10n.text("内容未完整验证，保持保护"))) }
        if active { evidence.append(Evidence(code: "active-project", summary: L10n.text("文件正在使用，暂不可选择"))) }
        return context.protectionPolicy.applying(to: CleanupCandidate(url: url, displayName: url.lastPathComponent,
            category: .installerArtifact, bytes: identity.size, risk: eligible ? .review : .blocked, evidence: evidence,
            identity: identity, source: .projectArtifacts, lastAccessDate: nil, isActive: active, defaultSelection: false,
            requiresExplicitSelection: git == .tracked))
    }

    private enum Tracking { case tracked, untracked, unknown }
    private func trackedFiles(in artifact: URL, project: URL, context: ScanContext) async -> Tracking {
        var parent = project
        var hasRepository = false
        while parent.path != "/" {
            if await context.fileSystem.fileExists(parent.appendingPathComponent(".git")) { hasRepository = true; break }
            guard await context.fileSystem.isReadable(parent) else { return .unknown }
            parent = parent.deletingLastPathComponent()
        }
        guard hasRepository else { return .untracked }
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        do {
            let path = String(artifact.path.dropFirst(project.path.count + 1))
            let output = try await BoundedProcess.run("/usr/bin/git", arguments: ["--no-optional-locks", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-C", project.path, "ls-files", "-z", "--", path], timeout: 3, environment: environment)
            guard output.status == 0 else { return .unknown }
            return output.stdout.isEmpty ? .untracked : .tracked
        } catch { return .unknown }
    }

    private func sensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == ".env" || name.hasPrefix(".env.") || ["id_rsa", "id_ed25519", "credentials.json", "keypair.json"].contains(name)
            || ["pem", "key", "p12", "pfx"].contains(url.pathExtension.lowercased())
    }
    private func limitation(_ path: URL, _ reason: String) -> ScanLimitation {
        ScanLimitation(title: reason, path: path, impact: L10n.text("项目产物结果可能不完整；已验证项目仍可审查"), recovery: L10n.text("缩小扫描根或检查权限后重扫"))
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
