import Foundation

public enum DiskUsageAnalysisState: String, Codable, Hashable, Sendable {
    case indexedResults
    case complete
}

public indirect enum DiskUsageChildren: Codable, Hashable, Sendable {
    case unloaded
    case loaded([DiskUsageNode])
    case unavailable(String)
}

public struct DiskUsageNode: Identifiable, Codable, Hashable, Sendable {
    public var id: URL { url.standardizedFileURL }
    public let url: URL
    public let kind: FileIdentity.Kind
    public let ownBytes: UInt64
    public let recursiveBytes: UInt64
    public let childCount: Int
    public let modifiedAt: Date
    public let isReadable: Bool
    public let children: DiskUsageChildren
    public let identity: FileIdentity?

    public init(
        url: URL,
        kind: FileIdentity.Kind,
        ownBytes: UInt64,
        recursiveBytes: UInt64,
        childCount: Int,
        modifiedAt: Date,
        isReadable: Bool,
        children: DiskUsageChildren,
        identity: FileIdentity? = nil
    ) {
        self.url = url.standardizedFileURL
        self.kind = kind
        self.ownBytes = ownBytes
        self.recursiveBytes = recursiveBytes
        self.childCount = childCount
        self.modifiedAt = modifiedAt
        self.isReadable = isReadable
        self.children = children
        self.identity = identity
    }
}

public struct DiskUsageTree: Codable, Hashable, Sendable {
    public let roots: [DiskUsageNode]
    public let largeFiles: [DiskUsageNode]
    public let minimumFileBytes: UInt64
    public let coverage: CoverageSummary
    public let scannedAt: Date
    public let analysisState: DiskUsageAnalysisState

    public init(
        roots: [DiskUsageNode],
        largeFiles: [DiskUsageNode],
        minimumFileBytes: UInt64 = 100_000_000,
        coverage: CoverageSummary,
        scannedAt: Date,
        analysisState: DiskUsageAnalysisState = .complete
    ) {
        self.roots = roots
        self.largeFiles = largeFiles
        self.minimumFileBytes = minimumFileBytes
        self.coverage = coverage
        self.scannedAt = scannedAt
        self.analysisState = analysisState
    }

    public func node(at url: URL) -> DiskUsageNode? {
        let path = url.standardizedFileURL.path
        func find(_ nodes: [DiskUsageNode]) -> DiskUsageNode? {
            for node in nodes {
                if node.url.path == path { return node }
                if case let .loaded(children) = node.children, let match = find(children) { return match }
            }
            return nil
        }
        return find(roots)
    }

    public var concreteFiles: [DiskUsageNode] {
        func collect(_ nodes: [DiskUsageNode]) -> [DiskUsageNode] {
            nodes.flatMap { node -> [DiskUsageNode] in
                var files = node.kind == .file ? [node] : []
                if case let .loaded(children) = node.children { files.append(contentsOf: collect(children)) }
                return files
            }
        }
        return collect(roots).sorted {
            $0.recursiveBytes == $1.recursiveBytes
                ? $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                : $0.recursiveBytes > $1.recursiveBytes
        }
    }
}

public struct DiskUsageScanner: Sendable {
    public let minimumFileBytes: UInt64
    public let maximumDepth: Int?
    public let maximumEntries: Int?

    public init(
        minimumFileBytes: UInt64 = 100_000_000,
        maximumDepth: Int? = nil,
        maximumEntries: Int? = nil
    ) {
        self.minimumFileBytes = minimumFileBytes
        self.maximumDepth = maximumDepth.map { max(1, $0) }
        self.maximumEntries = maximumEntries.map { max(1, $0) }
    }

