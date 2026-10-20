import CleanerCore
import CryptoKit
import Foundation

func runApplicationUpdatePolicyContracts() throws {
    let configuration = ReleaseConfiguration(bundleIdentifier: "com.test.Cleaner", teamIdentifier: "ABCDE12345",
        applicationUpdateURL: URL(string: "https://updates.example.com/appcast.xml")!,
        applicationPublicKey: Data(repeating: 1, count: 32), allowedHosts: ["updates.example.com"])
    let policy = ApplicationUpdatePolicy(configuration: configuration)
    func check(_ version: String = "2", current: String = "1", url: String = "https://updates.example.com/cleaner.dmg",
               length: UInt64 = 100, type: String = "application", signed: Bool = true, delta: Bool = false) throws {
        try policy.validate(version: version, currentVersion: current, archiveURL: URL(string: url), length: length,
                            installationType: type, feedIsSigned: signed, isDelta: delta)
    }
    try check()
    try check("100", current: "99")
    let cases: [() throws -> Void] = [
        { try check("1") }, { try check("1", current: "2") }, { try check("0") }, { try check("02") },
        { try check("2.0") }, { try check("v2") }, { try check("18446744073709551616") },
        { try check(signed: false) }, { try check(type: "package") }, { try check(delta: true) },
        { try check(length: 0) }, { try check(length: 536_870_913) },
        { try check(url: "http://updates.example.com/app.dmg") },
        { try check(url: "https://elsewhere.example.com/app.dmg") },
        { try check(url: "https://user:password@updates.example.com/app.dmg") },
        { try check(url: "https://updates.example.com:444/app.dmg") },
        { try check(url: "https://updates.example.com/app.zip") },
        { try check(url: "https://updates.example.com/app.pkg") },
        { try check(url: "https://updates.example.com/app.dmg?secret=1") },
    ]
    for invalid in cases {
        do { try invalid(); require(false, "invalid application update passed production policy") } catch { }
    }
    var settings: [String: Any] = ["SUFeedURL": configuration.applicationUpdateURL!.absoluteString,
        "SUPublicEDKey": configuration.applicationPublicKey!.base64EncodedString(), "CFBundleVersion": "1",
        "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUSignedFeedFailureExpirationInterval": 0,
        "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false, "SUAllowsAutomaticUpdates": false,
        "SUEnableSystemProfiling": false, "SUShowReleaseNotes": false, "SUEnableJavaScript": false]
    try policy.validateBundleSettings(settings)
    for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUShowReleaseNotes", "SUEnableJavaScript"] {
        var tampered = settings; tampered[key] = !(settings[key] as! Bool)
        do { try policy.validateBundleSettings(tampered); require(false, "unsafe Sparkle setting accepted: \(key)") } catch { }
    }
    settings["SUSignedFeedFailureExpirationInterval"] = 1
    do { try policy.validateBundleSettings(settings); require(false, "signed feed fail-open expiration accepted") } catch { }
    print("PASS: application update production policy, downgrade, origin, archive and manual signed-feed settings")
    let fixture = try SignedReleaseFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.checkFailureCases()
}

