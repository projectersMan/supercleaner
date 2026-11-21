import CryptoKit
import Foundation

public enum CommercialConfigurationError: Error, LocalizedError, Sendable {
    case missing, unknownField, invalidSchemaVersion, invalidProductID, invalidAPIBaseURL, invalidPublicKey

    public var errorDescription: String? {
        switch self {
        case .missing: L10n.text("缺少商业授权配置，无法启用购买、扫描或新清理。")
        case .unknownField: L10n.text("商业授权配置包含未知字段；只允许公开产品、接口和验签公钥。")
        case .invalidSchemaVersion: L10n.text("商业授权配置版本无效。")
        case .invalidProductID: L10n.text("商业授权产品标识为空、无效或仍为占位值。")
        case .invalidAPIBaseURL: L10n.text("商业授权接口必须为有效的生产 HTTPS 地址，且不得包含凭据、查询参数或占位值。")
        case .invalidPublicKey: L10n.text("商业授权必须配置有效的 Ed25519 公钥，禁止使用私钥或占位值。")
        }
    }
}

/// Public deployment identity only. Business price, device limits and lease duration live on the service.
public struct CommercialConfiguration: Decodable, Hashable, Sendable {
    public let schemaVersion: Int
    public let productID: String
    public let apiBaseURL: URL
    public let licensePublicKey: Data

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, productID, apiBaseURL, licensePublicKey
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let arbitrary = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        guard Set(arbitrary.allKeys.map(\.stringValue)).isSubset(of: known) else {
            throw CommercialConfigurationError.unknownField
        }
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try fields.decode(Int.self, forKey: .schemaVersion)
        productID = try fields.decode(String.self, forKey: .productID)
        let apiURLString = try fields.decode(String.self, forKey: .apiBaseURL)
        let publicKeyString = try fields.decode(String.self, forKey: .licensePublicKey)
        guard schemaVersion == 1 else { throw CommercialConfigurationError.invalidSchemaVersion }
        guard !productID.isEmpty, productID.count <= 255,
              productID == productID.trimmingCharacters(in: .whitespacesAndNewlines),
              productID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !Self.isPlaceholder(productID) else {
            throw CommercialConfigurationError.invalidProductID
        }
        guard let url = URL(string: apiURLString), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              host.contains("."), !Self.isPlaceholder(host),
              host != "0.0.0.0", host != "127.0.0.1", !host.hasSuffix(".local"),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".invalid"),
              !host.hasSuffix(".test"), !host.hasSuffix(".example"),
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              apiURLString.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw CommercialConfigurationError.invalidAPIBaseURL
        }
        apiBaseURL = url
        guard !Self.isPlaceholder(publicKeyString), let key = Data(base64Encoded: publicKeyString),
              key.count == 32, key.contains(where: { $0 != 0 }) else {
            throw CommercialConfigurationError.invalidPublicKey
        }
        licensePublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key).rawRepresentation
    }

    public static func load(bundle: Bundle? = nil) throws -> CommercialConfiguration {
        guard let source = bundle ?? ReleaseConfiguration.applicationBundle(),
              let url = source.url(forResource: "commercial-configuration", withExtension: "json") else {
            throw CommercialConfigurationError.missing
        }
        return try CommercialConfiguration(data: UpdateFileContent.read(url, maximumBytes: 65_536))
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        return ["replace", "changeme", "change_me", "your_", "your-", "placeholder", "todo", "example.com", "example.org", "example.net"].contains(where: lower.contains)
    }
}
