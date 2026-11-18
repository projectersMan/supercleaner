import Darwin
import Foundation

/// A volume measurement independent of cleanup receipts and purgeable capacity.
public struct DiskCapacitySnapshot: Equatable, Sendable {
    public let volumeURL: URL
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let recordedAt: Date

    public var usedBytes: UInt64 { totalBytes - availableBytes }
    public var usedFraction: Double { Double(usedBytes) / Double(totalBytes) }

    public init?(volumeURL: URL, totalBytes: UInt64, availableBytes: UInt64, recordedAt: Date) {
        guard totalBytes > 0, availableBytes <= totalBytes else { return nil }
        self.volumeURL = volumeURL
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.recordedAt = recordedAt
    }
}

public enum DiskCapacityReadResult: Sendable {
    case available(DiskCapacitySnapshot)
    case unavailable(Int32)
}

public enum DiskCapacityReader {
    /// Reads the filesystem containing `url`; available bytes exclude purgeable data.
    public static func read(at url: URL) -> DiskCapacityReadResult {
        guard url.isFileURL, !url.path(percentEncoded: false).utf8.contains(0) else { return .unavailable(EINVAL) }
        var fileSystem = statfs()
        let readError = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return EINVAL }
            return statfs(path, &fileSystem) == 0 ? 0 : errno
        }
        guard readError == 0 else { return .unavailable(readError) }

        let blockSize = UInt64(fileSystem.f_bsize)
        let total = fileSystem.f_blocks.multipliedReportingOverflow(by: blockSize)
        let available = fileSystem.f_bavail.multipliedReportingOverflow(by: blockSize)
        guard !total.overflow, !available.overflow else { return .unavailable(EOVERFLOW) }

        let mountPath = withUnsafeBytes(of: fileSystem.f_mntonname) { bytes -> String? in
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            return String(bytes: bytes[..<end], encoding: .utf8)
        }
        guard let mountPath, !mountPath.isEmpty,
              let snapshot = DiskCapacitySnapshot(
                volumeURL: URL(fileURLWithPath: mountPath, isDirectory: true),
                totalBytes: total.partialValue,
                availableBytes: available.partialValue,
                recordedAt: Date()
              ) else {
            return .unavailable(EINVAL)
        }
        return .available(snapshot)
    }
}
