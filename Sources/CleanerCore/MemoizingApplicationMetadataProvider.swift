import Darwin
import Foundation

/// Reuses only metadata parsing and signature inspection. Each hit checks the
/// current generations of every directory and code input read by the provider;
/// installed-app enumeration and all ownership/running checks remain live.
final class MemoizingApplicationMetadataProvider: ApplicationMetadataProviding, @unchecked Sendable {
    static let shared = MemoizingApplicationMetadataProvider()
    private struct Entry {
        let metadata: ApplicationBundleMetadata
        let stamps: [String: String]
    }
    private let base: any ApplicationMetadataProviding
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init(base: any ApplicationMetadataProviding = BundleApplicationMetadataProvider()) { self.base = base }

    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        let path = bundleURL.path
        if let entry = lock.withLock({ entries[path] }), Self.unchanged(entry.stamps) {
            return entry.metadata
        }
        _ = lock.withLock { entries.removeValue(forKey: path) }
        let stamps = Self.inputs(for: bundleURL)
        guard let metadata = base.metadata(for: bundleURL) else { return nil }
        if let stamps, Self.unchanged(stamps) {
            lock.withLock {
                if entries.count >= 256 { entries.removeAll(keepingCapacity: true) }
                entries[path] = Entry(metadata: metadata, stamps: stamps)
            }
        }
        return metadata
    }

    private static func unchanged(_ stamps: [String: String]) -> Bool {
        !Task.isCancelled && stamps.allSatisfy { stamp($0.key) == $0.value }
    }

    private static func stamp(_ path: String) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT || errno == ENOTDIR ? "missing" : nil }
        // Do not reuse metadata whose inputs can resolve through another path.
        guard info.st_mode & S_IFMT != S_IFLNK else { return nil }
        return "\(info.st_dev)|\(info.st_ino)|\(info.st_mode)|\(info.st_size)|\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)|\(info.st_uid)|\(info.st_gid)"
    }

    private static func inputs(for bundle: URL) -> [String: String]? {
        var stamps = [String: String]()
        func record(_ url: URL) -> Bool {
            guard let generation = stamp(url.path) else { return false }
            stamps[url.path] = generation
            return true
        }
        func codeInputs(_ url: URL) -> Bool {
            let contents = url.appendingPathComponent("Contents")
            let infoURL = contents.appendingPathComponent("Info.plist")
            for input in [url, contents, infoURL, contents.appendingPathComponent("MacOS"),
                          contents.appendingPathComponent("_CodeSignature"), contents.appendingPathComponent("_CodeSignature/CodeResources")] {
                guard record(input) else { return false }
            }
            guard let size = try? infoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                  let data = try? Data(contentsOf: infoURL),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
            if let executable = info["CFBundleExecutable"] as? String {
                guard ApplicationDataDiscovery.safeRelativePath(executable),
                      record(contents.appendingPathComponent("MacOS").appendingPathComponent(executable)) else { return false }
            }
            return true
        }
        guard codeInputs(bundle) else { return nil }
        let roots = ["XPCServices", "PlugIns", "Extensions", "Helpers", "Applications", "Library/LoginItems", "Library/LaunchServices", "Library/SystemExtensions"]
        var pending = roots.map { bundle.appendingPathComponent("Contents/" + $0) }
        var visited = 0
        while let directory = pending.popLast() {
            guard !Task.isCancelled, record(directory) else { return nil }
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            guard let children = try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { return nil }
            for child in children {
                visited += 1
                guard visited <= 512, let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return nil }
                guard values.isDirectory == true else { continue }
                guard values.isSymbolicLink != true, record(child) else { return nil }
                if ["app", "xpc", "appex", "bundle"].contains(child.pathExtension.lowercased()), !codeInputs(child) { return nil }
                if child.pathExtension.lowercased() != "framework" { pending.append(child) }
            }
        }
        return stamps
    }
}
