import CryptoKit
import Foundation

struct AppRuntimeIdentitySnapshot: Equatable {
    let buildIdentity: String

    static func current(bundle: Bundle = .main) -> AppRuntimeIdentitySnapshot {
        let executableURL = bundle.executableURL
        return AppRuntimeIdentitySnapshot(
            buildIdentity: executableURL.flatMap(binaryFingerprint) ?? bundle.bundleURL.path
        )
    }

    private static func binaryFingerprint(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
