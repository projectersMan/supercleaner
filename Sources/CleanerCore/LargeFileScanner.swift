import Foundation

public struct LargeFileScanner: Scanner {
    public let id = "general.large-files"
    public let category = CleanupCategory.largeFile
    public let minimumBytes: UInt64
    /// Legacy compatibility only; directory traversal has no depth cutoff.
    public let maximumDepth: Int?
    public let maximumEntries: Int?

    public init(
        minimumBytes: UInt64 = 100_000_000,
        maximumDepth: Int? = nil,
        maximumEntries: Int? = nil
    ) {
        self.minimumBytes = minimumBytes
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let tree = try await DiskUsageScanner(
            minimumFileBytes: minimumBytes,
            maximumDepth: maximumDepth,
            maximumEntries: maximumEntries
        ).scan(context: context)
        return try await candidates(from: tree, context: context)
    }

    public func candidates(from tree: DiskUsageTree, context: ScanContext) async throws -> [CleanupCandidate] {
        var output: [CleanupCandidate] = []
        let deletedContent = DeletedContentScanExclusion(homeDirectory: context.homeDirectory)
        for node in tree.largeFiles where node.ownBytes >= minimumBytes {
            try Task.checkCancellation()
            guard !deletedContent.contains(node.url) else { continue }
            let identity: FileIdentity
            if let capturedIdentity = node.identity {
                identity = capturedIdentity
            } else if let currentIdentity = try? await context.fileSystem.identity(at: node.url) {
                identity = currentIdentity
            } else {
                continue
            }
            guard identity.kind == .file else { continue }
            let active = context.isActive(node.url)
            var risk: RiskLevel = active || !node.isReadable ? .blocked : .review
            var evidence = [Evidence(
                code: "large-file",
                summary: L10n.text("大文件仅因体积被发现，不会自动清理")
            )]
            let scope = LargeFileCleanupScope(homeDirectory: context.homeDirectory)
            if !scope.allows(node.url, forManualSelection: true) {
                risk = .blocked
                evidence.append(Evidence(code: "large-file-protected-scope", summary: L10n.text("仅允许选择当前用户目录中的文件")))
            }
            if active { evidence.append(Evidence(code: "active", summary: L10n.text("文件正在使用，暂不可选择"))) }
            if !node.isReadable { evidence.append(Evidence(code: "unreadable", summary: L10n.text("不可读取"))) }
            do { _ = try context.pathPolicy.validateCandidate(node.url) }
            catch { risk = .blocked; evidence.append(Evidence(code: "protected-path", summary: L10n.text("路径受到安全策略保护"))) }
            output.append(context.protectionPolicy.applying(to: CleanupCandidate(
                url: node.url, displayName: node.url.lastPathComponent, category: category, bytes: node.ownBytes,
                risk: risk, evidence: evidence, identity: identity, source: .diskAnalysis,
                lastAccessDate: node.modifiedAt, isActive: active,
                requiresExplicitSelection: !scope.allows(node.url) && !scope.allowsInstaller(node.url)
            )))
        }
        return output.sorted { $0.bytes > $1.bytes }
    }
}
