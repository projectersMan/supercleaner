import Foundation

enum AgentCatalogPathPolicy {
    /// Inspect every literal component without resolving a link into its target.
    static func isDirectPath(_ url: URL, fileSystem: any FileSystemAccess) async -> Bool {
        guard url.isFileURL else { return false }
        var current = url.standardizedFileURL
        while current.path != "/" {
            guard let identity = try? await fileSystem.identity(at: current),
                  identity.kind != .symbolicLink else { return false }
            current.deleteLastPathComponent()
        }
        return true
    }
}
