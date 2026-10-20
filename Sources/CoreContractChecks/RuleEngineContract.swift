import CleanerCore
import CryptoKit
import Foundation

func runRuleEngineContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("rules-contract-\(UUID().uuidString)")
    let home = root.appendingPathComponent("home")
    let cache = home.appendingPathComponent("Library/Caches/example")
    let file = cache.appendingPathComponent("old.bin")
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    try Data("fixture".utf8).write(to: file)
    let now = Date()
    for path in [file, cache] {
        try manager.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: path.path)
    }
    let rule = CleanupRule(
        ruleID: "fixture.cache", category: .cache, relativePaths: ["Library/Caches"],
        minimumAgeDays: 30, defaultRisk: .safe, ownershipEvidence: "fixture owner",
        regenerationEvidence: "fixture can be rebuilt", defaultSelection: true,
        minimumOSVersion: "13.0", sourceReference: "fixture-source",
        granularity: .children, activeProcessNames: ["fixture-process"], maximumDepth: 8, maximumEntries: 100
    )
    let pack = RulePack(version: "fixture-1", issuedAt: now, rules: [rule], revokedRuleIDs: [])
    let fs = LocalFileSystem()
    let context = ScanContext(homeDirectory: home, fileSystem: fs, now: now)
    let engine = CleanupRuleEngine(pack: pack, operatingSystemVersion: "15.0")
    let found = try await engine.scan(context: context)
    require(found.count == 1 && found[0].risk == .safe && found[0].defaultSelection == true, "precise rules must drive candidates and defaults")
    let candidate = found[0]
    let tooOldOS = try await CleanupRuleEngine(pack: pack, operatingSystemVersion: "12.9").scan(context: context)
    require(tooOldOS.isEmpty, "OS-incompatible rules must not scan")
    let revoked = RulePack(version: pack.version, issuedAt: now.addingTimeInterval(1), rules: [rule], revokedRuleIDs: [rule.ruleID])
    let revokedCandidates = try await CleanupRuleEngine(pack: revoked).scan(context: context)
    require(revokedCandidates.isEmpty && revoked.executionVersion != pack.executionVersion, "revocation must change execution identity and remove rule")
    let active = try await engine.scan(context: ScanContext(homeDirectory: home, now: now, activeProcessNames: ["fixture-process"]))
    require(active.first?.risk == .safe && active.first?.isActive == true, "active tool must remain manually selectable with explicit activity evidence")
    let unknown = try await engine.scan(context: ScanContext(homeDirectory: home, now: now, activityProbeAvailable: false))
    require(unknown.first?.risk == .safe && unknown.first?.isActive == true, "unknown tool activity must remain manually selectable and visible")

    let key = Curve25519.Signing.PrivateKey()
    let store = RuleStore(directory: root.appendingPathComponent("rules"), publicKey: key.publicKey.rawRepresentation, bundledURL: BundledCleanupRules.url)
    let bundled = try await store.currentPack()
    require(bundled.version == "bundled-3", "production rule store must load the bundled fallback")
    require(bundled.rules.count >= 15, "bundled rules must cover more than the initial cache set")
    require(bundled.rules.allSatisfy {
        $0.sourceKind?.isEmpty == false && $0.sourceReference?.isEmpty == false
            && $0.testFixture?.isEmpty == false && $0.ownershipEvidence?.isEmpty == false
    }, "every bundled rule must carry source, fixture and ownership governance metadata")
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sourceLedger = try String(contentsOf: repositoryRoot.appendingPathComponent("docs/rule-sources.md"), encoding: .utf8)
    require(bundled.rules.allSatisfy { rule in
        rule.sourceReference.map(sourceLedger.contains) == true
    }, "every bundled source reference must exist in the rule source ledger")
    let broad = bundled.rules.first { $0.ruleID == "discovery.user-caches" }
    require(broad?.defaultRisk == .review && broad?.defaultSelection == false, "cache age alone cannot authorize default cleanup")
    require(bundled.rules.first { $0.ruleID == "developer.uv-managed-cache" }?.defaultRisk == .blocked, "uv managed cache must reject direct removal")
    let expandedRuleIDs = Set(bundled.rules.map(\.ruleID))
    require(["developer.go-build-cache", "developer.deno-cache", "developer.cargo-download-cache",
             "developer.cocoapods-cache", "developer.playwright-browsers"].allSatisfy(expandedRuleIDs.contains),
            "officially sourced developer caches must remain in the bundled catalog")
    let goCache = home.appendingPathComponent("Library/Caches/go-build")
    let goArtifact = goCache.appendingPathComponent("00/build.a")
    try manager.createDirectory(at: goArtifact.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("go cache fixture".utf8).write(to: goArtifact)
    for path in [goArtifact, goArtifact.deletingLastPathComponent(), goCache] {
        try manager.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: path.path)
    }
    let bundledCandidates = try await CleanupRuleEngine(pack: bundled, operatingSystemVersion: "15.0").scan(context: context)
    require(bundledCandidates.contains { $0.ruleID == "developer.go-build-cache" && $0.risk == .safe && $0.defaultSelection == true },
            "precise Go build cache rule must override broad cache discovery and remain regenerable")
    let encoded = try JSONEncoder().encode(pack)
    try await store.install(update: SignedRuleUpdate(packData: encoded, signature: try key.signature(for: encoded)))
    let firstIdentity = try await store.currentPack().executionVersion
    let secondData = try JSONEncoder().encode(revoked)
    try await store.install(update: SignedRuleUpdate(packData: secondData, signature: try key.signature(for: secondData)))
    let changedIdentity = try await store.currentPack().executionVersion
    require(changedIdentity != firstIdentity, "same version updates must invalidate old plans")
    try await store.rollback()
    let rolledBackIdentity = try await store.currentPack().executionVersion
    let rolledBack = try await store.currentPack()
    require(rolledBack.rules == pack.rules && rolledBack.revokedRuleIDs.contains(rule.ruleID), "rollback must restore signed rule contents without reactivating a revoked rule")
    require(rolledBackIdentity != firstIdentity && rolledBackIdentity != changedIdentity, "each explicit activation/rollback must invalidate previous plans")
    let unsafe = CleanupRule(ruleID: "unsafe", category: .cache, relativePaths: ["Library/Caches"], minimumAgeDays: 30, defaultRisk: .safe)
    let unsafeData = try JSONEncoder().encode(RulePack(version: "bad", issuedAt: now, rules: [unsafe], revokedRuleIDs: []))
    do {
        try await store.install(update: SignedRuleUpdate(packData: unsafeData, signature: try key.signature(for: unsafeData)))
        require(false, "safe rules without regeneration evidence must be rejected")
    } catch is RuleStoreError {}

    let protectionStore = ProtectionStore(url: root.appendingPathComponent("protections.json"), homeDirectory: home)
    let protectedFile = try await protectionStore.protect(file)
    do { try protectedFile.validate(cache); require(false, "protected child must protect its parent removal") } catch is ProtectionError {}
    do { try protectedFile.validate(file.appendingPathComponent("nested")); require(false, "protected parent must protect descendants") } catch is ProtectionError {}
    try protectedFile.validate(home.appendingPathComponent("Library/Caches/example-sibling"))
    let persisted = try await protectionStore.snapshot()
    require(persisted.entries == protectedFile.entries, "protection paths must persist")
    let link = home.appendingPathComponent("alias")
    try manager.createSymbolicLink(at: link, withDestinationURL: cache)
    do { try persisted.validate(link); require(false, "symlink ancestor must not bypass protection") } catch is ProtectionError {}
    let protectedCandidates = try await engine.scan(context: ScanContext(homeDirectory: home, now: now, protectionPolicy: persisted))
    require(protectedCandidates.first?.risk == .blocked, "scanner must enforce persistent protection")
    let builder = PlanBuilder(ruleVersion: rolledBackIdentity, protectionPolicy: persisted)
    do { _ = try builder.build(candidates: found, selectedIDs: [candidate.id]); require(false, "planner must enforce protection") } catch is PlanBuilderError {}
    _ = try await protectionStore.remove(id: persisted.entries[0].id)
    let plan = try PlanBuilder(ruleVersion: rolledBackIdentity).build(candidates: found, selectedIDs: [candidate.id])
    _ = try await protectionStore.protect(file)
    let executor = CleanupExecutor(
        fileSystem: fs, pathPolicy: PathPolicy(homeDirectory: home), quarantineRoot: root.appendingPathComponent("quarantine"),
        currentRuleVersion: rolledBackIdentity, loadProtection: { try await protectionStore.snapshot() },
        loadRuleVersion: { try await store.currentPack().executionVersion }
    )
    let denied = await executor.execute(plan: plan)
    require(denied.results.first?.status == .skippedProtected && manager.fileExists(atPath: file.path), "new protection must reject previously valid plan without moving files")
    try Data("corrupt".utf8).write(to: root.appendingPathComponent("protections.json"))
    let corrupt = await executor.execute(plan: plan)
    require(corrupt.results.first?.status == .skippedProtected && manager.fileExists(atPath: file.path), "unreadable protection policy must fail closed")
    let thirdData = try JSONEncoder().encode(RulePack(version: "fixture-2", issuedAt: now.addingTimeInterval(2), rules: [rule], revokedRuleIDs: [rule.ruleID]))
    try await store.install(update: SignedRuleUpdate(packData: thirdData, signature: try key.signature(for: thirdData)))
    let stale = await executor.execute(plan: plan)
    require(stale.overallStatus == .rejected, "rule update must reject stale plan before file effects")

    let credential = cache.appendingPathComponent("credentials.json")
    try Data("sensitive fixture".utf8).write(to: credential)
    let sensitive = try await engine.scan(context: context)
    require(sensitive.first?.risk == .blocked, "sensitive descendants must block whole-directory removal")
    let tiny = CleanupRule(ruleID: "budget", category: .cache, relativePaths: ["Library/Caches"], minimumAgeDays: 30, defaultRisk: .review, maximumDepth: 1, maximumEntries: 1)
    do {
        let limited = try await CleanupRuleEngine(pack: RulePack(version: "tiny", issuedAt: now, rules: [tiny], revokedRuleIDs: [])).scan(context: context)
        require(limited.allSatisfy { $0.risk == .blocked }, "incomplete inspection cannot create deletable candidate")
    } catch is RuleScanError {}
    let rawIdentity = pack.executionVersion
    let activeIdentity = try await store.currentPack().executionVersion
    for _ in 0..<5 {
        let reread = try await store.currentPack().executionVersion
        require(pack.executionVersion == rawIdentity && reread == activeIdentity, "rule content and persisted activation identity must be deterministic")
    }
    print("PASS: rule-driven scanning, signed update/rollback and persistent protection contracts")
}
