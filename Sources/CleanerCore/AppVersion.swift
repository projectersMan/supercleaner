import Foundation

/// Installed metadata is authoritative, including CI overrides made during packaging.
public struct AppVersion: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.text("未打包")
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    public static let current = AppVersion()
}
