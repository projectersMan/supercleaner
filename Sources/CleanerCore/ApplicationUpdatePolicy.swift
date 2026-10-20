import Foundation

public enum ApplicationUpdateError: Error, LocalizedError, Sendable {
    case invalidVersion, downgrade, untrustedFeed, invalidArchive, busy, helperStillRegistered
    public var errorDescription: String? {
        switch self {
        case .invalidVersion: L10n.text("应用构建号必须是正整数")
        case .downgrade: L10n.text("拒绝相同或更低构建号的更新")
        case .untrustedFeed: L10n.text("更新目录没有通过签名验证")
        case .invalidArchive: L10n.text("更新必须是明确发布主机上的完整应用 DMG")
        case .busy: L10n.text("请先结束扫描、清理、恢复或其他更新")
        case .helperStillRegistered: L10n.text("Helper 尚未解除注册，不能开始应用更新")
        }
    }
}

/// Production policy used by the Sparkle delegate and release preflight. Sparkle
/// owns archive Ed25519 verification, extraction, native authorization and atomic
/// replacement. No second installer or generic privileged write interface exists.
public struct ApplicationUpdatePolicy: Sendable {
    public let configuration: ReleaseConfiguration
    public init(configuration: ReleaseConfiguration) { self.configuration = configuration }

    public static func buildNumber(_ version: String) throws -> UInt64 {
        guard !version.isEmpty, version.count <= 19, version.utf8.allSatisfy({ (48...57).contains($0) }),
              version.first != "0", let value = UInt64(version), value > 0 else { throw ApplicationUpdateError.invalidVersion }
        return value
    }

    public func validate(version: String, currentVersion: String, archiveURL: URL?, length: UInt64,
                         installationType: String, feedIsSigned: Bool, isDelta: Bool = false) throws {
        try configuration.validate()
        guard feedIsSigned else { throw ApplicationUpdateError.untrustedFeed }
        guard try Self.buildNumber(version) > Self.buildNumber(currentVersion) else { throw ApplicationUpdateError.downgrade }
        try validateArchive(archiveURL: archiveURL, length: length, installationType: installationType, isDelta: isDelta)
    }
    public func validateArchive(archiveURL: URL?, length: UInt64, installationType: String, isDelta: Bool = false) throws {
        try configuration.validate()
        guard let archiveURL, installationType == "application", !isDelta,
              archiveURL.pathExtension.lowercased() == "dmg", archiveURL.query == nil,
              length > 0, length <= 536_870_912 else { throw ApplicationUpdateError.invalidArchive }
        try UpdateDownloadPolicy(allowedHosts: configuration.allowedHosts, maximumBytes: 536_870_912).validate(archiveURL)
    }

    public func validateBundleSettings(_ settings: [String: Any]) throws {
        try configuration.validate()
        guard let feed = configuration.applicationUpdateURL, let key = configuration.applicationPublicKey,
              settings["SUFeedURL"] as? String == feed.absoluteString,
              settings["SUPublicEDKey"] as? String == key.base64EncodedString(),
              settings["SURequireSignedFeed"] as? Bool == true,
              settings["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              settings["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
              settings["SUEnableAutomaticChecks"] as? Bool == false,
              settings["SUAutomaticallyUpdate"] as? Bool == false,
              settings["SUAllowsAutomaticUpdates"] as? Bool == false,
              settings["SUEnableSystemProfiling"] as? Bool == false,
              settings["SUShowReleaseNotes"] as? Bool == false,
              settings["SUEnableJavaScript"] as? Bool == false else { throw ReleaseConfigurationError.invalid }
        _ = try Self.buildNumber(settings["CFBundleVersion"] as? String ?? "")
    }
}
