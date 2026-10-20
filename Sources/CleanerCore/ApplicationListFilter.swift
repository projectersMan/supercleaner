import Foundation

public enum ApplicationListScope: String, CaseIterable, Sendable {
    case all
    case uninstallable
    case running
    case systemProtected

    public var displayTitle: String {
        switch self {
        case .all: L10n.text("全部")
        case .uninstallable: L10n.text("可卸载")
        case .running: L10n.text("运行中")
        case .systemProtected: L10n.text("系统保护")
        }
    }
}

public struct ApplicationListFilter: Sendable {
    public let query: String
    public let scope: ApplicationListScope

    public init(query: String, scope: ApplicationListScope) {
        self.query = query
        self.scope = scope
    }

    public func apply(to applications: [InstalledApplication]) -> [InstalledApplication] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return applications.filter { application in
            let matchesQuery = needle.isEmpty
                || application.name.localizedCaseInsensitiveContains(needle)
                || application.bundleIdentifier.localizedCaseInsensitiveContains(needle)
                || application.bundleURL.path.localizedCaseInsensitiveContains(needle)
            let matchesScope: Bool
            switch scope {
            case .all: matchesScope = true
            case .uninstallable: matchesScope = !application.isRunning && !application.isSystem
            case .running: matchesScope = application.isRunning
            case .systemProtected: matchesScope = application.isSystem
            }
            return matchesQuery && matchesScope
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func reconciledSelection(current: URL?, in applications: [InstalledApplication]) -> URL? {
        let visible = apply(to: applications)
        if let current, visible.contains(where: { $0.id == current }) { return current }
        return visible.first?.id
    }

    public func summary(for applications: [InstalledApplication]) -> ApplicationFilterSummary {
        ApplicationFilterSummary(
            visibleCount: apply(to: applications).count,
            totalCount: applications.count,
            canClear: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scope != .all
        )
    }
}

public struct ApplicationFilterSummary: Codable, Hashable, Sendable {
    public let visibleCount: Int
    public let totalCount: Int
    public let canClear: Bool

    public init(visibleCount: Int, totalCount: Int, canClear: Bool) {
        self.visibleCount = visibleCount
        self.totalCount = totalCount
        self.canClear = canClear
    }
}
