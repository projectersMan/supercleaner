import Foundation

public extension ByteCountFormatter {
    static func cleanerString(bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 KB" }
        guard bytes >= 1_000 else { return "< 1 KB" }
        return string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
