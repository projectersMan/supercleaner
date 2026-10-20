import Foundation

public enum ApplicationSortOrder: String, CaseIterable, Sendable {
    case name
    case selection
    case directory

    public var displayTitle: String {
        switch self {
        case .name: L10n.text("按名称")
        case .selection: L10n.text("按选择")
        case .directory: L10n.text("按目录")
        }
    }

    /// Keeps checkbox state out of stable sort modes. Only the explicit selection
    /// mode is allowed to move checked applications ahead of unchecked ones.
    public func sorted(
        _ applications: [InstalledApplication],
        selectedApplicationURLs: Set<URL> = []
    ) -> [InstalledApplication] {
        applications.sorted { lhs, rhs in
            if self == .selection {
                let lhsSelected = selectedApplicationURLs.contains(lhs.bundleURL.standardizedFileURL)
                let rhsSelected = selectedApplicationURLs.contains(rhs.bundleURL.standardizedFileURL)
                if lhsSelected != rhsSelected { return lhsSelected }
            }
            if self == .directory {
                let lhsDirectory = lhs.bundleURL.deletingLastPathComponent().standardizedFileURL.path
                let rhsDirectory = rhs.bundleURL.deletingLastPathComponent().standardizedFileURL.path
                if lhsDirectory != rhsDirectory {
                    return lhsDirectory.localizedStandardCompare(rhsDirectory) == .orderedAscending
                }
            }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.bundleURL.path.localizedStandardCompare(rhs.bundleURL.path) == .orderedAscending
        }
    }
}
