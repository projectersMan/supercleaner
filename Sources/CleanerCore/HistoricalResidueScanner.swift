import Foundation

/// Finds narrowly identifiable application data left in user library locations
/// after the corresponding application bundle disappeared. The scanner is
/// limited to identifiable reverse-DNS names. Verified unowned
/// data is included in recommended cleanup; uncertain ownership stays manual.
public struct HistoricalResidueScanner: Sendable {
    public let maximumEntries: Int
    /// Legacy compatibility only; directory traversal has no depth cutoff.
    public let maximumDepth: Int

    public init(maximumEntries: Int = 12_000, maximumDepth: Int = 4) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumDepth = max(1, maximumDepth)
    }

    public func scan(context: ScanContext) async -> [CleanupCandidate] {
        let inventory = await ApplicationScanner().installedApplications(
            context: context,
            runningBundleIdentifiers: context.runningBundleIdentifiers,
            maximumEntries: 30_000
        )
        return await scan(context: context, inventory: inventory.completingSharedGroupDeclarations(ifNeededFor: context))
    }

    func scan(context: ScanContext, inventory: ApplicationInventory) async -> [CleanupCandidate] {
        let inventoryComplete = inventory.coverage.unavailableRoots.isEmpty
            && !inventory.coverage.budgetLimitedModules.contains(.applications)
        let roots: [(String, CleanupCategory, Bool)] = [
            ("Library/Caches", .cache, true),
            ("Library/Application Support", .applicationSupport, false),
            ("Library/Preferences", .applicationSupport, false),
            ("Library/Saved Application State", .applicationSupport, false),
            ("Library/Containers", .applicationSupport, false),
            ("Library/Group Containers", .applicationSupport, false),
        ]
        var remaining = maximumEntries
        var results: [CleanupCandidate] = []

        for (relativeRoot, category, cacheRoot) in roots {
            guard !Task.isCancelled else { break }
            guard (!context.enforcesEntryBudgets || remaining > 0) else { break }
            let sharedContainer = relativeRoot == "Library/Group Containers"
            let container = relativeRoot == "Library/Containers"
            let root = context.homeDirectory.appendingPathComponent(relativeRoot, isDirectory: true)
            guard await context.fileSystem.fileExists(root), await context.fileSystem.isReadable(root) else { continue }
            guard let children = try? await context.fileSystem.children(of: root) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                guard !Task.isCancelled else { break }
                guard (!context.enforcesEntryBudgets || remaining > 0) else { break }
                if context.enforcesEntryBudgets { remaining -= 1 }
                guard let identity = try? await context.fileSystem.identity(at: child),
                      identity.kind != .symbolicLink,
                      let identifier = Self.identifier(for: child.lastPathComponent),
                      !HistoricalResidueOwnership.hasOwner(identifier, applications: inventory.applications),
                      (sharedContainer || !identifier.hasPrefix("group.")),
                      !identifier.hasPrefix("com.apple."), !identifier.contains(".com.apple.") else { continue }
                guard !context.isActive(child),
                      !HistoricalResidueOwnership.hasRunningOwner(identifier, identifiers: context.runningBundleIdentifiers) else { continue }

                let inspection = await inspect(child, context: context)
                let sharedOwnershipComplete = !(sharedContainer || container)
                    || HistoricalResidueOwnership.sharedOwnershipComplete(inventory, context: context)
                let confirmed = inventoryComplete && inspection.complete && sharedOwnershipComplete
                let risk: RiskLevel = !inspection.complete ? .blocked : (confirmed ? .safe : .review)
                var evidence = [
                    Evidence(code: "historical-residue", summary: L10n.text("当前未发现对应应用")),
                    Evidence(code: "residue-bundle-id", summary: identifier),
                    Evidence(code: "residue-ownership", summary: L10n.text("名称与完整 Bundle ID 边界匹配；未发现当前应用所有者")),
                ]
                if sharedContainer { evidence.append(Evidence(code: "shared-residue", summary: identifier)) }
                if confirmed {
                    evidence.append(Evidence(code: "confirmed-residue", summary: L10n.text("已完成应用归属检查，未发现对应应用；此残留默认加入推荐清理")))
                    if cacheRoot { evidence.append(Evidence(code: "rebuildable-cache", summary: L10n.text("缓存目录可由应用重新生成"))) }
                } else if !inspection.complete {
                    evidence.append(Evidence(code: "scan-incomplete-residue", summary: L10n.text("未完成目录验证，不可删除")))
                } else {
                    evidence.append(Evidence(code: "review-required", summary: sharedContainer
                        ? L10n.text("部分应用或扩展的共享数据声明未完成检查，暂不默认选择此残留")
                        : L10n.text("应用扫描尚未完成，暂不默认选择此残留")))
                }
                let candidate = context.protectionPolicy.applying(to: CleanupCandidate(
                    url: child.standardizedFileURL,
                    displayName: child.lastPathComponent,
                    category: category,
                    bytes: inspection.bytes,
                    risk: risk,
                    evidence: evidence,
                    identity: identity,
                    source: .historicalApplicationResidue,
                    lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                    isActive: false,
                    ruleID: nil,
                    defaultSelection: confirmed, requiresExplicitSelection: !confirmed
                ))
                results.append(candidate)
            }
        }
        return results.sorted { $0.url.path < $1.url.path }
    }

    private static func identifier(for name: String) -> String? {
        var value = name.lowercased()
        for suffix in [".savedstate", ".plist"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        let parts = value.split(separator: ".")
        guard parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } })
        else { return nil }
        return value
    }

    private func inspect(_ url: URL, context: ScanContext) async -> (bytes: UInt64, complete: Bool) {
        // Root overlap checks cover protected descendants. Links below are never followed.
        do { try context.protectionPolicy.validate(url) } catch { return (0, false) }
        var pending = [url]
        var total: UInt64 = 0
        var complete = true
        var remaining = 2_000
        while let current = pending.popLast() {
            guard !Task.isCancelled, !context.enforcesEntryBudgets || remaining > 0 else { return (total, false) }
            if context.enforcesEntryBudgets { remaining -= 1 }
            guard let identity = try? await context.fileSystem.identity(at: current) else { complete = false; continue }
            // Sandboxed app containers include standard links to Desktop, Keychains,
            // etc. Removing the container removes these links, never their targets.
            if identity.kind == .symbolicLink { continue }
            // Ownership applies to the whole residue; payload readability is not
            // needed for a no-follow move (container metadata may be unreadable).
            guard identity.kind == .file || identity.kind == .directory else { complete = false; continue }
            guard !context.isActive(current) else { complete = false; continue }
            if identity.kind == .file {
                let (sum, overflow) = total.addingReportingOverflow(identity.size)
                total = overflow ? .max : sum
            } else if let children = try? await context.fileSystem.children(of: current) {
                pending.append(contentsOf: children)
            } else { complete = false }
        }
        return (total, complete)
    }

}

