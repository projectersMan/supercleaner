import Darwin
import Foundation

let rootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let instant = Date(timeIntervalSince1970: 1_800_000_000)
let measured = DiskCapacitySnapshot(volumeURL: rootURL, totalBytes: 1_000, availableBytes: 400, recordedAt: instant)!
precondition(measured.usedBytes == 600)
precondition(measured.usedFraction == 0.6)
precondition(DiskCapacitySnapshot(volumeURL: rootURL, totalBytes: 0, availableBytes: 0, recordedAt: instant) == nil)
precondition(DiskCapacitySnapshot(volumeURL: rootURL, totalBytes: UInt64.max - 1, availableBytes: UInt64.max, recordedAt: instant) == nil)
let maximum = DiskCapacitySnapshot(volumeURL: rootURL, totalBytes: UInt64.max, availableBytes: 1, recordedAt: instant)!
precondition(maximum.usedBytes == UInt64.max - 1 && maximum.usedFraction.isFinite)

switch DiskCapacityReader.read(at: rootURL) {
case let .available(snapshot):
    precondition(snapshot.totalBytes > 0)
    precondition(snapshot.usedBytes + snapshot.availableBytes == snapshot.totalBytes)
    print("mount=\(snapshot.volumeURL.path) total=\(snapshot.totalBytes) available=\(snapshot.availableBytes) used=\(snapshot.usedBytes)")
case let .unavailable(error):
    preconditionFailure("Existing directory read failed: \(error)")
}

switch DiskCapacityReader.read(at: rootURL.appendingPathComponent(UUID().uuidString)) {
case .available:
    preconditionFailure("Missing directory read succeeded")
case let .unavailable(error):
    precondition(error == ENOENT)
}
switch DiskCapacityReader.read(at: URL(string: "https://example.com/")!) {
case .available:
    preconditionFailure("Non-file URL read succeeded")
case let .unavailable(error):
    precondition(error == EINVAL)
}
switch DiskCapacityReader.read(at: URL(fileURLWithPath: "/\0missing")) {
case .available:
    preconditionFailure("Null-containing URL read succeeded")
case let .unavailable(error):
    precondition(error == EINVAL)
}
print("Disk capacity standalone checks passed")
