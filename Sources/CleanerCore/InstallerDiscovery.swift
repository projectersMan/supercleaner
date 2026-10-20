import Foundation

public enum InstallerDiscoveryError: Error, Sendable {
    case deadlineExceeded, entryBudgetExceeded, depthBudgetExceeded(URL), unreadableRoot(URL)
}

public struct InstallerDiscovery: Sendable {
    public let maximumDepth: Int
    public let maximumEntries: Int
    public let timeLimit: TimeInterval
    public let additionalRoots: [URL]
    private let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]

    public init(maximumDepth: Int = 6, maximumEntries: Int = 25_000, timeLimit: TimeInterval = 20, additionalRoots: [URL] = []) {
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
        self.timeLimit = timeLimit
        self.additionalRoots = additionalRoots
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let clock = ContinuousClock()
        let start = clock.now
        func check() throws {
            try Task.checkCancellation()
            if start.duration(to: clock.now) >= .seconds(timeLimit) { throw InstallerDiscoveryError.deadlineExceeded }
        }
        func remainingSeconds() -> TimeInterval {
            let elapsed = start.duration(to: clock.now).components
            return max(0.01, timeLimit - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18)
        }
        let knownRoots: [(String, String)] = [
            ("Downloads", "下载"), ("Desktop", "桌面"),
            ("Library/Caches/Homebrew", "Homebrew 缓存"),
            ("Library/Mobile Documents/com~apple~CloudDocs/Downloads", "iCloud 下载"),
            ("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "邮件附件下载"),
            ("Library/Containers/ru.keepcoder.Telegram/Data/Downloads", "Telegram 下载"),
        ]
        var roots = knownRoots.map { (context.homeDirectory.appendingPathComponent($0.0).standardizedFileURL, $0.1) }
        roots.append(contentsOf: additionalRoots.map { ($0.standardizedFileURL, "自定义位置") })
        var remaining = maximumEntries
        var visited = Set<String>()
        var output: [CleanupCandidate] = []
        for (configuredRoot, source) in roots {
            try check()
            guard await context.fileSystem.fileExists(configuredRoot) else { continue }
            // Explicit root aliases are supported. Descendant symlinks never
            // expand the scan, and each final candidate gets a physical path.
            let configuredIdentity = try await context.fileSystem.identity(at: configuredRoot)
            let root = configuredIdentity.kind == .symbolicLink
                ? configuredRoot.resolvingSymlinksInPath().standardizedFileURL : configuredRoot
            guard await context.fileSystem.isReadable(root) else { throw InstallerDiscoveryError.unreadableRoot(configuredRoot) }
            var queue = [(root, 0)]
            while let (directory, depth) = queue.popLast() {
                try check()
                guard visited.insert(directory.path).inserted else { continue }
                let children = try await context.fileSystem.children(of: directory)
                for child in children {
                    try check()
                    guard remaining > 0 else { throw InstallerDiscoveryError.entryBudgetExceeded }
                    remaining -= 1
                    let url = child.standardizedFileURL
                    let identity = try await context.fileSystem.identity(at: url)
                    guard identity.kind == .file || identity.kind == .directory else { continue }
                    let ext = url.pathExtension.lowercased()
                    let isPackage = ["pkg", "mpkg"].contains(ext)
                    var recognized = extensions.contains(ext) && (identity.kind == .file || isPackage)
                    if ext == "zip", identity.kind == .file, await context.fileSystem.isReadable(url) {
                        do {
                            recognized = try await isInstallerArchive(url, timeout: min(3, remainingSeconds()))
                        } catch is CancellationError { throw CancellationError() }
                        catch ProcessFailure.cancelled { throw CancellationError() }
                        catch ProcessFailure.timedOut { throw InstallerDiscoveryError.deadlineExceeded }
                        catch { recognized = false }
                    }
                    if recognized {
                        let measured = try await measure(url, identity: identity, remaining: &remaining, context: context, check: check)
                        var risk: RiskLevel = .review
                        let active = context.isActive(url)
                        let readable = await context.fileSystem.isReadable(url)
                        if active || !measured.complete || !readable { risk = .blocked }
                        do { _ = try context.pathPolicy.validateCandidate(url) } catch { risk = .blocked }
                        let current = try await context.fileSystem.identity(at: url)
                        if current != identity { risk = .blocked }
                        output.append(context.protectionPolicy.applying(to: CleanupCandidate(
                            url: url, displayName: url.lastPathComponent, category: .installerArtifact,
                            bytes: measured.bytes, risk: risk,
                            evidence: [Evidence(code: "installer-source", summary: source, details: configuredRoot.path),
                                       Evidence(code: "installer-type", summary: ext == "zip" ? "已验证安装归档结构和完整性" : "安装文件格式：\(ext)"),
                                       Evidence(code: "manual-selection", summary: "已识别的安装包；安装完成且不再需要时可清理")],
                            identity: identity, source: .general, lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                            isActive: active, defaultSelection: false
                        )))
                    } else if identity.kind == .directory, ext != "app", ext != "download", !child.lastPathComponent.hasPrefix(".") {
                        guard depth < maximumDepth else { throw InstallerDiscoveryError.depthBudgetExceeded(url) }
                        queue.append((url, depth + 1))
                    }
                }
            }
        }
        try check()
        return output.sorted { $0.url.path < $1.url.path }
    }

    private func isInstallerArchive(_ url: URL, timeout: TimeInterval) async throws -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        let list = try await BoundedProcess.run("/usr/bin/zipinfo", arguments: ["-1", url.path], timeout: timeout)
        guard list.status == 0, let text = String(data: list.stdout, encoding: .utf8) else { return false }
        let entries = text.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else { return false }
        let installer = entries.contains {
            let lower = $0.lowercased()
            return lower.hasSuffix(".pkg") || lower.contains(".pkg/") || lower.hasSuffix(".mpkg")
                || lower.contains(".mpkg/") || lower.hasSuffix(".app/contents/info.plist")
        }
        guard installer else { return false }
        let elapsed = start.duration(to: clock.now).components
        let remaining = timeout - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18
        guard remaining > 0 else { throw ProcessFailure.timedOut }
        let checked = try await BoundedProcess.run("/usr/bin/unzip", arguments: ["-tqq", url.path], timeout: remaining, maximumOutputBytes: 65_536)
        return checked.status == 0
    }

    private func measure(
        _ url: URL, identity: FileIdentity, remaining: inout Int, context: ScanContext,
        check: () throws -> Void
    ) async throws -> (bytes: UInt64, complete: Bool) {
        if identity.kind == .file { return (identity.size, true) }
        var stack = [(url, 0)]
        var bytes: UInt64 = 0
        var complete = true
        while let (directory, depth) = stack.popLast() {
            try check()
            guard depth < maximumDepth else { complete = false; continue }
            for child in try await context.fileSystem.children(of: directory) {
                try check()
                guard remaining > 0 else { throw InstallerDiscoveryError.entryBudgetExceeded }
                remaining -= 1
                let childIdentity = try await context.fileSystem.identity(at: child)
                if childIdentity.kind == .directory { stack.append((child, depth + 1)) }
                else if childIdentity.kind == .file {
                    let (sum, overflow) = bytes.addingReportingOverflow(childIdentity.size)
                    bytes = overflow ? .max : sum
                } else { complete = false }
            }
        }
        return (bytes, complete)
    }
}