/// Bundle suffixes are preferences/extensions, not proof of a separate missing application.
enum HistoricalResidueOwnership {
    static func sharedOwnershipComplete(_ inventory: ApplicationInventory, context: ScanContext) -> Bool {
        inventory.coverage.unavailableRoots.isEmpty
            && !inventory.coverage.budgetLimitedModules.contains(.applications)
            && inventory.applications.allSatisfy { $0.applicationGroupsComplete == true }
            && context.activityProbeAvailable
            && context.runningBundleIdentifiers.allSatisfy { running in
                inventory.applications.contains { app in
                    ([app.bundleIdentifier] + (app.associatedBundleIdentifiers ?? [])).contains(running)
                }
            }
    }

    static func hasRunningOwner(_ identifier: String, identifiers: Set<String>) -> Bool {
        identifiers.contains { identifier.lowercased() == $0.lowercased() || identifier.lowercased().hasPrefix($0.lowercased() + ".") }
    }

    static func hasOwner(_ identifier: String, applications: [InstalledApplication]) -> Bool {
        let value = identifier.lowercased()
        return applications.contains { app in
            let identifiers = [app.bundleIdentifier] + (app.associatedBundleIdentifiers ?? []) + (app.applicationGroups ?? [])
            return identifiers.contains { known in
                let owner = known.lowercased()
                if value == owner || value.hasPrefix(owner + ".") { return true }
                if let team = app.teamIdentifier?.lowercased(), value == team + "." + owner || value.hasPrefix(team + "." + owner + ".") { return true }
                return false
            }
        }
    }
}
