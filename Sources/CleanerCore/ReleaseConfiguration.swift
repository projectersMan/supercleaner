import Darwin
import Foundation

public enum ReleaseConfigurationError: Error, LocalizedError, Sendable {
    case missing, invalid, wrongApplication
    public var errorDescription: String? {
        switch self {
        case .missing: "发布更新尚未配置"
        case .invalid: "发布身份、更新源或签名公钥配置无效"
        case .wrongApplication: "发布配置不属于当前应用身份"
        }
    }
}

/// Public deployment data only. Private signing keys, passwords, authorization
/// forms and notarization credentials must never enter this document.
public struct ReleaseConfiguration: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let ruleUpdateURL: URL?
    public let applicationUpdateURL: URL?
    public let rulePublicKey: Data?
    public let applicationPublicKey: Data?
    public let allowedHosts: Set<String>
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, bundleIdentifier, teamIdentifier, ruleUpdateURL, applicationUpdateURL, rulePublicKey, applicationPublicKey, allowedHosts
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(bundleIdentifier: String, teamIdentifier: String, ruleUpdateURL: URL? = nil, applicationUpdateURL: URL? = nil, rulePublicKey: Data? = nil, applicationPublicKey: Data? = nil, allowedHosts: Set<String> = []) {
        schemaVersion = 1; self.bundleIdentifier = bundleIdentifier; self.teamIdentifier = teamIdentifier
        self.ruleUpdateURL = ruleUpdateURL; self.applicationUpdateURL = applicationUpdateURL
        self.rulePublicKey = rulePublicKey; self.applicationPublicKey = applicationPublicKey; self.allowedHosts = allowedHosts
    }
    public init(from decoder: any Decoder) throws {
        let arbitrary = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        guard Set(arbitrary.allKeys.map(\.stringValue)).isSubset(of: known) else { throw ReleaseConfigurationError.invalid }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        teamIdentifier = try values.decode(String.self, forKey: .teamIdentifier)
        ruleUpdateURL = try values.decodeIfPresent(URL.self, forKey: .ruleUpdateURL)
        applicationUpdateURL = try values.decodeIfPresent(URL.self, forKey: .applicationUpdateURL)
        rulePublicKey = try values.decodeIfPresent(Data.self, forKey: .rulePublicKey)
        applicationPublicKey = try values.decodeIfPresent(Data.self, forKey: .applicationPublicKey)
        allowedHosts = try values.decode(Set<String>.self, forKey: .allowedHosts)
        try validate()
    }
    public func validate(requireComplete: Bool = false) throws {
        guard schemaVersion == 1, (try? HelperSigningIdentity(applicationIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier)) != nil,
              allowedHosts.count <= 16, allowedHosts.allSatisfy(UpdateDownloadPolicy.validHost),
              rulePublicKey == nil || rulePublicKey?.count == 32,
              applicationPublicKey == nil || applicationPublicKey?.count == 32 else { throw ReleaseConfigurationError.invalid }
        let policy = UpdateDownloadPolicy(allowedHosts: allowedHosts, maximumBytes: 1_500_000)
        for url in [ruleUpdateURL, applicationUpdateURL].compactMap({ $0 }) {
            try policy.validate(url)
            guard url.query == nil else { throw ReleaseConfigurationError.invalid }
        }
        guard ruleUpdateURL == nil || rulePublicKey != nil, applicationUpdateURL == nil || applicationPublicKey != nil else { throw ReleaseConfigurationError.invalid }
        if requireComplete, ruleUpdateURL == nil || applicationUpdateURL == nil || rulePublicKey == nil || applicationPublicKey == nil { throw ReleaseConfigurationError.missing }
    }
    public static func applicationBundle(containing executable: URL? = Bundle.main.executableURL) -> Bundle? {
        var cursor = executable?.deletingLastPathComponent() ?? Bundle.main.bundleURL
        for _ in 0..<8 {
            if cursor.pathExtension.lowercased() == "app" { return Bundle(url: cursor) }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return Bundle.main.bundleURL.pathExtension.lowercased() == "app" ? Bundle.main : nil
    }
    public static func load(bundle: Bundle? = nil) throws -> ReleaseConfiguration? {
        guard let bundle = bundle ?? applicationBundle(), let url = bundle.url(forResource: "release-configuration", withExtension: "json") else { return nil }
        let configuration = try JSONDecoder().decode(Self.self, from: UpdateFileContent.read(url, maximumBytes: 65_536))
        try configuration.validate()
        guard configuration.bundleIdentifier == bundle.bundleIdentifier else { throw ReleaseConfigurationError.wrongApplication }
        return configuration
    }
}

public enum UpdateFileContent {
    public static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard url.isFileURL, maximumBytes > 0, maximumBytes <= 8_388_608 else { throw ReleaseConfigurationError.invalid }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ReleaseConfigurationError.invalid }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), before.st_size <= maximumBytes else { throw ReleaseConfigurationError.invalid }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        var after = stat()
        guard data.count <= maximumBytes, fstat(fd, &after) == 0,
              before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw ReleaseConfigurationError.invalid }
        return data
    }
}
