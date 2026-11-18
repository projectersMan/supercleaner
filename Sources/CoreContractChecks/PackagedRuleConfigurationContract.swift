import CleanerCore
import CryptoKit
import Foundation

func runPackagedRuleConfigurationContract(application: String) async throws {
    let manager = FileManager.default
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tests/local-ai-projects-disk/cli", isDirectory: true)
    let root = fixtures.appendingPathComponent("packaged-rule-config-" + UUID().uuidString)
    let app = root.appendingPathComponent("Fixture.app")
    let executable = app.appendingPathComponent("Contents/MacOS/CoreContractChecks")
    let resources = app.appendingPathComponent("Contents/Resources")
    try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try manager.createDirectory(at: resources, withIntermediateDirectories: true)
    try manager.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
    let originalBundle = URL(fileURLWithPath: application).appendingPathComponent("Contents/Resources/SuperCleaner_CleanerCore.bundle")
    try manager.copyItem(at: originalBundle, to: resources.appendingPathComponent("SuperCleaner_CleanerCore.bundle"))
    let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.fixture.SuperCleaner", "CFBundleExecutable": "CoreContractChecks", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
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
    let result = try await BoundedProcess.run(executable.path, arguments: ["--assert-packaged-rule-config", home.path], timeout: 30)
    require(result.status == 0 && result.stderr.isEmpty,
            "packaged Core checker must load the same release configuration and installed signed rules as GUI: \(String(decoding: result.stderr, as: UTF8.self))")
    let after = try Data(contentsOf: rulesDirectory.appendingPathComponent("state.json"))
    require(before == after && manager.fileExists(atPath: cache.appendingPathComponent("payload").path), "configured Core scan must remain read-only")
    require(!manager.fileExists(atPath: home.appendingPathComponent("Library/Application Support/SuperCleaner/history.json").path), "configured scan must not initialize unrelated state")
    try manager.removeItem(at: root)
    print("PASS: packaged Core resources, public release key and active signed rules without writes")
}

func runPackagedRuleConfigurationSelfCheck(home: String) async throws {
    guard let bundle = ReleaseConfiguration.applicationBundle(), let configuration = try ReleaseConfiguration.load() else {
        throw ReleaseConfigurationError.missing
    }
    require(configuration.bundleIdentifier == "org.fixture.SuperCleaner" && configuration.rulePublicKey?.count == 32,
            "packaged rule fixture must require its explicit application identity and signing key")
    let resources = bundle.bundleURL.appendingPathComponent("Contents/Resources/SuperCleaner_CleanerCore.bundle").resolvingSymlinksInPath().path
    require(BundledCleanupRules.url.resolvingSymlinksInPath().path.hasPrefix(resources + "/"),
            "packaged rules must resolve from the copied application resources")
    let homeURL = URL(fileURLWithPath: home)
    let runtime = CleanupRuntime(home: homeURL, fileSystem: ReviewScanFileSystem(home: homeURL))
    let active = try await runtime.configuration()
    require(active.pack.executionVersion.hasPrefix("packaged-fixture:"),
            "packaged runtime must use installed activation identity, not a bundled or empty-key fallback")
    let scan = await SystemCleanupScanner().scan(context: active.context, pack: active.pack)
    require(scan.failures.isEmpty && scan.candidates.contains { $0.ruleID == "network.fixture" },
            "installed signed rule must drive packaged Core discovery")
    print("PASS: packaged resource and signed-rule self-check")
}
