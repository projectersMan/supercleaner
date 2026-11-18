import CleanerCore
import Foundation

func runCoreReadOnlyContracts() async throws {
    let manager = FileManager.default
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tests/local-ai-projects-disk/cli", isDirectory: true)
    let home = fixtures.appendingPathComponent("core-readonly-" + UUID().uuidString, isDirectory: true)
    let cache = home.appendingPathComponent("Library/Caches/unknown")
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    let file = cache.appendingPathComponent("user-payload")
    let original = Data("fixture must survive preview".utf8)
    try original.write(to: file)
    let before = try manager.attributesOfItem(atPath: file.path)
    let runtime = CleanupRuntime(home: home, fileSystem: ReviewScanFileSystem(home: home))
    let configuration = try await runtime.configuration()
    let scan = await SystemCleanupScanner().scan(context: configuration.context, pack: configuration.pack)
    require(scan.failures.isEmpty && configuration.context.protectionPolicy.isAvailable,
            "Core scan must retain complete coverage and available protection")
    let selected = scan.candidates.filter { $0.url.resolvingSymlinksInPath().path == cache.resolvingSymlinksInPath().path }
    require(selected.count == 1 && selected.first?.defaultSelection == false,
            "Core scan must use production classification")
    let candidate = selected[0]
    let builder = PlanBuilder(ruleVersion: configuration.pack.executionVersion, protectionPolicy: configuration.context.protectionPolicy)
    let preview = try builder.build(candidates: selected, selectedIDs: [candidate.id])
    require(preview.selectedItems.map(\.candidate.id) == [candidate.id], "preview must bind the selected scanned candidate")
    let eligible = CleanupScopePolicy().cleanupCenterCandidates(from: scan.candidates)
    let defaults = try builder.build(candidates: eligible, selectedIDs: CleanupRecommendationPolicy().defaultSelectedIDs(for: eligible))
    require(defaults.selectedItems.map { $0.candidate.url.resolvingSymlinksInPath().path } == [cache.resolvingSymlinksInPath().path],
            "default preview must reflect selectable System and other applications items")
    let support = home.appendingPathComponent("Library/Application Support/SuperCleaner")
    let receipts = try await HistoryStore(url: support.appendingPathComponent("history.json")).receipts()
    require(receipts.isEmpty, "missing history must produce an empty read-only result")
    require(!manager.fileExists(atPath: support.path), "Core scan/preview/history must not create application state")
    let remainingPayload = try Data(contentsOf: file)
    require(remainingPayload == original, "Core observation and preview must leave payload unchanged")
    let after = try manager.attributesOfItem(atPath: file.path)
    require(before[.modificationDate] as? Date == after[.modificationDate] as? Date, "preview must not modify file metadata")

    _ = try await runtime.protections.protect(file)
    let protected = try await runtime.configuration()
    let protectedPreview = Result {
        try PlanBuilder(ruleVersion: protected.pack.executionVersion, protectionPolicy: protected.context.protectionPolicy)
            .build(candidates: selected, selectedIDs: [candidate.id])
    }
    switch protectedPreview {
    case .success: require(false, "preview must not bypass persistent protection")
    case let .failure(error):
        require(error as? PlanBuilderError == .protectedSelection(candidate.id), "protected preview must fail with the exact protection rejection")
    }
    try Data("invalid protection fixture".utf8).write(to: support.appendingPathComponent("protected-paths.json"))
    let unavailable = try await runtime.configuration()
    require(!unavailable.context.protectionPolicy.isAvailable, "unreadable protection must remain unavailable rather than becoming an empty policy")
    let unavailablePreview = Result {
        try PlanBuilder(ruleVersion: unavailable.pack.executionVersion, protectionPolicy: unavailable.context.protectionPolicy)
            .build(candidates: selected, selectedIDs: [candidate.id])
    }
    switch unavailablePreview {
    case .success: require(false, "preview must refuse unavailable protection")
    case let .failure(error):
        require(error as? PlanBuilderError == .protectedSelection(candidate.id), "unavailable protection must fail closed")
    }
    try manager.removeItem(at: home)
    print("PASS: Core production classification, explicit/default previews, history, read-only effects and protection gates")
}
