import CleanerCore
import CryptoKit
import Foundation

private enum RulePublishingValidationError: Error, LocalizedError {
    case invalidPath, mismatchedPayload, invalidVersion, reusedKey, wrongWorkingDirectory

    var errorDescription: String? {
        switch self {
        case .invalidPath: "Rule publishing inputs must be absolute regular files without symbolic links."
        case .mismatchedPayload: "Published packData differs from the original RulePack bytes."
        case .invalidVersion: "Rule publication version must be a nonempty printable label without surrounding whitespace."
        case .reusedKey: "Rule publishing requires an Ed25519 key independent of the Sparkle key."
        case .wrongWorkingDirectory: "Run the rule verifier from the repository root; verification state belongs under Tests."
        }
    }
}

/// Used by the publishing CLI before exposing an envelope. Signature and full rule
/// schema validation deliberately run through the same RuleStore as the application.
func validateRulePublication(configurationPath: String, rawPackPath: String, envelopePath: String) async throws {
    let configurationURL = try rulePublishingInput(configurationPath)
    let rawURL = try rulePublishingInput(rawPackPath)
    let envelopeURL = try rulePublishingInput(envelopePath)
    let configuration = try JSONDecoder().decode(ReleaseConfiguration.self,
        from: UpdateFileContent.read(configurationURL, maximumBytes: 65_536))
    try configuration.validate(requireComplete: true)
    guard let publicKey = configuration.rulePublicKey,
          publicKey != configuration.applicationPublicKey else { throw RulePublishingValidationError.reusedKey }
    let raw = try UpdateFileContent.read(rawURL, maximumBytes: 1_048_576)
    let update = try JSONDecoder().decode(SignedRuleUpdate.self,
        from: UpdateFileContent.read(envelopeURL, maximumBytes: 1_500_000))
    guard update.packData == raw else { throw RulePublishingValidationError.mismatchedPayload }
    let decoded = try JSONDecoder().decode(RulePack.self, from: raw)
    guard !decoded.version.isEmpty,
          decoded.version == decoded.version.trimmingCharacters(in: .whitespacesAndNewlines),
          decoded.version.rangeOfCharacter(from: .controlCharacters) == nil else {
        throw RulePublishingValidationError.invalidVersion
    }
    let manager = FileManager.default
    let root = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
    guard manager.fileExists(atPath: root.appendingPathComponent("Package.swift").path),
          manager.fileExists(atPath: root.appendingPathComponent("Tests", isDirectory: true).path) else {
        throw RulePublishingValidationError.wrongWorkingDirectory
    }
    let fixtures = root.appendingPathComponent("Tests/commercial-launch/fixtures", isDirectory: true)
    try manager.createDirectory(at: fixtures, withIntermediateDirectories: true)
    let state = fixtures.appendingPathComponent("rule-validation-" + UUID().uuidString, isDirectory: true)
    let store = RuleStore(directory: state, publicKey: publicKey, bundledURL: BundledCleanupRules.url)
    try await store.install(update: update)
    let validated = try await store.currentPack()
    guard validated.version == decoded.version else { throw RulePublishingValidationError.mismatchedPayload }
    try manager.removeItem(at: state)
    let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
    print("PASS: published RulePack original bytes, Ed25519 signature and application RuleStore schema; SHA256 \(digest)")
}

private func rulePublishingInput(_ path: String) throws -> URL {
    guard path.hasPrefix("/") else { throw RulePublishingValidationError.invalidPath }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path == url.resolvingSymlinksInPath().path else { throw RulePublishingValidationError.invalidPath }
    return url
}
