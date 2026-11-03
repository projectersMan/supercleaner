import CryptoKit
import Foundation

/// Discovery boundaries are independent from uninstall ownership. Only cache
/// leaves and typed log files become cleanup candidates; user-data roots never do.
public struct ApplicationCleanupTarget: Sendable {
    public let url: URL
    public let application: InstalledApplication
    public let kind: String
    public let manualOnly: Bool
    public let allowOfflineContent: Bool
    public let logExtensions: Set<String>?

    var allowRuntimeCleanup: Bool { logExtensions == nil && !manualOnly }

    var ruleID: String {
        "system-cleanup.v1." + SHA256.hash(data: Data((application.bundleIdentifier + "|" + url.path).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func rule(home: URL, maximumEntries: Int) -> CleanupRule {
        CleanupRule(ruleID: ruleID, category: logExtensions == nil ? .cache : .log,
            relativePaths: [String(url.path.dropFirst(home.standardizedFileURL.path.count + 1))],
            minimumAgeDays: 0,
            defaultRisk: logExtensions == nil && !manualOnly ? .safe : .review,
            ownershipEvidence: application.bundleIdentifier,
            regenerationEvidence: manualOnly ? nil : "缓存可能需要重新下载，日志将不再保留",
            defaultSelection: logExtensions == nil && !manualOnly, sourceKind: "platform-convention-and-local-observation",
            sourceReference: "SRC-SYSTEM-APP-CLEANUP-001", testFixture: "SystemCleanupContract",
            granularity: logExtensions == nil ? .root : .descendantFiles,
            fileExtensions: logExtensions, activeBundleIdentifiers: [application.bundleIdentifier],
            maximumDepth: 16, maximumEntries: maximumEntries)
    }
}

public struct ApplicationCleanupDiscovery: Sendable {
    public var targets: [ApplicationCleanupTarget] = []
    /// Includes protected data boundaries even if no safe leaf exists.
    public var reservedRoots: [URL] = []
    public var failures: [ScanFailure] = []
}

public struct ApplicationCleanupScanner: Sendable {
    public let maximumEntries: Int
    public let maximumDiscoveryEntries: Int
    public init(maximumEntries: Int = 100_000, maximumDiscoveryEntries: Int = 10_000) {
        self.maximumEntries = maximumEntries; self.maximumDiscoveryEntries = maximumDiscoveryEntries
    }

    public func discover(applications: [InstalledApplication], context: ScanContext) async -> ApplicationCleanupDiscovery {
        var output = ApplicationCleanupDiscovery()
        let home = context.homeDirectory
        var seen = Set<String>()
        var listingCache: [URL: [URL]] = [:]
        let apps = applications.filter { !$0.bundleIdentifier.isEmpty }
        func list(_ root: URL) async -> [URL] {
            if let cached = listingCache[root] { return cached }
            guard !Task.isCancelled, await context.fileSystem.fileExists(root) else { return [] }
            do {
                try CleanupRuleEngine.validateTraversal(root, context: context)
                guard try await context.fileSystem.identity(at: root).kind == .directory else { return [] }
                let all = try await context.fileSystem.children(of: root).sorted { $0.path < $1.path }
                if context.enforcesEntryBudgets && all.count > maximumDiscoveryEntries {
                    output.failures.append(.init(scannerID: "system-cleanup.discovery", message: L10n.text("达到扫描数量上限"), path: root, reason: .budget))
                }
                let result = context.enforcesEntryBudgets ? Array(all.prefix(max(0, maximumDiscoveryEntries))) : all
                listingCache[root] = result
                return result
            } catch {
                output.failures.append(.init(scannerID: "system-cleanup.discovery", message: L10n.text("目录无法完整检查"), path: root, reason: .access))
                listingCache[root] = []
                return []
            }
        }
        func add(_ url: URL, app: InstalledApplication, kind: String, manual: Bool = false,
                 allowOfflineContent: Bool = false, logs: Set<String>? = nil) async {
            guard !Task.isCancelled, url.path.hasPrefix(home.path + "/"), await context.fileSystem.fileExists(url), seen.insert(url.path).inserted else { return }
            // Reserve before inspecting: a failed precise check must not fall
            // through to a broader, less restrictive deletion candidate.
            output.reservedRoots.append(url)
            do {
                try CleanupRuleEngine.validateTraversal(url, context: context)
                guard try await context.fileSystem.identity(at: url).kind == .directory else { return }
                output.targets.append(.init(url: url, application: app, kind: kind, manualOnly: manual,
                    allowOfflineContent: allowOfflineContent, logExtensions: logs))
            } catch {
                output.failures.append(.init(scannerID: "system-cleanup.discovery", message: L10n.text("目录无法完整检查"), path: url, reason: .access))
            }
        }
        let logExtensions: Set<String> = ["log", "xlog", "ips", "crash", "trace"]
        let registry = ApplicationAssociationPathRegistry.roots(home: home).filter {
            !$0.isSystem && [.cache, .log, .applicationSupport].contains($0.kind)
                && $0.url.deletingLastPathComponent() == home.appendingPathComponent("Library")
        }
        for root in registry {
            var entries = await list(root.url)
            for vendor in entries where root.isVendorDirectory(vendor, for: apps) {
                entries += await list(vendor)
            }
            for entry in entries {
                let owners = apps.filter { root.ownership(of: entry, application: $0) != nil }
                guard owners.count == 1, let app = owners.first else { continue }
                if app.bundleIdentifier == "com.google.Chrome" || app.bundleIdentifier == "com.tencent.xinWeChat" { continue }
                switch root.kind {
                case .cache: await add(entry, app: app, kind: L10n.text("应用缓存"))
                case .log: await add(entry, app: app, kind: L10n.text("应用日志"), logs: logExtensions)
                default:
                    for leaf in ["Cache", "Code Cache", "GPUCache", "DawnCache", "CachedData", "ShaderCache"] {
                        await add(entry.appendingPathComponent(leaf), app: app, kind: L10n.text("派生缓存"))
                    }
                    for leaf in ["logs", "Logs"] {
                        await add(entry.appendingPathComponent(leaf), app: app, kind: L10n.text("应用日志"), logs: logExtensions)
                    }
                    await add(entry.appendingPathComponent("Service Worker/CacheStorage"), app: app,
                        kind: L10n.text("网页离线内容"), manual: true)
                }
            }
        }
        for app in apps {
            // Exact bundle/group metadata only; fuzzy names never select a container.
            let identifiers = Set([app.bundleIdentifier] + (app.associatedBundleIdentifiers ?? []))
            for identifier in identifiers where safeComponent(identifier) {
                let library = home.appendingPathComponent("Library/Containers/\(identifier)/Data/Library")
                await add(library.appendingPathComponent("Caches"), app: app, kind: L10n.text("沙盒缓存"))
                await add(library.appendingPathComponent("Logs"), app: app, kind: L10n.text("应用日志"), logs: logExtensions)
            }
            for group in app.applicationGroups ?? [] where safeComponent(group) {
                // Shared caches need individual consent even with exact metadata.
                let root = home.appendingPathComponent("Library/Group Containers/\(group)/Library")
                await add(root.appendingPathComponent("Caches"), app: app, kind: L10n.text("共享缓存"), manual: true)
                await add(root.appendingPathComponent("Logs"), app: app, kind: L10n.text("应用日志"), manual: true, logs: logExtensions)
            }
            if app.bundleIdentifier == "com.google.Chrome" {
                let cache = home.appendingPathComponent("Library/Caches/Google/Chrome")
                let data = home.appendingPathComponent("Library/Application Support/Google/Chrome")
                output.reservedRoots += [cache, data]
                for base in [cache, data] {
                    for profile in await list(base) where Self.isChromeProfile(profile.lastPathComponent) {
                        for leaf in ["Cache", "Code Cache", "GPUCache", "DawnCache", "GrShaderCache", "GraphiteDawnCache"] {
                            await add(profile.appendingPathComponent(leaf), app: app, kind: L10n.text("浏览器缓存"))
                        }
                        if base == data {
                            for leaf in ["CacheStorage", "ScriptCache"] {
                                await add(profile.appendingPathComponent("Service Worker/" + leaf), app: app,
                                    kind: L10n.text("网页离线内容"), allowOfflineContent: true)
                            }
                        }
                    }
                    for leaf in ["ShaderCache", "GrShaderCache", "GraphiteDawnCache"] {
                        await add(base.appendingPathComponent(leaf), app: app, kind: L10n.text("派生缓存"))
                    }
                }
            }
            if app.bundleIdentifier == "com.tencent.xinWeChat" {
                let container = home.appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data")
                let documents = container.appendingPathComponent("Documents")
                // Current account roots are enumerated without opening messages or account files.
                if (app.version ?? "").hasPrefix("4.") {
                    for account in await list(documents.appendingPathComponent("xwechat_files")) where !account.lastPathComponent.hasPrefix(".") {
                        await add(account.appendingPathComponent("cache"), app: app, kind: L10n.text("微信缓存"))
                    }
                    await add(documents.appendingPathComponent("app_data/log"), app: app, kind: L10n.text("微信日志"), logs: ["xlog"])
                }
                // Legacy caches outside the sandbox remain separate from message storage.
                await add(home.appendingPathComponent("Library/Caches/com.tencent.xinWeChat"), app: app, kind: L10n.text("微信缓存"))
                await add(home.appendingPathComponent("Library/Logs/com.tencent.xinWeChat"), app: app, kind: L10n.text("微信日志"), logs: logExtensions)
                // Deliberately no msg, Message, Database, attachment, backup, temp or Downloads roots.
            }
        }
        // Shared containers or nested generic targets must never be counted twice.
        output.targets = output.targets.filter { target in
            !output.targets.contains { other in other.url != target.url && target.url.path.hasPrefix(other.url.path + "/") }
        }
        return output
    }

    static func isChromeProfile(_ name: String) -> Bool {
        name == "Default" || name == "Guest Profile" ||
            (name.hasPrefix("Profile ") && Int(name.dropFirst(8)) != nil)
    }

    private func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    public func scan(discovery: ApplicationCleanupDiscovery, context: ScanContext) async throws -> ScannerResult {
        var output = ScannerResult(failures: discovery.failures)
        for target in discovery.targets {
            try Task.checkCancellation()
            let rule = target.rule(home: context.homeDirectory, maximumEntries: maximumEntries)
            let result = try await CleanupRuleEngine(pack: RulePack(version: "system-cleanup-v1", issuedAt: .distantPast,
                rules: [rule], revokedRuleIDs: []),
                allowOfflineContentRoots: target.allowOfflineContent ? [target.url] : []).scanResult(context: context)
            output.failures += result.failures
            output.candidates += result.candidates.map { candidate in
                var evidence = candidate.evidence
                evidence.insert(Evidence(code: "application-cleanup", summary: target.application.name + " · " + target.kind,
                    details: target.application.bundleIdentifier), at: 0)
                let appIsActive = candidate.isActive || target.application.isRunning
                    || context.runningBundleIdentifiers.contains(target.application.bundleIdentifier)
                    || context.isActive(candidate.url)
                if target.allowRuntimeCleanup && appIsActive {
                    evidence.append(Evidence(code: "active-cleanup", summary: target.allowOfflineContent
                        ? L10n.text("应用运行中，缓存可能立即重新生成；离线页面可能暂时不可用")
                        : L10n.text("应用运行中，缓存可能立即重新生成")))
                }
                if target.manualOnly {
                    evidence.append(Evidence(code: "manual-only", summary: L10n.text("必须逐项手动选择；清理后离线内容或共享缓存可能不可用")))
                }
                return CleanupCandidate(id: candidate.id, url: candidate.url, displayName: candidate.displayName,
                    category: candidate.category, bytes: candidate.bytes, risk: candidate.risk, evidence: evidence,
                    identity: candidate.identity, source: .general, lastAccessDate: candidate.lastAccessDate,
                    isActive: target.allowRuntimeCleanup ? false : (candidate.isActive || target.application.isRunning), ruleID: rule.ruleID,
                    defaultSelection: candidate.defaultSelection, requiresExplicitSelection: target.manualOnly || candidate.requiresExplicitSelection == true,
                    cleanupApplication: CleanupApplication(bundleIdentifier: target.application.bundleIdentifier,
                        name: target.application.name, kind: target.kind, bundleURL: target.application.bundleURL))
            }
        }
        return output
    }

    public func validateForExecution(_ candidate: CleanupCandidate, context: ScanContext,
                                     applications: [InstalledApplication]) async throws {
        let discovery = await discover(applications: applications, context: context)
        guard let target = discovery.targets.first(where: { $0.ruleID == candidate.ruleID }),
              (target.logExtensions == nil ? candidate.url == target.url : candidate.url.path.hasPrefix(target.url.path + "/")),
              target.logExtensions.map({ $0.contains(candidate.url.pathExtension.lowercased()) }) ?? true,
              (!target.manualOnly || candidate.requiresExplicitSelection == true),
              target.allowRuntimeCleanup || (!target.application.isRunning
                && !context.runningBundleIdentifiers.contains(target.application.bundleIdentifier)
                && !context.isActive(candidate.url)) else {
            throw RuleScanError.executionRefused(candidate.ruleID ?? "system-cleanup")
        }
        let rule = target.rule(home: context.homeDirectory, maximumEntries: maximumEntries)
        try await CleanupRuleEngine(pack: RulePack(version: "system-cleanup-v1", issuedAt: .distantPast,
            rules: [rule], revokedRuleIDs: []),
            allowOfflineContentRoots: target.allowOfflineContent ? [target.url] : []).validateForExecution(candidate, context: context)
    }
}
