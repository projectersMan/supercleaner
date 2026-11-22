import Foundation

/// Reuses only parsed BOM contents, never an ownership or deletion decision.
actor ApplicationReceiptDirectoryCache {
    static let shared = ApplicationReceiptDirectoryCache(read: readDirectories)
    private let read: @Sendable (URL, TimeInterval) async throws -> String
    private var entries: [URL: (generation: String, paths: String)] = [:]
    private var order: [URL] = []

    init(read: @escaping @Sendable (URL, TimeInterval) async throws -> String) { self.read = read }

    func directories(in url: URL, context: ScanContext, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        let generation = try await context.fileSystem.itemGeneration(at: url)
        if let generation, let cached = entries[url], cached.generation == generation {
            return cached.paths
        }
        let paths = try await read(url, timeout)
        try Task.checkCancellation()
        guard let generation else { return paths }
        guard try await context.fileSystem.itemGeneration(at: url) == generation else {
            throw FileSystemError.invalidAttributes(url)
        }
        if entries[url] == nil {
            if order.count == 256 { entries.removeValue(forKey: order.removeFirst()) }
            order.append(url)
        }
        entries[url] = (generation, paths)
        return paths
    }

    private static func readDirectories(_ url: URL, timeout: TimeInterval) async throws -> String {
        let output = try await BoundedProcess.run("/usr/bin/lsbom", arguments: ["-s", "-d", url.path],
            timeout: timeout, maximumOutputBytes: 2_097_152)
        guard output.status == 0, let paths = String(data: output.stdout, encoding: .utf8) else {
            throw FileSystemError.unreadableContent(url)
        }
        return paths
    }
}
