import Foundation

public extension ByteCountFormatter {
    static func cleanerString(bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 KB" }
        guard bytes >= 1_000 else { return "< 1 KB" }
        return Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(L10n.language.locale))
    }
}
