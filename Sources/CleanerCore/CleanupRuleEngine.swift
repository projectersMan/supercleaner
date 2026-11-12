import Foundation

public enum BundledCleanupRules {
    public static var url: URL {
        if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("SuperCleaner_CleanerCore.bundle", isDirectory: true),
           let bundle = Bundle(url: resourcesURL),
           let url = bundle.url(forResource: "base-rules", withExtension: "json") {
            return url
        }
        return Bundle.module.url(forResource: "base-rules", withExtension: "json")!
    }
    public static func pack() throws -> RulePack {
        try JSONDecoder().decode(RulePack.self, from: Data(contentsOf: url))
    }
}

public struct CleanupRuleEngine: Scanner {
    public var id: String { pack.rules.count == 1 ? "rule.\(pack.rules[0].ruleID)" : "rules.current-pack" }
    public let category = CleanupCategory.cache
    public let pack: RulePack
    public let operatingSystemVersion: String
    public let excludedRoots: [URL]
    public let allowOfflineContentRoots: [URL]

    public init(pack: RulePack, operatingSystemVersion: String? = nil, excludedRoots: [URL] = [],
                allowOfflineContentRoots: [URL] = []) {
        self.excludedRoots = excludedRoots.map(\.standardizedFileURL)
        self.allowOfflineContentRoots = allowOfflineContentRoots.map(\.standardizedFileURL)
        self.pack = pack
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.operatingSystemVersion = operatingSystemVersion ?? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public var scanners: [any Scanner] {
        pack.rules.filter { !pack.revokedRuleIDs.contains($0.ruleID) && supportsOS($0) }.map { rule in
            CleanupRuleEngine(pack: RulePack(version: pack.version, issuedAt: pack.issuedAt,
                rules: [rule], revokedRuleIDs: pack.revokedRuleIDs),
                operatingSystemVersion: operatingSystemVersion, excludedRoots: excludedRoots,
                allowOfflineContentRoots: allowOfflineContentRoots)
        }
    }

    public func consolidate(_ candidates: [CleanupCandidate], home: URL) -> [CleanupCandidate] {
        let activeRules = pack.rules.filter { !pack.revokedRuleIDs.contains($0.ruleID) && supportsOS($0) }
        let roots = activeRules.flatMap { rule in rule.relativePaths.map { (rule.ruleID, home.appendingPathComponent($0).standardizedFileURL.path) } }
        var seen = Set<String>()
        return candidates.filter { candidate in
            let path = candidate.url.standardizedFileURL.path
            if let id = candidate.ruleID {
                let ownLength = roots.filter { $0.0 == id && (path == $0.1 || path.hasPrefix($0.1 + "/")) }.map { $0.1.count }.max() ?? 0
                if roots.contains(where: { $0.0 != id && $0.1.count > ownLength && ($0.1 == path || $0.1.hasPrefix(path + "/")) }) { return false }
            }
            return seen.insert(path).inserted
        }
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        try await scanResult(context: context).candidates
    }

    public func scanResult(context: ScanContext) async throws -> ScannerResult {
        var output = ScannerResult()
        var seen = Set<String>()
        let rules = pack.rules.filter { !pack.revokedRuleIDs.contains($0.ruleID) && supportsOS($0) }
            .sorted { ($0.relativePaths.map(\.count).max() ?? 0) > ($1.relativePaths.map(\.count).max() ?? 0) }
        var reservedRoots = excludedRoots
        for rule in rules {
            for relative in rule.relativePaths {
                try Task.checkCancellation()
                let root = context.homeDirectory.appendingPathComponent(relative).standardizedFileURL
                guard await context.fileSystem.fileExists(root) else { continue }
                // Rule entry counts never truncate a scan. Cancellation remains cooperative.
                var pending: [(URL, Int)] = []
                do {
                    try Self.validateTraversal(root, context: context)
                    guard try await context.fileSystem.identity(at: root).kind == .directory else { continue }
                    if rule.granularity == .root { pending = [(root, 0)] }
                    else { pending = try await context.fileSystem.children(of: root).sorted { $0.path > $1.path }.map { ($0, 1) } }
                } catch {
                    output.failures.append(failure(error, path: root)); continue
                }
                while let (url, depth) = pending.popLast() {
                    try Task.checkCancellation()
                    if let registry = rule.referenceInventory?.registryDirectory, url == root.appendingPathComponent(registry) { continue }
                    if reservedRoots.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) { continue }
                    do {
                        try Self.validateTraversal(url, context: context)
                        let identity = try await context.fileSystem.identity(at: url)
                        let containsReserved = reservedRoots.contains { $0.path.hasPrefix(url.path + "/") }
                        if identity.kind == .directory && (rule.granularity == .descendantFiles || containsReserved) {
                            pending.append(contentsOf: try await context.fileSystem.children(of: url).sorted { $0.path > $1.path }.map { ($0, depth + 1) })
                            continue
                        }
                        if let extensions = rule.fileExtensions, !extensions.contains(url.pathExtension.lowercased()) { continue }
                        guard seen.insert(url.path).inserted else { continue }
                        let allowsOfflineContent = allowOfflineContentRoots.contains { $0.path == url.path }
                        let candidate = try await inspect(url, identity: identity, rule: rule,
                            context: context, allowOfflineContent: allowsOfflineContent)
                        output.candidates.append(context.protectionPolicy.applying(to: candidate))
                        for evidence in candidate.evidence where evidence.code.hasPrefix("scan-incomplete-") {
                            output.failures.append(ScanFailure(scannerID: id, message: evidence.summary,
                                path: url, reason: evidence.code == "scan-incomplete-budget" ? .budget : .access))
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { output.failures.append(failure(error, path: url)) }
                }
            }
            reservedRoots.append(contentsOf: rule.relativePaths.map { context.homeDirectory.appendingPathComponent($0).standardizedFileURL })
        }
        output.candidates.sort { $0.url.path < $1.url.path }
        return output
    }

    private func failure(_ error: Error, path: URL) -> ScanFailure {
        ScanFailure.from(error: error, scannerID: id, path: path)
    }

    static func validateTraversal(_ url: URL, context: ScanContext) throws {
        let checked = try context.pathPolicy.validateCandidate(url)
        let home = context.homeDirectory.standardizedFileURL
        guard checked.literal.path.hasPrefix(home.path + "/") else { throw PathPolicyError.outsideAllowedHome }
        let relative = String(checked.literal.path.dropFirst(home.path.count + 1))
        let expected = home.resolvingSymlinksInPath().appendingPathComponent(relative).standardizedFileURL
        guard expected.path == checked.physical.path else { throw PathPolicyError.protectedPath(url.path) }
    }

    public func validateForExecution(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard let id = candidate.ruleID else { return }
        guard let rule = pack.rules.first(where: { $0.ruleID == id }),
              !pack.revokedRuleIDs.contains(id), supportsOS(rule),
              rule.relativePaths.contains(where: {
                  let root = context.homeDirectory.appendingPathComponent($0).standardizedFileURL.path
                  return candidate.url.path == root || candidate.url.path.hasPrefix(root + "/")
              }) else { throw RuleScanError.ruleUnavailable(id) }
        if let descriptor = rule.referenceInventory {
            guard !context.isActive(candidate.url) else { throw RuleScanError.executionRefused(id) }
            if candidate.requiresExplicitSelection != true,
               CacheReferenceInventory.state(of: candidate.url, descriptor: descriptor) != .unused {
                throw RuleScanError.executionRefused(id)
            }
        }
        let allowsOfflineContent = allowOfflineContentRoots.contains { $0.path == candidate.url.path }
        let currentIdentity = try await context.fileSystem.identity(at: candidate.url)
        if candidate.hasVerifiedCleanupScope && candidate.source == .general && rule.defaultRisk != .blocked {
            do {
                try Self.validateTraversal(candidate.url, context: context)
                try context.protectionPolicy.validate(candidate.url)
            } catch { throw RuleScanError.executionRefused(id) }
            guard candidate.matchesExecutionIdentity(currentIdentity), !sensitive(candidate.url),
                  rule.fileExtensions.map({ $0.contains(candidate.url.pathExtension.lowercased()) }) ?? true else {
                throw RuleScanError.executionRefused(id)
            }
            for relative in rule.protectedRelativePaths ?? [] {
                let protected = context.homeDirectory.appendingPathComponent(relative).standardizedFileURL.path
                let path = candidate.url.standardizedFileURL.path
                if path == protected || path.hasPrefix(protected + "/") || protected.hasPrefix(path + "/") {
                    throw RuleScanError.executionRefused(id)
                }
            }
            // Fixed-cost exclusions catch newly created top-level secrets/offline data,
            // without walking or sizing the selected directory again.
            if currentIdentity.kind == .directory {
                for name in ["auth.json", "credentials.json", ".env", ".ssh", ".git", "Cookies", "Login Data", "Local Storage", "IndexedDB"] {
                    if await context.fileSystem.fileExists(candidate.url.appendingPathComponent(name)) { throw RuleScanError.executionRefused(id) }
                }
                if !allowsOfflineContent && candidate.requiresExplicitSelection != true {
                    for name in ["CacheStorage", "Service Worker", "ScriptCache"] {
                        if await context.fileSystem.fileExists(candidate.url.appendingPathComponent(name)) { throw RuleScanError.executionRefused(id) }
                    }
                }
            }
            return
        }
        let inspected = try await inspect(candidate.url, identity: currentIdentity, rule: rule,
            context: context, allowOfflineContent: allowsOfflineContent)
        guard inspected.risk != .blocked, !(inspected.requiresExplicitSelection == true && candidate.requiresExplicitSelection != true) else { throw RuleScanError.executionRefused(id) }
    }

    private func inspect(
        _ url: URL, identity: FileIdentity, rule: CleanupRule,
        context: ScanContext, allowOfflineContent: Bool = false
    ) async throws -> CleanupCandidate {
        var bytes: UInt64 = 0
        var newest = identity.modificationTime
        var blocked = false
        var incomplete = false
        // A runtime cache without regeneration or reference evidence follows the
        // same manual-selection rule, regardless of product name or location.
        var manualOnly = rule.requiresExplicitSelection == true
            || (rule.category == .developerCache && rule.defaultRisk != .safe
                && rule.regenerable != true && rule.referenceInventory == nil)
        var active = context.isActive(url)
            || !(rule.activeBundleIdentifiers ?? []).isDisjoint(with: context.runningBundleIdentifiers)
            || !(rule.activeProcessNames ?? []).isDisjoint(with: context.activeProcessNames)
            || ((rule.activeProcessNames?.isEmpty == false) && !context.activityProbeAvailable)
        var pending = [(url, identity, 0)]
        let protected = (rule.protectedRelativePaths ?? []).map { context.homeDirectory.appendingPathComponent($0) }
        let allowedSensitiveDirectoryNames = rule.allowedSensitiveDirectoryNames ?? []
        var evidence = [Evidence(code: "cleanup-rule", summary: rule.ruleID, details: rule.sourceReference)]
        while let (entry, entryIdentity, depth) = pending.popLast() {
            try Task.checkCancellation()
            // A framework link inside a known cache is part of that cache. Never follow it.
            if entryIdentity.kind == .symbolicLink,
               CacheLinkPolicy.permitsInternalLink(entry, within: url, allowed: rule.allowsInternalLinks == true) {
                do { try context.protectionPolicy.validate(entry) } catch { blocked = true }
                continue
            }
            do { try Self.validateTraversal(entry, context: context); try context.protectionPolicy.validate(entry) }
            catch { blocked = true; continue }
            let path = entry.standardizedFileURL.path
            if protected.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") || $0.path.hasPrefix(path + "/") }) { blocked = true }
            if sensitive(entry), !(entryIdentity.kind == .directory
                && allowedSensitiveDirectoryNames.contains(entry.lastPathComponent.lowercased())) {
                blocked = true
            }
            let isOfflineStorage = ["cachestorage", "service worker", "scriptcache"].contains(entry.lastPathComponent.lowercased())
            if isOfflineStorage && !allowOfflineContent {
                manualOnly = true
            }
            if context.isActive(entry) { active = true }
            newest = max(newest, entryIdentity.modificationTime)
            guard await context.fileSystem.isReadable(entry) else { incomplete = true; continue }
            switch entryIdentity.kind {
            case .symbolicLink, .other: blocked = true
            case .file:
                let (sum, overflow) = bytes.addingReportingOverflow(entryIdentity.size)
                bytes = overflow ? .max : sum
            case .directory:
                do {
                    for child in try await context.fileSystem.children(of: entry) {
                        do { pending.append((child, try await context.fileSystem.identity(at: child), depth + 1)) }
                        catch { incomplete = true }
                    }
                } catch { incomplete = true }
            }
        }
        let old = rule.minimumAgeDays <= 0
            || context.now.timeIntervalSince1970 - Double(newest) >= Double(rule.minimumAgeDays) * 86_400
        // Activity is advisory for general cleanup. The user may explicitly try
        // the item; the executor records a failed move and leaves it in place if
        // the owning process or filesystem refuses the operation.
        if let descriptor = rule.referenceInventory {
            let ownership = CacheReferenceInventory.state(of: url, descriptor: descriptor)
            manualOnly = manualOnly || ownership != .unused || !context.activityProbeAvailable
            active = context.isActive(url)
            if ownership == .metadata { manualOnly = true }
            evidence.append(Evidence(code: "cache-reference-ownership", summary: ownership == .unused
                ? L10n.text("未发现已登记项目引用此版本，可清理旧运行文件")
                : ownership == .referenced ? L10n.text("仍有已登记项目声明使用此版本")
                : L10n.text("安装索引或引用信息尚未完整确认")))
        }
        let risk: RiskLevel = blocked || incomplete ? .blocked : (old ? rule.defaultRisk : .review)
        if !blocked && !incomplete {
            evidence.append(Evidence(code: "verified-cleanup-scope", summary: rule.ruleID))
        }
        if !blocked && !incomplete && rule.regenerable == true {
            evidence.append(Evidence(code: "verified-regenerable-cache", summary: rule.ruleID))
        }
        if manualOnly { evidence.append(Evidence(code: "manual-only", summary:
            L10n.text(rule.manualExplanation ?? "必须逐项手动选择；清理后离线内容或共享缓存可能不可用"))) }
        if let regeneration = rule.regenerationEvidence { evidence.append(Evidence(code: "regeneration", summary: L10n.text(regeneration))) }
        if let ownership = rule.ownershipEvidence { evidence.append(Evidence(code: "ownership", summary: L10n.text(ownership))) }
        if active { evidence.append(Evidence(code: "active", summary: L10n.text("关联应用或工具正在使用，或活动状态无法验证"))) }
        if blocked { evidence.append(Evidence(code: "protected-content", summary: L10n.text("包含受保护、敏感或链接内容"))) }
        if incomplete {
            evidence.append(Evidence(code: "incomplete-inspection", summary: L10n.text("未完成目录验证，不可删除")))
            evidence.append(Evidence(code: "scan-incomplete-access", summary: L10n.text("部分内容不可读取或已变化")))
        }
        evidence.append(Evidence(code: "newest-modified", summary: L10n.text("目录内容按最新修改时间判断")))
        return CleanupCandidate(
            url: url, displayName: url.lastPathComponent, category: rule.category, bytes: bytes,
            risk: risk, evidence: evidence, identity: identity, source: .general,
            lastAccessDate: Date(timeIntervalSince1970: Double(newest)), isActive: active,
            ruleID: rule.ruleID, defaultSelection: risk == .safe && rule.defaultSelection == true && !manualOnly,
            requiresExplicitSelection: manualOnly
        )
    }

    func supportsOS(_ rule: CleanupRule) -> Bool {
        (rule.minimumOSVersion.map { operatingSystemVersion.compare($0, options: .numeric) != .orderedAscending } ?? true)
            && (rule.maximumOSVersion.map { operatingSystemVersion.compare($0, options: .numeric) != .orderedDescending } ?? true)
    }

    private func sensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".git", "agents.md", "claude.md", "auth.json", "credentials.json", "id_rsa", "id_ed25519", "keychain", "keychain-db", "cookies", "login data", "history", "local storage", "indexeddb", "messages", "message", "msg", "attachments", "backup", "backups"].contains(name)
            || name == ".env" || name.hasPrefix(".env.") || ["pem", "p12", "pfx", "key"].contains(url.pathExtension.lowercased())
    }
}

public enum RuleScanError: Error, Sendable { case budgetExceeded(String), ruleUnavailable(String), executionRefused(String) }
