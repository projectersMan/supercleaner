import CryptoKit
import Foundation

/// Only parsed literal names are reused. Every lookup hashes the current source
/// bytes; filesystem, running-state and ownership checks stay live at execution.
actor ApplicationDataDeclarationCache {
    static let shared = ApplicationDataDeclarationCache()
    private var namesByDigest: [Data: Set<String>] = [:]
    private var order: [Data] = []
    private(set) var parseCount = 0

    func names(in source: Data) -> Set<String> {
        guard !Task.isCancelled else { return [] }
        let digest = Data(SHA256.hash(data: source))
        if let names = namesByDigest[digest] { return names }
        guard let text = String(data: source, encoding: .utf8) else { return [] }
        parseCount += 1
        let names = ApplicationDataDiscovery.declaredDirectoryNames(in: text)
        // Empty results can also mean a cancelled/timed-out parse. Never cache
        // those as evidence that an application declares no data directory.
        if !names.isEmpty, !Task.isCancelled {
            if order.count == 64 { namesByDigest.removeValue(forKey: order.removeFirst()) }
            namesByDigest[digest] = names
            order.append(digest)
        }
        return names
    }
}
