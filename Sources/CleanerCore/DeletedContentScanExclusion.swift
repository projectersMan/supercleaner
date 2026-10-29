import Foundation

/// Deleted content belongs in Recovery or Trash, never in cleanup discovery.
/// Resolve indexed aliases as well as checking literal directory boundaries.
struct DeletedContentScanExclusion: Sendable {
    private let rootPaths: [String]
    private let physicalRootPaths: [String]

    init(homeDirectory: URL) {
        let roots = ["Library/Application Support/SuperCleaner/Quarantine", ".Trash"]
            .map { homeDirectory.appendingPathComponent($0) }
        rootPaths = roots.map { $0.standardizedFileURL.path }
        physicalRootPaths = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if (rootPaths + physicalRootPaths).contains(where: { isWithin(path, $0) }) { return true }
        let physicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        return physicalRootPaths.contains { isWithin(physicalPath, $0) }
    }

    private func isWithin(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
