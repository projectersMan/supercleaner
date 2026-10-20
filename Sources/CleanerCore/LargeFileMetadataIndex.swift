import CoreServices
import Foundation

public protocol LargeFileMetadataIndexing: Sendable {
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL]
}

public enum LargeFileMetadataIndexError: Error, Sendable {
    case queryUnavailable
    case executionFailed
}

public struct SpotlightLargeFileMetadataIndex: LargeFileMetadataIndexing {
    public init() {}

    public func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] {
        try Task.checkCancellation()
        let queryString = "kMDItemFSSize >= \(minimumBytes)" as CFString
        let attributes = [kMDItemPath] as CFArray
        guard let query = MDQueryCreate(nil, queryString, attributes, nil) else {
            throw LargeFileMetadataIndexError.queryUnavailable
        }
        MDQuerySetSearchScope(query, [scope.standardizedFileURL.path] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw LargeFileMetadataIndexError.executionFailed
        }

        var urls: [URL] = []
        urls.reserveCapacity(MDQueryGetResultCount(query))
        for index in 0..<MDQueryGetResultCount(query) {
            try Task.checkCancellation()
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(pointer, to: MDItem.self)
            guard let value = MDItemCopyAttribute(item, kMDItemPath),
                  let path = value as? String else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }
}

public struct IndexedLargeFileScanner: Sendable {
    public let minimumBytes: UInt64
    private let index: any LargeFileMetadataIndexing

    public init(
        minimumBytes: UInt64 = 100_000_000,
        index: any LargeFileMetadataIndexing = SpotlightLargeFileMetadataIndex()
    ) {
        self.minimumBytes = minimumBytes
        self.index = index
    }

    public func scan(context: ScanContext) async throws -> DiskUsageTree {
        let scope = context.homeDirectory.standardizedFileURL
        let scopePrefix = scope.path + "/"
        let indexedURLs = try await index.matchingFileURLs(minimumBytes: minimumBytes, scope: scope)
        var seenPaths = Set<String>()
        var files: [DiskUsageNode] = []

        for indexedURL in indexedURLs {
            try Task.checkCancellation()
            let url = indexedURL.standardizedFileURL
            guard url.path.hasPrefix(scopePrefix),
                  seenPaths.insert(url.path).inserted,
                  await context.fileSystem.fileExists(url),
                  let identity = try? await context.fileSystem.identity(at: url),
                  identity.kind == .file,
                  identity.size >= minimumBytes else { continue }

            let readable = await context.fileSystem.isReadable(url)
            files.append(DiskUsageNode(
                url: url,
                kind: .file,
                ownBytes: identity.size,
                recursiveBytes: identity.size,
                childCount: 0,
                modifiedAt: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                isReadable: readable,
                children: readable ? .loaded([]) : .unavailable(L10n.text("无法读取文件")),
                identity: identity
            ))
        }

        files.sort {
            $0.ownBytes == $1.ownBytes
                ? $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                : $0.ownBytes > $1.ownBytes
        }
        return DiskUsageTree(
            roots: files,
            largeFiles: files,
            minimumFileBytes: minimumBytes,
            coverage: CoverageSummary(),
            scannedAt: context.now,
            analysisState: .indexedResults
        )
    }
}
