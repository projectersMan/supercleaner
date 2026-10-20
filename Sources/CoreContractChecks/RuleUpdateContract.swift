import CleanerCore
import CryptoKit
import Foundation

private struct SignedRuleFixtureTransport: UpdateTransport {
    let data: Data
    var shouldFail = false
    var delay: Duration?
    func download(from url: URL, to destination: URL, policy: UpdateDownloadPolicy, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> DownloadedUpdate {
        try policy.validate(url)
        if shouldFail { throw UpdateDownloadError.failed }
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        try data.write(to: destination)
        progress(Int64(data.count), Int64(data.count))
        return .init(fileURL: destination, sourceURL: url, byteCount: Int64(data.count), sha256: "fixture-envelope")
    }
}

func runRuleUpdateContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("rule-updates-" + UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let key = Curve25519.Signing.PrivateKey()
    let url = URL(string: "https://updates.fixture.test/rules.json")!
    let config = ReleaseConfiguration(bundleIdentifier: "org.contract.SuperCleaner", teamIdentifier: "A1B2C3D4E5", ruleUpdateURL: url, rulePublicKey: key.publicKey.rawRepresentation, allowedHosts: ["updates.fixture.test"])
    try config.validate()
    do { try config.validate(requireComplete: true); require(false, "incomplete production release config passed full gate") } catch ReleaseConfigurationError.missing { }
    let offline = ReleaseConfiguration(bundleIdentifier: "org.contract.SuperCleaner", teamIdentifier: "A1B2C3D4E5", rulePublicKey: key.publicKey.rawRepresentation)
    try offline.validate()
    var unsafeConfiguration = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
    unsafeConfiguration["privateKey"] = "must-never-be-embedded"
    do { _ = try JSONDecoder().decode(ReleaseConfiguration.self, from: JSONSerialization.data(withJSONObject: unsafeConfiguration)); require(false, "unknown/private deployment fields accepted") } catch { }
    let credentialURLConfig = ReleaseConfiguration(bundleIdentifier: config.bundleIdentifier, teamIdentifier: config.teamIdentifier,
        ruleUpdateURL: URL(string: "https://updates.fixture.test/rules?token=secret")!, rulePublicKey: key.publicKey.rawRepresentation, allowedHosts: config.allowedHosts)
    do { try credentialURLConfig.validate(); require(false, "credential-like feed query accepted into public configuration") } catch { }
    let now = Date()
    let joinedIDs = RulePack(version: "hash-fixture", issuedAt: now, rules: [], revokedRuleIDs: ["a\nb"])
    let separateIDs = RulePack(version: "hash-fixture", issuedAt: now, rules: [], revokedRuleIDs: ["a", "b"])
    require(joinedIDs.executionVersion != separateIDs.executionVersion, "execution identity must preserve field/array boundaries rather than join untrusted strings")
    let rule = CleanupRule(ruleID: "fixture.cache", category: .cache, relativePaths: ["Library/Caches/fixture"], minimumAgeDays: 30, defaultRisk: .review, sourceReference: "independent-fixture")
    func signed(_ version: String, seconds: Double, revoked: Set<String> = []) throws -> SignedRuleUpdate {
        let data = try JSONEncoder().encode(RulePack(version: version, issuedAt: now.addingTimeInterval(seconds), rules: [rule], revokedRuleIDs: revoked))
        return .init(packData: data, signature: try key.signature(for: data))
    }
    let first = try signed("1", seconds: -100)
    let second = try signed("2", seconds: -50, revoked: [rule.ruleID])
    let third = try signed("3", seconds: -1)
    let fourth = try signed("4", seconds: 1)
    let store = RuleStore(directory: root.appendingPathComponent("rules"), publicKey: key.publicKey.rawRepresentation)
    func service(_ update: SignedRuleUpdate, fail: Bool = false, delay: Duration? = nil) throws -> RuleUpdateService {
        RuleUpdateService(store: store, configuration: config, transport: SignedRuleFixtureTransport(data: try JSONEncoder().encode(update), shouldFail: fail, delay: delay))
    }
    let one = try await service(first).update()
    require(one.version == "1" && one.activationID != nil, "network workflow must activate only signed payload and persist a local revision")
    let oneReloaded = try await store.currentPack()
    require(one.executionVersion == oneReloaded.executionVersion, "activation revision must survive disk reload")
    for badService in [
        try service(.init(packData: second.packData, signature: Data(repeating: 0, count: 64))),
        try service(second, fail: true),
    ] {
        do { _ = try await badService.update(); require(false, "invalid signature or network failure replaced rules") } catch { }
        let unchanged = try await store.currentPack()
        require(unchanged.executionVersion == one.executionVersion, "failed update must retain active pack and activation revision")
    }
    let cancelService = try service(second, delay: .seconds(3))
    let cancelled = Task { try await cancelService.update() }
    try await Task.sleep(for: .milliseconds(50)); cancelled.cancel()
    do { _ = try await cancelled.value; require(false, "cancelled download activated rules") } catch is CancellationError { }
    let afterCancel = try await store.currentPack()
    require(afterCancel.executionVersion == one.executionVersion, "cancellation before commit must leave current pack untouched")
    _ = try await service(second).update()
    let three = try await service(third).update()
    require(three.revokedRuleIDs.contains(rule.ruleID), "a later signed pack cannot implicitly forget historical revocations")
    await store.failNextCommitForTesting()
    do { _ = try await service(fourth).update(); require(false, "interrupted atomic commit succeeded") } catch RuleStoreError.interruptedCommit { }
    let afterFailure = try await store.currentPack()
    require(afterFailure.executionVersion == three.executionVersion, "interrupted commit must preserve both current and previous slots")
    let rolled = try await service(third).rollback()
    require(rolled.version == "2" && rolled.revokedRuleIDs.contains(rule.ruleID) && rolled.executionVersion != three.executionVersion, "explicit rollback changes activation but retains signed revocation evidence")
    for replay in [first, second, third] {
        do { try await store.install(update: replay); require(false, "old feed or rolled-back highest pack replayed") } catch RuleStoreError.downgrade { }
    }
    let four = try await service(fourth).update()
    try await store.install(update: fourth)
    let duplicate = try await store.currentPack()
    require(duplicate.executionVersion == four.executionVersion, "identical current feed must be a no-op")
    let equalTime = try signed("different", seconds: 1)
    do { try await store.install(update: equalTime); require(false, "different payload reused monotonic issue time") } catch RuleStoreError.downgrade { }
    let future = try signed("future", seconds: 3_600)
    do { try await store.install(update: future); require(false, "future-dated rules froze the update high-water mark") } catch RuleStoreError.futureDated { }
    let imported = root.appendingPathComponent("offline.json")
    try JSONEncoder().encode(try signed("5", seconds: 2)).write(to: imported)
    let five = try await RuleUpdateService(store: store, configuration: offline).importUpdate(at: imported)
    require(five.version == "5", "offline signed import must use same signature/replay/atomic policy")
    let stateURL = root.appendingPathComponent("rules/state.json")
    var currentState = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
    var brokenCurrent = currentState["current"] as! [String: Any]
    brokenCurrent["signature"] = Data(repeating: 0, count: 64).base64EncodedString()
    currentState["current"] = brokenCurrent
    try JSONSerialization.data(withJSONObject: currentState).write(to: stateURL, options: .atomic)
    do { _ = try await store.currentPack(); require(false, "tampered active signature was trusted") } catch RuleStoreError.invalidSignature { }
    let canRepair = try await store.canRollback()
    require(canRepair, "bad current signature must not hide a still-verified previous slot")
    let repaired = try await RuleUpdateService(store: store, configuration: offline).rollback()
    require(repaired.version == "4" && repaired.revokedRuleIDs.contains(rule.ruleID), "explicit rollback repairs current while preserving signed high water and revocations")
    let badPrevious = try? await store.canRollback()
    require(badPrevious != true, "corrupted previous slot must not be advertised as a verified rollback target")
    let link = root.appendingPathComponent("linked.json")
    try manager.createSymbolicLink(at: link, withDestinationURL: imported)
    do { _ = try await RuleUpdateService(store: store, configuration: offline).importUpdate(at: link); require(false, "linked import silently read another file") } catch { }

    let bundledURL = root.appendingPathComponent("bundled.json")
    let bundled = RulePack(version: "bundled-fixture", issuedAt: now.addingTimeInterval(-1_000), rules: [rule], revokedRuleIDs: [])
    try JSONEncoder().encode(bundled).write(to: bundledURL)
    let initialStore = RuleStore(directory: root.appendingPathComponent("initial-failure"), publicKey: key.publicKey.rawRepresentation, bundledURL: bundledURL)
    let beforeInitialization = try await initialStore.currentPack()
    await initialStore.failAfterBaselineForTesting()
    do { try await initialStore.install(update: first); require(false, "initial failure after marker unexpectedly committed") } catch RuleStoreError.interruptedCommit { }
    let preservedBundle = try await initialStore.currentPack()
    require(preservedBundle.executionVersion == beforeInitialization.executionVersion, "initial commit failure must retain healthy bundled rules, not leave marker-only failure")
    try await initialStore.install(update: first)
    try await initialStore.rollback()
    let backToBundle = try await initialStore.currentPack()
    require(backToBundle.version == bundled.version && backToBundle.activationID != nil, "first-update rollback must restore bundled pack with a new activation revision")
    try await initialStore.install(update: try signed("newer", seconds: 3))
    let bundleRevocation = RulePack(version: "bundled-newer", issuedAt: now, rules: [rule], revokedRuleIDs: [rule.ruleID])
    try JSONEncoder().encode(bundleRevocation).write(to: bundledURL, options: .atomic)
    let protectedByNewBundle = try await initialStore.currentPack()
    require(protectedByNewBundle.version == "newer" && protectedByNewBundle.revokedRuleIDs.contains(rule.ruleID), "new application-bundled revocations must apply even while an installed rule pack remains active")

    let legacyRoot = root.appendingPathComponent("legacy")
    try manager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    try JSONEncoder().encode(second).write(to: legacyRoot.appendingPathComponent("current.json"))
    try JSONEncoder().encode(first).write(to: legacyRoot.appendingPathComponent("previous.json"))
    let legacy = RuleStore(directory: legacyRoot, publicKey: key.publicKey.rawRepresentation)
    let legacyPack = try await legacy.currentPack()
    require(legacyPack.version == "2" && !manager.fileExists(atPath: legacyRoot.appendingPathComponent("state.json").path), "legacy read must remain read-only before migration")
    try await legacy.install(update: third)
    let migrated = try await legacy.currentPack()
    require(migrated.version == "3" && migrated.revokedRuleIDs.contains(rule.ruleID), "atomic migration must preserve current, previous and revocations")
    try manager.removeItem(at: legacyRoot.appendingPathComponent("state.json"))
    do { _ = try await legacy.currentPack(); require(false, "missing initialized state fell back to old legacy or bundled rules") } catch RuleStoreError.invalidStorage { }
    let alias = root.appendingPathComponent("aliased-rule-root")
    try manager.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("rules"))
    do { _ = try await RuleStore(directory: alias, publicKey: key.publicKey.rawRepresentation).currentPack(); require(false, "linked rule store root accepted") } catch RuleStoreError.invalidStorage { }
    print("PASS: signed rule download/import, atomic failure preservation, sticky revocations, replay resistance, activation invalidation and migration")
}
