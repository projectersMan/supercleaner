import Foundation

extension SystemScanReport {
    static func preservingProjectInstallerProofs(_ projects: [CleanupCandidate], largeFiles: [CleanupCandidate]) -> [CleanupCandidate] {
        let proofs = (largeFiles + projects).compactMap(\.largeFileProof)
        let byPath = Dictionary(proofs.map { ($0.target.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        let retained = proofs.flatMap(\.retained)
        return projects.map { candidate in
            let path = candidate.url.standardizedFileURL.path
            let protected = retained.contains { $0.url.path == path || $0.url.path.hasPrefix(path + "/") }
            let result = byPath[path].map { candidate.withLargeFileProof($0) } ?? candidate
            guard protected || result.largeFileProof.map({ !$0.isCurrent(for: result) }) == true else { return result }
            return result.replacing(risk: .blocked, evidence: result.evidence + [Evidence(code: "large-file-retained-copy",
                summary: L10n.text("清理计划包含必须保留的文件或目录"))])
        }
    }

    public var projectInstallerPaths: Set<String> {
        Set((projectScanReport?.artifacts ?? []).filter {
            $0.candidate.identity.kind == .file && $0.candidate.url.pathExtension.lowercased() == "dmg"
        }.map { $0.candidate.url.standardizedFileURL.path })
    }

    public var largeFileReviewCandidates: [CleanupCandidate] {
        let projectPaths = projectInstallerPaths
        return largeFileCandidates.filter { !projectPaths.contains($0.url.standardizedFileURL.path) }
    }

    public var largeFileReviewTree: DiskUsageTree {
        diskUsageTree.excludingFiles(at: projectInstallerPaths)
    }
}

extension DiskUsageTree {
    func excludingFiles(at paths: Set<String>) -> DiskUsageTree {
        guard !paths.isEmpty else { return self }
        var ancestors = Set<String>()
        for path in paths {
            var parent = path
            while let slash = parent.lastIndex(of: "/") {
                parent = slash == parent.startIndex ? "/" : String(parent[..<slash])
                ancestors.insert(parent)
                if parent == "/" { break }
            }
        }
        return DiskUsageTree(roots: roots.compactMap { excludingProjectInstallers($0, paths: paths, ancestors: ancestors) },
            largeFiles: largeFiles.filter { !paths.contains($0.url.standardizedFileURL.path) },
            minimumFileBytes: minimumFileBytes, coverage: coverage, scannedAt: scannedAt, analysisState: analysisState)
    }

    private func excludingProjectInstallers(_ node: DiskUsageNode, paths: Set<String>, ancestors: Set<String>) -> DiskUsageNode? {
        let path = node.url.standardizedFileURL.path
        guard !paths.contains(path) else { return nil }
        // Reuse entire unaffected subtrees; no descendant inspection is needed.
        guard ancestors.contains(path) else { return node }
        guard case let .loaded(children) = node.children else { return node }
        let remaining = children.compactMap { excludingProjectInstallers($0, paths: paths, ancestors: ancestors) }
        let previousBytes = children.reduce(UInt64(0)) { $0 + $1.recursiveBytes }
        let remainingBytes = remaining.reduce(UInt64(0)) { $0 + $1.recursiveBytes }
        return DiskUsageNode(url: node.url, kind: node.kind, ownBytes: node.ownBytes,
            recursiveBytes: node.recursiveBytes - min(node.recursiveBytes, previousBytes - min(previousBytes, remainingBytes)),
            childCount: max(0, node.childCount - (children.count - remaining.count)), modifiedAt: node.modifiedAt,
            isReadable: node.isReadable, children: .loaded(remaining), identity: node.identity)
    }
}
