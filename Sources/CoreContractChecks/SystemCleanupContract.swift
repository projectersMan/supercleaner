import CleanerCore
import Foundation

private struct CleanupFixtureMetadata: ApplicationMetadataProviding {
    let applications: [InstalledApplication]
    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        guard let app = applications.first(where: { $0.bundleURL.path == bundleURL.path }) else { return nil }
        return .init(bundleIdentifier: app.bundleIdentifier, name: app.name, version: app.version)
    }
}

private struct DeniedCleanupFS: FileSystemAccess {
    let base = LocalFileSystem()
    let denied: URL
    func identity(at url: URL) async throws -> FileIdentity { try await base.identity(at: url) }
    func children(of url: URL) async throws -> [URL] {
        if url == denied { throw FileSystemError.unreadableContent(url) }
        return try await base.children(of: url)
    }
    func isReadable(_ url: URL) async -> Bool { url != denied }
    func isWritable(_ url: URL) async -> Bool { true }
    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }
}

func runSystemCleanupContracts() async throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true).appendingPathComponent("system-cleanup-\(UUID())")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let home = root.standardizedFileURL
    defer { try? fm.removeItem(at: home) }
    func file(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture payload".utf8).write(to: url)
        return url
    }
    func candidate(_ path: String, in values: [CleanupCandidate]) -> CleanupCandidate? {
        values.first { $0.url.path == home.appendingPathComponent(path).path }
    }
    let context = ScanContext(homeDirectory: home)
    let unreadablePath = home.appendingPathComponent("private-fixture-\(UUID().uuidString)")
    let safeFailure = ScanFailure.from(error: FileSystemError.unreadableContent(unreadablePath),
        scannerID: "fixture", path: unreadablePath)
    require(safeFailure.reason == .access && safeFailure.message == L10n.text("目录无法完整检查"),
            "scan failures use a user-safe localized summary")
    require(!safeFailure.message.contains(unreadablePath.path) && !safeFailure.message.contains("NSError"),
            "scan failures never expose raw OS error details")
    let smallA = try file("budget/A/payload")
    for i in 0..<8 { _ = try file("budget/B/\(i)") }
    _ = try file("budget/C/payload")
    let budgetRule = CleanupRule(ruleID: "fixture.budget", category: .cache, relativePaths: ["budget"],
        minimumAgeDays: 0, defaultRisk: .review, granularity: .children, maximumDepth: 8, maximumEntries: 3)
    let budgetPack = RulePack(version: "fixture", issuedAt: .distantPast, rules: [budgetRule], revokedRuleIDs: [])
    let limited = await ScanCoordinator().scan(using: [CleanupRuleEngine(pack: budgetPack)], context: context)
    require(limited.candidates.count == 3, "large sibling must not erase successful candidates before or after it")
    require(candidate("budget/A", in: limited.candidates)?.risk == .review && candidate("budget/C", in: limited.candidates)?.risk == .review,
            "both complete siblings must stay selectable")
    require(candidate("budget/B", in: limited.candidates)?.risk == .review && limited.failures.isEmpty,
            "large siblings must be inspected completely regardless of legacy rule limits")
    require(limited.coverage.budgetLimitedModules.isEmpty, "complete general coverage is not budget limited")
    let deniedContext = ScanContext(homeDirectory: home, fileSystem: DeniedCleanupFS(denied: home.appendingPathComponent("budget/B")))
    let denied = await ScanCoordinator().scan(using: [CleanupRuleEngine(pack: budgetPack)], context: deniedContext)
    require(denied.candidates.contains { $0.url == smallA.deletingLastPathComponent() } && denied.failures.contains { $0.reason == .access },
            "unreadable sibling preserves results and access reason")
    let discoveryRule = CleanupRule(ruleID: "fixture.discovery", category: .cache, relativePaths: ["budget"], minimumAgeDays: 0,
        defaultRisk: .review, granularity: .children, maximumEntries: 1)
    let discoveryLimited = try await CleanupRuleEngine(pack: RulePack(version: "fixture", issuedAt: .distantPast,
        rules: [discoveryRule], revokedRuleIDs: [])).scanResult(context: context)
    require(discoveryLimited.candidates.count == 3 && discoveryLimited.failures.isEmpty, "legacy rule entry limits cannot truncate discovery")

    let appRoot = home.appendingPathComponent("Applications")
    func app(_ name: String, _ id: String, _ version: String = "1.0") throws -> InstalledApplication {
        let url = appRoot.appendingPathComponent(name + ".app")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return InstalledApplication(bundleURL: url, bundleIdentifier: id, name: name, version: version, isRunning: false, isSystem: false)
    }
    let chrome = try app("Google Chrome", "com.google.Chrome")
    let chat = try app("ChatGPT", "com.openai.codex")
    let wechat = try app("WeChat", "com.tencent.xinWeChat", "4.1.15")
    let lark = try app("Lark", "com.bytedance.Lark")
    let trae = try app("Trae CN", "com.trae.cn")
    let apps = [chrome, chat, wechat, lark, trae]
    _ = try file("Library/Caches/Google/Chrome/Default/Cache/Cache_Data/a")
    _ = try file("Library/Caches/Google/Chrome/Profile 1/Cache/a")
    _ = try file("Library/Caches/Google/OtherProduct/a")
    _ = try file("Library/Application Support/Google/Chrome/Default/GPUCache/a")
    _ = try file("Library/Application Support/Google/Chrome/Profile 1/Code Cache/js/a")
    let offlinePayload = try file("Library/Application Support/Google/Chrome/Profile 1/Service Worker/CacheStorage/offline")
    let scriptCachePayload = try file("Library/Application Support/Google/Chrome/Profile 1/Service Worker/ScriptCache/a")
    let otherOfflinePayload = try file("Library/Application Support/Trae CN/Service Worker/CacheStorage/offline")
    _ = try file("Library/Caches/com.openai.codex/Cache.db")
    _ = try file("Library/Logs/com.openai.codex/2026/app.log")
    _ = try file("Library/Application Support/Trae CN/Code Cache/js/a")
    _ = try file("Library/Containers/com.bytedance.Lark/Data/Library/Caches/a")
    _ = try file("Library/Containers/com.bytedance.Lark/Data/Library/Logs/app.log")
    let wx = "Library/Containers/com.tencent.xinWeChat/Data/"
    _ = try file(wx + "Library/Caches/com.tencent.xinWeChat/old-account/log/old.xlog")
    _ = try file(wx + "Documents/xwechat_files/accountA/cache/a")
    _ = try file(wx + "Documents/xwechat_files/accountB/cache/b")
    _ = try file(wx + "Documents/xwechat_files/accountB/cache/2026-11/Message/thread/Thumb/preview.jpg")
    let wxLog = try file(wx + "Documents/app_data/log/app.xlog")
    try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 86_400)], ofItemAtPath: wxLog.path)
    let currentWxLog = try file(wx + "Documents/app_data/log/current.xlog")
    let manualChatFiles = try [
        wx + "Documents/xwechat_files/accountA/msg/attach/photo",
        wx + "Documents/xwechat_files/accountA/msg/file/file.pdf"
    ].map(file)
    let canaries = try [
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/Google/Chrome/Default/History",
        "Library/Application Support/Google/Chrome/Default/IndexedDB/data",
        "Library/Application Support/Google/Chrome/Default/Local Storage/data",
        "Library/Application Support/Trae CN/User/settings.json",
        wx + "Documents/app_data/log/user.txt",
        wx + "Documents/xwechat_files/accountA/db_storage/message.db",
        wx + "Library/Application Support/com.tencent.xinWeChat/account/Message/image.jpg",
        "Downloads/user.pdf"
    ].map(file)
    let scanner = ApplicationCleanupScanner(maximumEntries: 200)
    let discovery = await scanner.discover(applications: apps, context: context)
    let result = try await scanner.scan(discovery: discovery, context: context)
    require(result.failures.isEmpty, "complete fixture discovery must have no silent coverage gaps")
    require(candidate("Library/Caches/com.openai.codex", in: result.candidates)?.cleanupApplication?.name == "ChatGPT", "real bundle ID owns ChatGPT cache")
    require(candidate("Library/Caches/com.openai.codex", in: result.candidates)?.risk == .safe
        && candidate("Library/Caches/com.openai.codex", in: result.candidates)?.defaultSelection == false
        && candidate("Library/Caches/com.openai.codex", in: result.candidates)?.requiresExplicitSelection == true,
        "verified application cache remains manually selectable in the keep group")
    require(candidate("Library/Caches/Google/Chrome/Profile 1/Cache", in: result.candidates) != nil, "Chrome nondefault profiles supported")
    require(candidate("Library/Application Support/Trae CN/Code Cache", in: result.candidates) != nil, "Electron cache leaves supported without deleting user data")
    let weChatAccountCache = candidate(wx + "Documents/xwechat_files/accountB/cache", in: result.candidates)
    require(weChatAccountCache?.risk == .safe
        && CleanupRecommendationPolicy().disposition(for: weChatAccountCache!) == .retain,
        "typed WeChat Message/Thumb derivatives remain available for manual cleanup")
    require(result.candidates.contains { $0.url == wxLog && $0.category == .log }, "WeChat 4 xlog supported")
    let activeWeChatContext = ScanContext(homeDirectory: home, runningBundleIdentifiers: [wechat.bundleIdentifier])
    let activeWeChatDiscovery = await scanner.discover(applications: apps, context: activeWeChatContext)
    let activeWeChatScan = try await scanner.scan(discovery: activeWeChatDiscovery, context: activeWeChatContext)
    let activeWeChatLog = activeWeChatScan.candidates.first { $0.url == wxLog }!
    let activeCurrentWeChatLog = activeWeChatScan.candidates.first { $0.url == currentWxLog }!
    require(!activeWeChatLog.isActive
        && CleanupRecommendationPolicy().disposition(for: activeWeChatLog) == .retain,
        "historical typed WeChat logs remain cleanup candidates while WeChat is running")
    require(!activeCurrentWeChatLog.isActive
        && CleanupRecommendationPolicy().disposition(for: activeCurrentWeChatLog) == .retain,
        "recently modified typed WeChat logs remain cleanup candidates while WeChat is running")
    try await scanner.validateForExecution(activeWeChatLog, context: activeWeChatContext, applications: apps)
    try await scanner.validateForExecution(activeCurrentWeChatLog, context: activeWeChatContext, applications: apps)
    require(result.candidates.contains { $0.cleanupApplication?.bundleIdentifier == lark.bundleIdentifier }, "sandbox cache and log supported")
    require(canaries.allSatisfy { canary in !result.candidates.contains { canary.path == $0.url.path || canary.path.hasPrefix($0.url.path + "/") } }, "chat records, browser state and user files never covered by a removal root")
    require(manualChatFiles.allSatisfy { file in result.candidates.contains {
        file.path.hasPrefix($0.url.path + "/") && $0.category == .applicationSupport
            && $0.requiresExplicitSelection == true && $0.defaultSelection == false
    } }, "WeChat message files are visible as manual user-data leaves")
    let offline = result.candidates.first { offlinePayload.path.hasPrefix($0.url.path + "/") }!
    let scriptCache = result.candidates.first { scriptCachePayload.path.hasPrefix($0.url.path + "/") }!
    let otherOffline = result.candidates.first { otherOfflinePayload.path.hasPrefix($0.url.path + "/") }!
    require(offline.requiresExplicitSelection == true && scriptCache.requiresExplicitSelection == true,
            "Chrome offline storage remains manually selectable without default preselection")
    require(otherOffline.requiresExplicitSelection == true,
            "offline content from other applications remains individually confirmed")
    let policy = CleanupRecommendationPolicy()
    require(offline.risk == .safe && offline.defaultSelection == false && !PlanItem(candidate: offline).isSelected,
            "validated Chrome offline storage still requires an individual selection")
    require(policy.disposition(for: offline) == .retain,
            "application-generated offline storage is shown in the keep group")
    require(!policy.selectedIDs(for: result.candidates, mode: .smart, currentSelection: []).contains(offline.id)
        && !policy.selectedIDs(for: result.candidates, mode: .deep, currentSelection: []).contains(offline.id),
        "smart and deep cleanup do not silently select app offline storage")
    var selection = CleanupStrategySelectionState(strategy: .deep, generationID: UUID(), selectedIDs: [], excludedBaseIDs: [])
    selection.toggleCategory(candidates: result.candidates, baseEligibleIDs: [])
    require(!selection.selectedIDs.contains(offline.id), "group selection excludes individually confirmed app data")
    selection.toggle(offline, baseEligibleIDs: [])
    let custom = policy.selectedIDs(for: result.candidates, mode: .custom, currentSelection: selection.selectedIDs)
    require(custom.contains(offline.id), "custom mode preserves explicit Chrome offline selection")
    let decoded = try JSONDecoder().decode(CleanupCandidate.self, from: JSONEncoder().encode(offline))
    require(decoded.requiresExplicitSelection == true && decoded.cleanupApplication == offline.cleanupApplication,
            "Chrome offline cleanup eligibility persists across serialization")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(offline)) as! [String: Any]
    legacy.removeValue(forKey: "requiresExplicitSelection"); legacy.removeValue(forKey: "cleanupApplication")
    _ = try JSONDecoder().decode(CleanupCandidate.self, from: JSONSerialization.data(withJSONObject: legacy))
    require(SystemCleanupApplicationGroup.groups(result.candidates).contains { $0.title == "ChatGPT" && $0.kinds.count == 2 }, "application grouping contains cache/log subtypes")

    let appScanner = ApplicationScanner(metadataProvider: CleanupFixtureMetadata(applications: apps), applicationRoots: [appRoot])
    let broad = CleanupRule(ruleID: "discovery.user-caches", category: .cache, relativePaths: ["Library/Caches"], minimumAgeDays: 0,
        defaultRisk: .review, granularity: .children, maximumDepth: 16, maximumEntries: 200)
    let pack = RulePack(version: "fixture", issuedAt: .distantPast, rules: [broad], revokedRuleIDs: [])
    let full = await SystemCleanupScanner(applicationScanner: appScanner).scan(context: context, pack: pack)
    for item in full.candidates {
        require(!full.candidates.contains { $0.id != item.id && ($0.url == item.url || item.url.path.hasPrefix($0.url.path + "/")) }, "general and precise candidates cannot overlap")
    }
    require(full.candidates.contains { $0.url.path == home.appendingPathComponent("Library/Caches/Google/OtherProduct").path }, "splitting Google ancestor preserves unrelated sibling cache")
    require(full.candidates.contains { $0.cleanupApplication?.bundleIdentifier == chrome.bundleIdentifier }, "production general scan integrates app discovery")

    let systemReport = SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
        modules: [:], generalCandidates: result.candidates,
        applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
        diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
        largeFileCandidates: [], agentAssets: [])
    let defaultSelection = DefaultCleanupPolicy().selection(for: systemReport).candidates
    require(!defaultSelection.contains { $0.id == offline.id } && !defaultSelection.contains { $0.id == scriptCache.id },
            "dashboard one-click defaults leave app-generated offline roots for manual selection")
    require(Set(defaultSelection.map(\.id)) == policy.defaultSelectedIDs(for: CleanupScopePolicy().cleanupCenterCandidates(from: result.candidates)),
            "dashboard defaults share the explicit safe-default eligibility policy")
    require(!defaultSelection.contains { $0.id == otherOffline.id },
            "dashboard one-click defaults retain other apps' offline data for manual selection")

    let activeChat = InstalledApplication(bundleURL: chat.bundleURL, bundleIdentifier: chat.bundleIdentifier,
        name: chat.name, version: chat.version, isRunning: true, isSystem: false)
    var activeContext = context
    activeContext = ScanContext(homeDirectory: home, runningBundleIdentifiers: [activeChat.bundleIdentifier])
    let activeCacheScan = try await scanner.scan(
        discovery: await scanner.discover(applications: [activeChat], context: activeContext), context: activeContext)
    let activeCache = candidate("Library/Caches/com.openai.codex", in: activeCacheScan.candidates)!
    require(!activeCache.isActive && activeCache.evidence.contains { $0.code == "active-cleanup" },
            "exact app cache remains eligible while its app runs and carries a regeneration warning")
    try await scanner.validateForExecution(activeCache, context: activeContext, applications: [activeChat])
    let refreshed = systemReport.replacing(module: .general, payload: .general(denied), completedAt: Date())
    require(refreshed.modules[.general]?.state == .limited && !refreshed.coverage.unavailableRoots.isEmpty,
            "partial-refresh reports retain coverage limitations")

    let preciseRule = CleanupRule(ruleID: "fixture.precise", category: .cache,
        relativePaths: ["Library/Caches/com.openai.codex"], minimumAgeDays: 0, defaultRisk: .review,
        granularity: .root, maximumEntries: 200)
    let priorityScan = await SystemCleanupScanner(applicationScanner: appScanner).scan(context: context,
        pack: .init(version: "fixture", issuedAt: .distantPast, rules: [broad, preciseRule], revokedRuleIDs: []))
    require(candidate("Library/Caches/com.openai.codex", in: priorityScan.candidates)?.ruleID == preciseRule.ruleID,
            "packaged precise rules retain priority without duplicate automatic candidates")
    let revokedScan = await SystemCleanupScanner(applicationScanner: appScanner).scan(context: context,
        pack: .init(version: "fixture", issuedAt: .distantPast, rules: [broad, preciseRule], revokedRuleIDs: [preciseRule.ruleID]))
    require(candidate("Library/Caches/com.openai.codex", in: revokedScan.candidates)?.cleanupApplication?.name == chat.name,
            "inactive packaged rules must not suppress independent app discovery")
    let dynamicID = candidate("Library/Caches/com.openai.codex", in: result.candidates)!.ruleID!
    let revokedDynamic = await SystemCleanupScanner(applicationScanner: appScanner).scan(context: context,
        pack: .init(version: "fixture", issuedAt: .distantPast, rules: [broad], revokedRuleIDs: [dynamicID]))
    let chatPath = home.appendingPathComponent("Library/Caches/com.openai.codex").path
    require(!revokedDynamic.candidates.contains { $0.url.path == chatPath || chatPath.hasPrefix($0.url.path + "/") },
            "revoked dynamic app rules cannot fall back to broad cache removal")

    try await scanner.validateForExecution(offline, context: context, applications: apps)
    try await scanner.validateForExecution(scriptCache, context: context, applications: apps)
    let active = ScanContext(homeDirectory: home, runningBundleIdentifiers: [chrome.bundleIdentifier])
    let activeScan = try await scanner.scan(discovery: discovery, context: active)
    let activeChromeCandidates = activeScan.candidates.filter { $0.cleanupApplication?.bundleIdentifier == chrome.bundleIdentifier }
    let activeOffline = activeChromeCandidates.first { $0.url.path == offline.url.path }!
    let activeScript = activeChromeCandidates.first { $0.url.path == scriptCache.url.path }!
    require(!activeOffline.isActive && !activeScript.isActive
        && activeOffline.evidence.contains { $0.code == "active-cleanup" }
        && activeScript.evidence.contains { $0.code == "active-cleanup" },
        "running Chrome offline caches remain manually eligible with a visible regeneration warning")
    let activeReport = SystemScanReport(metadata: .init(startedAt: Date(), completedAt: Date(), rulesetVersion: "fixture"),
        modules: [:], generalCandidates: activeScan.candidates,
        applicationInventory: .init(applications: [], coverage: .init(), scannedAt: Date()),
        diskUsageTree: .init(roots: [], largeFiles: [], coverage: .init(), scannedAt: Date()),
        largeFileCandidates: [], agentAssets: [])
    let activeDefaultSelection = DefaultCleanupPolicy().selection(for: activeReport).systemCleanup
    require(!activeDefaultSelection.contains { $0.url.path == offline.url.path }
        && !activeDefaultSelection.contains { $0.url.path == scriptCache.url.path },
        "running Chrome offline roots are excluded from one-click cleanup selection")
    try await scanner.validateForExecution(offline, context: active, applications: apps)
    try await scanner.validateForExecution(scriptCache, context: active, applications: apps)
    let activeOtherApp = ScanContext(homeDirectory: home, runningBundleIdentifiers: [trae.bundleIdentifier])
    do { try await scanner.validateForExecution(otherOffline, context: activeOtherApp, applications: apps); require(false, "other running apps must still block offline cache cleanup") } catch is RuleScanError {}
    let chatCandidate = candidate("Library/Caches/com.openai.codex", in: result.candidates)!
    let protectedContext = ScanContext(homeDirectory: home, protectionPolicy: .init(
        entries: [.init(url: chatCandidate.url)], homeDirectory: home))
    do { try await scanner.validateForExecution(chatCandidate, context: protectedContext, applications: apps); require(false, "new protection invalidates old candidate") } catch is RuleScanError {}
    let credential = try file("Library/Caches/com.openai.codex/credentials.json")
    do { try await scanner.validateForExecution(chatCandidate, context: context, applications: apps); require(false, "new sensitive descendants invalidate old candidate") } catch is RuleScanError {}
    try fm.removeItem(at: credential)
    let external = home.appendingPathComponent("outside")
    try fm.createDirectory(at: external, withIntermediateDirectories: true)
    let link = home.appendingPathComponent("Library/Application Support/Trae CN/GPUCache")
    try fm.createSymbolicLink(at: link, withDestinationURL: external)
    let linkedDiscovery = await scanner.discover(applications: apps, context: context)
    require(!linkedDiscovery.targets.contains { $0.url == link } && linkedDiscovery.failures.contains { $0.path == link }, "symlinked cache roots rejected visibly")
    require(activeChromeCandidates.allSatisfy { $0.requiresExplicitSelection == true && !$0.isActive },
            "exact non-shared Chrome cache/log roots are manually selectable while running")

    let plan = try PlanBuilder(ruleVersion: "fixture", protectionPolicy: context.protectionPolicy).build(candidates: [offline], selectedIDs: [offline.id])
    let executor = CleanupExecutor(pathPolicy: context.pathPolicy, quarantineRoot: home.appendingPathComponent("quarantine"),
        currentRuleVersion: "fixture", loadProtection: { context.protectionPolicy },
        validateCandidate: { try await scanner.validateForExecution($0, context: active, applications: apps) })
    let receipt = await executor.execute(plan: plan)
    require(receipt.results.first?.disposition == .quarantined, "offline selection is quarantined while Chrome is running")
    require((canaries + manualChatFiles).allSatisfy { fm.fileExists(atPath: $0.path) }, "explicit cache cleanup leaves user-data and manual chat files intact")
    print("PASS: system cleanup partial results, Chrome profiles/offline defaults, application grouping, WeChat, and execution boundaries")
}
