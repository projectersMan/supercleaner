import Foundation

/// Finds narrowly identifiable application data left in user library locations
/// after the corresponding application bundle disappeared. The scanner is
/// intentionally conservative: only exact reverse-DNS style names are
/// considered, and non-cache data remains review-only.
public struct HistoricalResidueScanner: Sendable {
    public let maximumEntries: Int
    public let maximumDepth: Int

    public init(maximumEntries: Int = 12_000, maximumDepth: Int = 4) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumDepth = max(1, maximumDepth)
    }

    public func scan(context: ScanContext) async -> [CleanupCandidate] {
        let inventory = await ApplicationScanner().installedApplications(
            context: context,
            runningBundleIdentifiers: context.runningBundleIdentifiers,
            maximumDepth: 12,
            maximumEntries: 30_000
        )
        let installedIDs = Set(inventory.applications.map { $0.bundleIdentifier.lowercased() })
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
            guard remaining > 0 else { break }
            let root = context.homeDirectory.appendingPathComponent(relativeRoot, isDirectory: true)
            guard await context.fileSystem.fileExists(root), await context.fileSystem.isReadable(root) else { continue }
            guard let children = try? await context.fileSystem.children(of: root) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                guard remaining > 0 else { break }
                remaining -= 1
                guard let identity = try? await context.fileSystem.identity(at: child),
                      identity.kind != .symbolicLink,
                      let identifier = Self.identifier(for: child.lastPathComponent),
                      !installedIDs.contains(identifier),
                      !identifier.hasPrefix("group."),
                      !identifier.hasPrefix("com.apple.") else { continue }
                guard !context.isActive(child) else { continue }

                let bytes = await measuredBytes(child, identity: identity, context: context)
                let emptyDirectory = identity.kind == .directory
                    ? await isEmptyDirectory(child, context: context)
                    : false
                let rebuildable = inventoryComplete && (cacheRoot || emptyDirectory)
                let risk: RiskLevel = rebuildable ? .safe : .review
                let evidence = [
                    Evidence(code: "historical-residue", summary: L10n.text("当前未发现对应应用")),
                    Evidence(code: "residue-bundle-id", summary: identifier),
                    Evidence(code: "residue-ownership", summary: L10n.text("名称与完整 Bundle ID 边界匹配；未发现当前应用所有者")),
                    Evidence(code: rebuildable ? (cacheRoot ? "rebuildable-cache" : "empty-residue") : "review-required", summary: rebuildable
                        ? (cacheRoot ? L10n.text("缓存目录可由应用重新生成") : L10n.text("目录为空，不包含用户内容"))
                        : L10n.text("可能包含用户数据或仍有重建成本")),
                ]
                let candidate = context.protectionPolicy.applying(to: CleanupCandidate(
                    url: child.standardizedFileURL,
                    displayName: child.lastPathComponent,
                    category: category,
                    bytes: bytes,
                    risk: risk,
                    evidence: evidence,
                    identity: identity,
                    source: .historicalApplicationResidue,
                    lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                    isActive: false,
                    ruleID: nil,
                    defaultSelection: risk == .safe
                ))
                results.append(candidate)
            }
        }
        return results.sorted { $0.url.path < $1.url.path }
    }

    private func isEmptyDirectory(_ url: URL, context: ScanContext) async -> Bool {
        guard let children = try? await context.fileSystem.children(of: url) else { return false }
        return children.isEmpty
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

    private func measuredBytes(_ url: URL, identity: FileIdentity, context: ScanContext) async -> UInt64 {
        if identity.kind == .file { return identity.size }
        var pending: [(URL, Int)] = [(url, 0)]
        var seen = Set<String>()
        var total: UInt64 = 0
        var remaining = 2_000
        while let (current, depth) = pending.popLast(), remaining > 0 {
            guard seen.insert(current.path).inserted,
                  let currentIdentity = try? await context.fileSystem.identity(at: current) else { continue }
            remaining -= 1
            if currentIdentity.kind == .file { total += currentIdentity.size; continue }
            guard depth < maximumDepth, let children = try? await context.fileSystem.children(of: current) else { continue }
            pending.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return total
    }
}
