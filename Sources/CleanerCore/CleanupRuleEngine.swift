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

    public init(pack: RulePack, operatingSystemVersion: String? = nil) {
        self.pack = pack
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.operatingSystemVersion = operatingSystemVersion ?? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public var scanners: [any Scanner] {
        pack.rules.filter { !pack.revokedRuleIDs.contains($0.ruleID) && supportsOS($0) }.map {
            CleanupRuleEngine(pack: RulePack(version: pack.version, issuedAt: pack.issuedAt, rules: [$0], revokedRuleIDs: pack.revokedRuleIDs), operatingSystemVersion: operatingSystemVersion)
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
        var results: [String: CleanupCandidate] = [:]
        // Exact rules take precedence over broad discovery rules.
        let rules = pack.rules.filter { !pack.revokedRuleIDs.contains($0.ruleID) && supportsOS($0) }
            .sorted { ($0.relativePaths.map(\.count).max() ?? 0) > ($1.relativePaths.map(\.count).max() ?? 0) }
        var reservedRoots: [URL] = []
        for rule in rules {
            var remaining = rule.maximumEntries ?? 20_000
            for relative in rule.relativePaths {
                try Task.checkCancellation()
                let root = context.homeDirectory.appendingPathComponent(relative).standardizedFileURL
                guard await context.fileSystem.fileExists(root) else { continue }
                let rootIdentity = try await context.fileSystem.identity(at: root)
                guard rootIdentity.kind == .directory else { continue }
                var pending: [(URL, Int)] = []
                if rule.granularity == .root { pending = [(root, 0)] }
                else { pending = try await context.fileSystem.children(of: root).map { ($0, 1) } }
                while let (url, depth) = pending.popLast() {
                    try Task.checkCancellation()
                    guard remaining > 0 else { throw RuleScanError.budgetExceeded(rule.ruleID) }
                    remaining -= 1
                    if reservedRoots.contains(where: { $0.path == url.path || $0.path.hasPrefix(url.path + "/") }) { continue }
                    let identity = try await context.fileSystem.identity(at: url)
                    if rule.granularity == .descendantFiles, identity.kind == .directory {
                        guard depth < (rule.maximumDepth ?? 6) else { throw RuleScanError.budgetExceeded(rule.ruleID) }
                        pending.append(contentsOf: try await context.fileSystem.children(of: url).map { ($0, depth + 1) })
                        continue
                    }
                    if let extensions = rule.fileExtensions, !extensions.contains(url.pathExtension.lowercased()) { continue }
                    if results[url.standardizedFileURL.path] != nil { continue }
                    let candidate = try await inspect(url, identity: identity, rule: rule, remaining: &remaining, context: context)
                    results[url.standardizedFileURL.path] = context.protectionPolicy.applying(to: candidate)
                }
            }
            reservedRoots.append(contentsOf: rule.relativePaths.map { context.homeDirectory.appendingPathComponent($0).standardizedFileURL })
        }
        return results.values.sorted { $0.url.path < $1.url.path }
    }

    public func validateForExecution(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard let id = candidate.ruleID else { return }
        guard let rule = pack.rules.first(where: { $0.ruleID == id }),
              !pack.revokedRuleIDs.contains(id), supportsOS(rule),
              rule.relativePaths.contains(where: {
                  let root = context.homeDirectory.appendingPathComponent($0).standardizedFileURL.path
                  return candidate.url.path == root || candidate.url.path.hasPrefix(root + "/")
              }) else { throw RuleScanError.ruleUnavailable(id) }
        var remaining = rule.maximumEntries ?? 20_000
        let inspected = try await inspect(candidate.url, identity: candidate.identity, rule: rule, remaining: &remaining, context: context)
        guard inspected.risk != .blocked else { throw RuleScanError.executionRefused(id) }
    }

    private func inspect(
        _ url: URL, identity: FileIdentity, rule: CleanupRule, remaining: inout Int,
        context: ScanContext
    ) async throws -> CleanupCandidate {
        var bytes: UInt64 = 0
        var newest = identity.modificationTime
        var blocked = false
        var incomplete = false
        var active = context.isActive(url)
            || !(rule.activeBundleIdentifiers ?? []).isDisjoint(with: context.runningBundleIdentifiers)
            || !(rule.activeProcessNames ?? []).isDisjoint(with: context.activeProcessNames)
            || ((rule.activeProcessNames?.isEmpty == false) && !context.activityProbeAvailable)
        var pending = [(url, identity, 0)]
        let protected = (rule.protectedRelativePaths ?? []).map { context.homeDirectory.appendingPathComponent($0) }
        var evidence = [Evidence(code: "cleanup-rule", summary: rule.ruleID, details: rule.sourceReference)]
        while let (entry, entryIdentity, depth) = pending.popLast() {
            try Task.checkCancellation()
            do { _ = try context.pathPolicy.validateCandidate(entry); try context.protectionPolicy.validate(entry) }
            catch { blocked = true }
            let path = entry.standardizedFileURL.path
            if protected.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") || $0.path.hasPrefix(path + "/") }) { blocked = true }
            if sensitive(entry) { blocked = true }
            if context.isActive(entry) { active = true }
            newest = max(newest, entryIdentity.modificationTime)
            guard await context.fileSystem.isReadable(entry) else { incomplete = true; continue }
            switch entryIdentity.kind {
            case .symbolicLink, .other: blocked = true
            case .file:
                let (sum, overflow) = bytes.addingReportingOverflow(entryIdentity.size)
                bytes = overflow ? .max : sum
            case .directory:
                guard depth < (rule.maximumDepth ?? 8), remaining > 0 else { incomplete = true; continue }
                do {
                    for child in try await context.fileSystem.children(of: entry) {
                        guard remaining > 0 else { incomplete = true; break }
                        remaining -= 1
                        do { pending.append((child, try await context.fileSystem.identity(at: child), depth + 1)) }
                        catch { incomplete = true }
                    }
                } catch { incomplete = true }
            }
        }
        let old = context.now.timeIntervalSince1970 - Double(newest) >= Double(rule.minimumAgeDays) * 86_400
        // Activity is advisory for general cleanup. The user may explicitly try
        // the item; the executor records a failed move and leaves it in place if
        // the owning process or filesystem refuses the operation.
        let risk: RiskLevel = blocked || incomplete ? .blocked : (old ? rule.defaultRisk : .review)
        if let regeneration = rule.regenerationEvidence { evidence.append(Evidence(code: "regeneration", summary: L10n.text(regeneration))) }
        if let ownership = rule.ownershipEvidence { evidence.append(Evidence(code: "ownership", summary: L10n.text(ownership))) }
        if active { evidence.append(Evidence(code: "active", summary: L10n.text("关联应用或工具正在使用，或活动状态无法验证"))) }
        if blocked { evidence.append(Evidence(code: "protected-content", summary: L10n.text("包含受保护、敏感或链接内容"))) }
        if incomplete { evidence.append(Evidence(code: "incomplete-inspection", summary: L10n.text("未完成目录验证，不可删除"))) }
        evidence.append(Evidence(code: "newest-modified", summary: L10n.text("目录内容按最新修改时间判断")))
        return CleanupCandidate(
            url: url, displayName: url.lastPathComponent, category: rule.category, bytes: bytes,
            risk: risk, evidence: evidence, identity: identity, source: .general,
            lastAccessDate: Date(timeIntervalSince1970: Double(newest)), isActive: active,
            ruleID: rule.ruleID, defaultSelection: risk == .safe && rule.defaultSelection == true
        )
    }

    private func supportsOS(_ rule: CleanupRule) -> Bool {
        (rule.minimumOSVersion.map { operatingSystemVersion.compare($0, options: .numeric) != .orderedAscending } ?? true)
            && (rule.maximumOSVersion.map { operatingSystemVersion.compare($0, options: .numeric) != .orderedDescending } ?? true)
    }

    private func sensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return [".git", "agents.md", "claude.md", "auth.json", "credentials.json", "id_rsa", "id_ed25519", "keychain", "keychain-db"].contains(name)
            || name == ".env" || name.hasPrefix(".env.") || ["pem", "p12", "pfx", "key"].contains(url.pathExtension.lowercased())
    }
}

public enum RuleScanError: Error, Sendable { case budgetExceeded(String), ruleUnavailable(String), executionRefused(String) }
