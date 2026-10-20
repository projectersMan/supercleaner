import Foundation

public enum LargeFileSortOrder: String, CaseIterable, Sendable {
    case size
    case selection
    case directory

    public var displayTitle: String {
        switch self {
        case .size: L10n.text("按大小")
        case .selection: L10n.text("按选择")
        case .directory: L10n.text("按目录")
        }
    }

    /// Sort each tree level without changing hierarchy or the identity of its rows.
    /// Only selection order depends on checkboxes, including selected descendants.
    public func sorted(_ nodes: [DiskUsageNode], selectedFileURLs: Set<URL> = []) -> [DiskUsageNode] {
        var selectedPaths = Set<String>()
        if self == .selection {
            for url in selectedFileURLs {
                var path = url.standardizedFileURL.path
                while true {
                    selectedPaths.insert(path)
                    guard path != "/", let separator = path.lastIndex(of: "/") else { break }
                    path = separator == path.startIndex ? "/" : String(path[..<separator])
                }
            }
        }
        return nodes.sorted { lhs, rhs in
            if self == .selection {
                let lhsSelected = selectedPaths.contains(lhs.url.path)
                let rhsSelected = selectedPaths.contains(rhs.url.path)
                if lhsSelected != rhsSelected { return lhsSelected }
            }
            if self == .directory {
                let lhsDirectory = lhs.kind == .directory ? lhs.url.path : lhs.url.deletingLastPathComponent().path
                let rhsDirectory = rhs.kind == .directory ? rhs.url.path : rhs.url.deletingLastPathComponent().path
                if lhsDirectory != rhsDirectory {
                    return lhsDirectory.localizedStandardCompare(rhsDirectory) == .orderedAscending
                }
            }
            if lhs.recursiveBytes != rhs.recursiveBytes { return lhs.recursiveBytes > rhs.recursiveBytes }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }
}
