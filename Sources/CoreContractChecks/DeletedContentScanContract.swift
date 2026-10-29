import CleanerCore
import Foundation

func runDeletedContentScanContracts() async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("deleted-content-scan-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    defer { try? manager.removeItem(at: home) }
    let quarantine = home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine")
    let deleted = quarantine.appendingPathComponent("batch/installer.dmg")
    let appPayload = quarantine.appendingPathComponent("batch/Deleted.app/Contents/payload.bin")
    let trashed = home.appendingPathComponent(".Trash/installer.dmg")
    let neighboring = home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine-backup/keep.dmg")
    let ordinary = home.appendingPathComponent("Downloads/keep.dmg")
    let restored = home.appendingPathComponent("Downloads/restored.dmg")
    let payload = Data(repeating: 42, count: 256)
    for url in [deleted, appPayload, trashed, neighboring, ordinary] {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: url)
    }
    let alias = home.appendingPathComponent("RecoveryAlias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: quarantine)
    let aliasedFile = alias.appendingPathComponent("batch/installer.dmg")
    let context = ScanContext(homeDirectory: home)
    let urls = [deleted, appPayload, trashed, neighboring, ordinary, aliasedFile, restored]
    let index = DeletedContentFixtureIndex(urls: urls)
    let indexed = try await IndexedLargeFileScanner(minimumBytes: 100, index: index).scan(context: context)
    let walked = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: context)
    let expected = Set([ordinary, neighboring])
    for tree in [indexed, walked] {
        require(Set(tree.largeFiles.map(\.url)) == expected, "rescans must omit recovery, removed apps, Trash, aliases, and stale missing paths while retaining neighboring names")
        require(Set(tree.concreteFiles.map(\.url)) == expected, "deleted files must not remain in displayed tree rows")
        require(tree.roots.reduce(0) { $0 + $1.recursiveBytes } == 512, "deleted content must not inflate visible file totals")
        let candidates = try await LargeFileScanner(minimumBytes: 100).candidates(from: tree, context: context)
        require(Set(candidates.map(\.url)) == expected, "deleted content must not re-enter cleanup candidates")
    }
    require(walked.node(at: quarantine) == nil, "directory fallback must prune the recovery subtree")
    require(walked.node(at: home.appendingPathComponent(".Trash")) == nil, "directory fallback must prune Trash")

    // Even a previously collected tree cannot materialize deleted storage as candidates.
    let capturedIdentity = try await context.fileSystem.identity(at: deleted)
    let staleNode = DiskUsageNode(url: deleted, kind: .file, ownBytes: 256, recursiveBytes: 256,
        childCount: 0, modifiedAt: Date(), isReadable: true, children: .loaded([]), identity: capturedIdentity)
    let staleTree = DiskUsageTree(roots: [staleNode], largeFiles: [staleNode], coverage: .init(), scannedAt: Date())
    let staleCandidates = try await LargeFileScanner(minimumBytes: 100).candidates(from: staleTree, context: context)
    require(staleCandidates.isEmpty, "candidate materialization must reject recovery paths in older snapshots")
    let retainedData = try Data(contentsOf: deleted)
    require(retainedData == payload && manager.fileExists(atPath: appPayload.path), "scan filtering must preserve recoverable content")

    // A restored item is a normal file again; do not hide by basename or past history.
    try manager.moveItem(at: deleted, to: restored)
    let afterRestore = try await IndexedLargeFileScanner(minimumBytes: 100, index: index).scan(context: context)
    require(Set(afterRestore.largeFiles.map(\.url)) == expected.union([restored]), "restored files must reappear at their live location")
}

private struct DeletedContentFixtureIndex: LargeFileMetadataIndexing {
    let urls: [URL]
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] { urls }
}
