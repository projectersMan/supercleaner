import CleanerCore
import CryptoKit
import Foundation

func runPackagedRuleConfigurationContract(binary: String) async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("packaged-rule-config-" + UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    let app = root.appendingPathComponent("Fixture.app")
    let executable = app.appendingPathComponent("Contents/MacOS/supercleaner")
    let resources = app.appendingPathComponent("Contents/Resources")
    try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try manager.createDirectory(at: resources, withIntermediateDirectories: true)
    try manager.copyItem(at: URL(fileURLWithPath: binary), to: executable)
    let originalBundle = URL(fileURLWithPath: binary).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/SuperCleaner_CleanerCore.bundle")
    try manager.copyItem(at: originalBundle, to: resources.appendingPathComponent("SuperCleaner_CleanerCore.bundle"))
    let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.fixture.SuperCleaner", "CFBundleExecutable": "supercleaner", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
    try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
    let key = Curve25519.Signing.PrivateKey()
    let configuration = ReleaseConfiguration(bundleIdentifier: "org.fixture.SuperCleaner", teamIdentifier: "A1B2C3D4E5", rulePublicKey: key.publicKey.rawRepresentation)
    try JSONEncoder().encode(configuration).write(to: resources.appendingPathComponent("release-configuration.json"))
    let home = root.appendingPathComponent("home")
    let cache = home.appendingPathComponent("Library/Caches/fixture")
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data("payload must survive".utf8).write(to: cache.appendingPathComponent("payload"))
    let rulesDirectory = home.appendingPathComponent("Library/Application Support/SuperCleaner/Rules")
    let store = RuleStore(directory: rulesDirectory, publicKey: key.publicKey.rawRepresentation, bundledURL: BundledCleanupRules.url)
    let rule = CleanupRule(ruleID: "network.fixture", category: .cache, relativePaths: ["Library/Caches/fixture"], minimumAgeDays: 0, defaultRisk: .review, sourceReference: "fixture", granularity: .root)
    let data = try JSONEncoder().encode(RulePack(version: "packaged-fixture", issuedAt: Date(), rules: [rule], revokedRuleIDs: []))
    try await store.install(update: .init(packData: data, signature: try key.signature(for: data)))
    let before = try Data(contentsOf: rulesDirectory.appendingPathComponent("state.json"))
    let result = try await BoundedProcess.run(executable.path, arguments: ["scan", "--module", "general", "--home", home.path], timeout: 30)
    require(result.status == 0 && result.stderr.isEmpty, "packaged CLI must load same signed release configuration and installed rules as GUI")
    let document = try JSONSerialization.jsonObject(with: result.stdout) as! [String: Any]
    let scan = document["scan"] as! [String: Any]
    let metadata = scan["metadata"] as! [String: Any]
    let candidates = scan["candidates"] as! [[String: Any]]
    require((metadata["ruleset_version"] as? String)?.hasPrefix("packaged-fixture:") == true, "CLI must use installed activation identity, not a bundled or empty-key fallback")
    require(candidates.contains { $0["rule_id"] as? String == "network.fixture" }, "installed signed rule must actually drive packaged CLI discovery")
    let after = try Data(contentsOf: rulesDirectory.appendingPathComponent("state.json"))
    require(before == after && manager.fileExists(atPath: cache.appendingPathComponent("payload").path), "configured CLI scan must remain read-only")
    require(!manager.fileExists(atPath: home.appendingPathComponent("Library/Application Support/SuperCleaner/history.json").path), "configured scan must not initialize unrelated state")
    print("PASS: packaged CLI shares public release key and active signed rules without writes")
}