    public func scan(context: ScanContext) async throws -> DiskUsageTree {
        let configuredRoots = [context.homeDirectory.standardizedFileURL]
        var roots: [DiskUsageNode] = []
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        var remainingEntries = maximumEntries
        var reachedBudget = false

        for root in configuredRoots where await context.fileSystem.fileExists(root) {
            try Task.checkCancellation()
            guard await context.fileSystem.isReadable(root) else {
                unavailableRoots.append(root)
                continue
            }
            scannedRoots.append(root)
            do {
                roots.append(try await directoryNode(
                    at: root,
                    identity: try? await context.fileSystem.identity(at: root),
                    depth: 0,
                    remainingEntries: &remainingEntries,
                    reachedBudget: &reachedBudget,
                    unavailableRoots: &unavailableRoots,
                    context: context
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unavailableRoots.append(root)
            }
            if reachedBudget { break }
        }

        roots.sort { $0.recursiveBytes == $1.recursiveBytes ? $0.url.path < $1.url.path : $0.recursiveBytes > $1.recursiveBytes }
        let largeFiles = collectLargeFiles(from: roots).sorted {
            $0.recursiveBytes == $1.recursiveBytes ? $0.url.path < $1.url.path : $0.recursiveBytes > $1.recursiveBytes
        }
        return DiskUsageTree(
            roots: roots,
            largeFiles: largeFiles,
            minimumFileBytes: minimumFileBytes,
            coverage: CoverageSummary(
                scannedRoots: scannedRoots,
                unavailableRoots: unavailableRoots,
                budgetLimitedModules: reachedBudget ? [.largeFiles] : []
            ),
            scannedAt: context.now
        )
    }

    private func directoryNode(
        at url: URL,
        identity: FileIdentity?,
        depth: Int,
        remainingEntries: inout Int?,
        reachedBudget: inout Bool,
        unavailableRoots: inout [URL],
        context: ScanContext
    ) async throws -> DiskUsageNode {
        try Task.checkCancellation()
        let readable = await context.fileSystem.isReadable(url)
        let modifiedAt = Date(timeIntervalSince1970: Double(identity?.modificationTime ?? Int64(context.now.timeIntervalSince1970)))
        guard readable else {
            unavailableRoots.append(url)
            return DiskUsageNode(
                url: url, kind: .directory, ownBytes: identity?.size ?? 0,
                recursiveBytes: identity?.size ?? 0, childCount: 0, modifiedAt: modifiedAt,
                isReadable: false, children: .unavailable("无法读取目录"), identity: identity
            )
        }
        if let maximumDepth, depth >= maximumDepth {
            reachedBudget = true
            return DiskUsageNode(
                url: url, kind: .directory, ownBytes: identity?.size ?? 0,
                recursiveBytes: identity?.size ?? 0, childCount: 0, modifiedAt: modifiedAt,
                isReadable: true, children: .unloaded, identity: identity
            )
        }

        let childURLs: [URL]
        do {
            childURLs = try await context.fileSystem.children(of: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            unavailableRoots.append(url)
            return DiskUsageNode(
                url: url, kind: .directory, ownBytes: identity?.size ?? 0,
                recursiveBytes: identity?.size ?? 0, childCount: 0, modifiedAt: modifiedAt,
                isReadable: false, children: .unavailable("无法读取目录"), identity: identity
            )
        }
        var children: [DiskUsageNode] = []
        var omittedFileBytes: UInt64 = 0
        for childURL in childURLs {
            try Task.checkCancellation()
            if let remaining = remainingEntries {
                guard remaining > 0 else { reachedBudget = true; break }
                remainingEntries = remaining - 1
            }
            guard let childIdentity = try? await context.fileSystem.identity(at: childURL),
                  childIdentity.kind != .symbolicLink
            else { continue }
            let childReadable = await context.fileSystem.isReadable(childURL)
            if childIdentity.kind == .directory {
                children.append(try await directoryNode(
                    at: childURL,
                    identity: childIdentity,
                    depth: depth + 1,
                    remainingEntries: &remainingEntries,
                    reachedBudget: &reachedBudget,
                    unavailableRoots: &unavailableRoots,
                    context: context
                ))
            } else {
                if childIdentity.kind == .file, childIdentity.size >= minimumFileBytes {
                    children.append(DiskUsageNode(
                        url: childURL,
                        kind: childIdentity.kind,
                        ownBytes: childIdentity.size,
                        recursiveBytes: childIdentity.size,
                        childCount: 0,
                        modifiedAt: Date(timeIntervalSince1970: Double(childIdentity.modificationTime)),
                        isReadable: childReadable,
                        children: childReadable ? .loaded([]) : .unavailable("无法读取文件"),
                        identity: childIdentity
                    ))
                } else {
                    let (sum, overflowed) = omittedFileBytes.addingReportingOverflow(childIdentity.size)
                    omittedFileBytes = overflowed ? .max : sum
                }
            }
            if reachedBudget { break }
        }
        children.sort { $0.recursiveBytes == $1.recursiveBytes ? $0.url.path < $1.url.path : $0.recursiveBytes > $1.recursiveBytes }
        let recursiveBytes = children.reduce(omittedFileBytes) { total, child in
            let (sum, overflowed) = total.addingReportingOverflow(child.recursiveBytes)
            return overflowed ? .max : sum
        }
        return DiskUsageNode(
            url: url,
            kind: .directory,
            ownBytes: identity?.size ?? 0,
            recursiveBytes: recursiveBytes,
            childCount: childURLs.count,
            modifiedAt: modifiedAt,
            isReadable: true,
            children: .loaded(children),
            identity: identity
        )
    }

    private func collectLargeFiles(from nodes: [DiskUsageNode]) -> [DiskUsageNode] {
        nodes.flatMap { node -> [DiskUsageNode] in
            var matches = node.kind == .file && node.ownBytes >= minimumFileBytes ? [node] : []
            if case let .loaded(children) = node.children {
                matches.append(contentsOf: collectLargeFiles(from: children))
            }
            return matches
        }
    }
}