private final class SignedReleaseFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("signed-release-" + UUID().uuidString)
    let key = Curve25519.Signing.PrivateKey()
    let payload = Data("fixture archive bytes; not an installable application".utf8)
    var archive: URL { root.appendingPathComponent("SuperCleaner-1.dmg") }
    var feed: URL { root.appendingPathComponent("appcast.xml") }
    var configuration: ReleaseConfiguration {
        ReleaseConfiguration(bundleIdentifier: "com.test.Cleaner", teamIdentifier: "ABCDE12345",
            ruleUpdateURL: URL(string: "https://updates.example.com/rules.json")!,
            applicationUpdateURL: URL(string: "https://updates.example.com/appcast.xml")!,
            rulePublicKey: key.publicKey.rawRepresentation, applicationPublicKey: key.publicKey.rawRepresentation, allowedHosts: ["updates.example.com"])
    }
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try payload.write(to: archive)
        try writeFeed(xml())
    }
    func xml(version: String = "1", length: Int? = nil, extra: String = "") throws -> String {
        let signature = try key.signature(for: payload).base64EncodedString()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
        <sparkle:version>\(version)</sparkle:version><sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        <enclosure url="https://updates.example.com/SuperCleaner-1.dmg" length="\(length ?? payload.count)" sparkle:edSignature="\(signature)" />\(extra)
        </item></channel></rss>
        """
    }
    func writeFeed(_ xml: String) throws {
        let content = Data((xml + "\n").utf8)
        let signature = try key.signature(for: content).base64EncodedString()
        var result = content
        result.append(Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(content.count)\n-->\n".utf8))
        try result.write(to: feed)
    }
    @discardableResult func validate() throws -> String {
        try SignedApplicationRelease.validate(appcast: feed, archive: archive, configuration: configuration, expectedBuild: "1", minimumOS: "13.0")
    }
    func mustReject() {
        do { _ = try validate(); require(false, "untrusted release fixture accepted") } catch { }
    }
    func checkFailureCases() throws {
        let digest = try validate()
        require(digest == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), "release digest mismatch")
        let valid = try Data(contentsOf: feed)
        var tampered = valid; tampered[0] ^= 1
        try tampered.write(to: feed); mustReject()
        try valid.write(to: feed)
        var changed = payload; changed[0] ^= 1
        try changed.write(to: archive); mustReject()
        try payload.write(to: archive)
        try writeFeed(xml(version: "2")); mustReject()
        try writeFeed(xml(length: payload.count + 1)); mustReject()
        try writeFeed(xml(extra: "<sparkle:version>1</sparkle:version>")); mustReject()
        try writeFeed(xml().replacingOccurrences(of: "<rss", with: "<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss")); mustReject()
        try writeFeed(xml())
        let linked = root.appendingPathComponent("linked.dmg")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: archive)
        // Keep the expected basename to reach the no-follow archive check.
        let actual = root.appendingPathComponent("bytes.dmg")
        try FileManager.default.moveItem(at: archive, to: actual)
        try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: actual)
        mustReject()
        try FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: actual, to: archive)
        _ = try validate()
        print("PASS: public-key signed appcast/archive gate; first release, tampering, metadata, DTD and linked archive rejection")
    }
}

func runSparkleSigningInteropContract(tool: String) async throws {
    let fixture = try SignedReleaseFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let seed = fixture.root.appendingPathComponent("ephemeral-test-seed.txt")
    // Random test key only, never the user's key or Keychain; directory is 0700.
    try Data(fixture.key.rawRepresentation.base64EncodedString().utf8).write(to: seed)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: seed.path)
    let signed = try await BoundedProcess.run(tool, arguments: ["--ed-key-file", seed.path, fixture.feed.path], timeout: 15)
    require(signed.status == 0, "pinned Sparkle could not sign fixture feed")
    _ = try fixture.validate()
    let verified = try await BoundedProcess.run(tool, arguments: ["--verify", "--ed-key-file", seed.path, fixture.feed.path], timeout: 15)
    require(verified.status == 0, "pinned Sparkle rejected fixture Ed25519 feed")
    let signature = try fixture.key.signature(for: fixture.payload).base64EncodedString()
    let verifiedArchive = try await BoundedProcess.run(tool, arguments: ["--verify", "--ed-key-file", seed.path, fixture.archive.path, signature], timeout: 15)
    require(verifiedArchive.status == 0, "Sparkle/CryptoKit archive signature mismatch")
    var corrupt = try Data(contentsOf: fixture.feed); corrupt[0] ^= 1
    try corrupt.write(to: fixture.feed)
    let rejected = try await BoundedProcess.run(tool, arguments: ["--verify", "--ed-key-file", seed.path, fixture.feed.path], timeout: 15)
    require(rejected.status != 0, "Sparkle accepted tampered feed")
    fixture.mustReject()
    print("PASS: pinned Sparkle sign/verify and public release gate interoperate; tampered feed rejected; no Keychain access")
}

func runProductionSigningNegativeContract(application: String, script: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("production-signing-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Fixture.app")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: application), to: app)
    let id = "com.contract.Cleaner"
    let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let configuration = ReleaseConfiguration(bundleIdentifier: id, teamIdentifier: "ABCDE12345",
        ruleUpdateURL: URL(string: "https://updates.example.com/rules.json")!, applicationUpdateURL: URL(string: "https://updates.example.com/appcast.xml")!,
        rulePublicKey: key, applicationPublicKey: key, allowedHosts: ["updates.example.com"])
    try JSONEncoder().encode(configuration).write(to: app.appendingPathComponent("Contents/Resources/release-configuration.json"))
    let plistURL = app.appendingPathComponent("Contents/Info.plist")
    var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
    plist["CFBundleIdentifier"] = id
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
    let sign = try await BoundedProcess.run("/usr/bin/codesign", arguments: ["--force", "--sign", "-", "--options", "0", "--timestamp=none", "--identifier", id, app.path], timeout: 15)
    require(sign.status == 0, "temporary signing fixture failed")
    let gate = try await BoundedProcess.run(script, arguments: [app.path], timeout: 15)
    require(gate.status != 0 && String(decoding: gate.stdout, as: UTF8.self).contains("PASS: public release configuration"),
            "production gate did not specifically reject ad-hoc signing after complete public-config validation")
    print("PASS: production signing gate rejects ad-hoc app even with valid complete public configuration; no private keys or notary submission")
}
