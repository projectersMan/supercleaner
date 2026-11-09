import CleanerZIP
import Darwin
import Foundation

struct ExtractedZIPAnalyzer {
    let context: ScanContext
    let minimumBytes: UInt64

    private struct Entry {
        let path: String
        let size: UInt64
        let directory: Bool
    }

    private struct ZIPBudget {
        var scan: LargeFileContentBudget
        var archive = LargeFileContentBudget(bytes: 32 << 30, entries: 10_000, time: .seconds(8))
        var directoryLimited = false

        mutating func take(bytes: UInt64, entries: Int) -> Bool {
            archive.take(bytes: bytes, entries: entries) && scan.take(bytes: bytes, entries: entries)
        }
    }

    func match(_ archive: LargeFileContentSnapshot, avoiding targets: Set<String>, budget: inout LargeFileContentBudget,
               skippedBudget: inout Bool) -> [LargeFileContentSnapshot]? {
        var limits = ZIPBudget(scan: budget)
        defer {
            budget = limits.scan
            skippedBudget = skippedBudget || limits.archive.limited || limits.directoryLimited
        }
        let minimumFolderBytes = max(minimumBytes, archive.bytes)
        guard let manifest = withZIP(archive, budget: &limits, body: {
            readManifest($0, minimumFolderBytes: minimumFolderBytes, budget: &$1)
        }) else { return nil }
        let parent = archive.url.deletingLastPathComponent()
        guard let folders = FileManager.default.enumerator(at: parent, includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsSubdirectoryDescendants], errorHandler: Self.stopOnAccessError) else { return nil }
        let prefixes = Self.rootPrefixes(manifest)
        for case let folder as URL in folders {
            guard limits.take(bytes: 0, entries: 1) else { return nil }
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let root = LargeFileContentAnalyzer.eligibleSnapshot(folder, context: context), root.isDirectory,
                  !root.isWithin(any: targets) else { continue }
            for prefix in prefixes {
                guard let tree = matchTree(manifest, prefix: prefix, root: root, avoiding: targets, budget: &limits) else { continue }
                let equal = withZIP(archive, budget: &limits) { reader, limits in
                    verify(reader, manifest: manifest, prefix: prefix, files: tree, budget: &limits)
                }
                if equal == true && root.isCurrent && tree.values.allSatisfy(\.isCurrent) {
                    return [root] + tree.values.sorted { $0.url.path < $1.url.path }
                }
            }
        }
        return nil
    }

    private func withZIP<T>(_ file: LargeFileContentSnapshot, budget: inout ZIPBudget,
                            body: (OpaquePointer, inout ZIPBudget) -> T?) -> T? {
        guard let fd = LargeFileContentIO.openFile(file) else { return nil }
        defer { close(fd) }
        guard let directory = Self.directorySize(fd, bytes: file.bytes) else { return nil }
        guard directory.bytes <= 16 << 20, directory.entries <= 10_000 else {
            budget.directoryLimited = true
            return nil
        }
        guard budget.take(bytes: directory.bytes, entries: 0) else { return nil }
        guard let reader = archive_read_new() else { return nil }
        defer { archive_read_free(reader) }
        guard archive_read_support_format_zip_seekable(reader) == CleanerArchiveOK,
              archive_read_set_format_option(reader, "zip", "mac-ext", nil) == CleanerArchiveOK,
              archive_read_open_fd(reader, fd, 65_536) == CleanerArchiveOK else { return nil }
        let result = body(reader, &budget)
        guard LargeFileContentIO.matches(fd, file), file.isCurrent else { return nil }
        return result
    }

    // Inspect the fixed end records before libarchive builds its central-directory index.
    private static func directorySize(_ fd: Int32, bytes: UInt64) -> (bytes: UInt64, entries: UInt64)? {
        let tailSize = Int(min(bytes, 65_557))
        let tailOffset = bytes - UInt64(tailSize)
        guard tailSize >= 22, let first = readRecord(fd, offset: 0, count: 4),
              value(first, 0, as: UInt32.self) == 0x04034b50,
              let tail = readRecord(fd, offset: tailOffset, count: tailSize) else { return nil }
        for end in stride(from: tailSize - 22, through: 0, by: -1) {
            guard value(tail, end, as: UInt32.self) == 0x06054b50,
                  end + 22 + Int(value(tail, end + 20, as: UInt16.self)) == tailSize else { continue }
            guard value(tail, end + 4, as: UInt32.self) == 0,
                  value(tail, end + 8, as: UInt16.self) == value(tail, end + 10, as: UInt16.self) else { return nil }
            let count = value(tail, end + 10, as: UInt16.self)
            let length = value(tail, end + 12, as: UInt32.self)
            let offset = value(tail, end + 16, as: UInt32.self)
            let endOffset = tailOffset + UInt64(end)
            if count == .max || length == .max || offset == .max {
                return zip64DirectorySize(fd, endOffset: endOffset)
            }
            guard UInt64(offset) + UInt64(length) == endOffset else { return nil }
            return (UInt64(length), UInt64(count))
        }
        return nil
    }

    private static func zip64DirectorySize(_ fd: Int32, endOffset: UInt64) -> (bytes: UInt64, entries: UInt64)? {
        guard endOffset >= 20, let locator = readRecord(fd, offset: endOffset - 20, count: 20),
              value(locator, 0, as: UInt32.self) == 0x07064b50, value(locator, 4, as: UInt32.self) == 0,
              value(locator, 16, as: UInt32.self) == 1 else { return nil }
        let offset = value(locator, 8, as: UInt64.self)
        guard offset <= endOffset - 20, endOffset - 20 - offset >= 56,
              let record = readRecord(fd, offset: offset, count: 56), value(record, 0, as: UInt32.self) == 0x06064b50,
              value(record, 4, as: UInt64.self) == endOffset - 32 - offset,
              value(record, 16, as: UInt64.self) == 0,
              value(record, 24, as: UInt64.self) == value(record, 32, as: UInt64.self) else { return nil }
        let length = value(record, 40, as: UInt64.self)
        let start = value(record, 48, as: UInt64.self)
        guard start <= offset, length == offset - start else { return nil }
        return (length, value(record, 32, as: UInt64.self))
    }

    private static func readRecord(_ fd: Int32, offset: UInt64, count: Int) -> Data? {
        var data = Data(count: count)
        return data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, count, off_t(offset)) } == count ? data : nil
    }

    private static func value<T: FixedWidthInteger>(_ data: Data, _ offset: Int, as type: T.Type) -> T {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: type).littleEndian }
    }

    private func readManifest(_ reader: OpaquePointer, minimumFolderBytes: UInt64, budget: inout ZIPBudget) -> [String: Entry]? {
        var entries: [String: Entry] = [:]
        var explicitPaths = Set<String>()
        var spellings: [String: String] = [:]
        var expandedBytes: UInt64 = 0
        while budget.take(bytes: 0, entries: 1) {
            var header: OpaquePointer?
            let status = archive_read_next_header(reader, &header)
            // An exact tree match has the manifest's total size. Exclude undersized
            // matches before walking sibling directories or decoding any payload.
            if status == CleanerArchiveEOF { return expandedBytes >= minimumFolderBytes ? entries : nil }
            guard status == CleanerArchiveOK, let header, let entry = Self.entry(header),
                  explicitPaths.insert(entry.path).inserted else { return nil }
            let (total, overflow) = expandedBytes.addingReportingOverflow(entry.size)
            guard !overflow else { return nil }
            expandedBytes = total
            var components = entry.path.split(separator: "/")
            while !components.isEmpty {
                let path = components.joined(separator: "/")
                let key = path.lowercased()
                if let spelling = spellings[key], spelling != path { return nil }
                spellings[key] = path
                let current = path == entry.path ? entry : Entry(path: path, size: 0, directory: true)
                if let previous = entries[path], !previous.directory || !current.directory { return nil }
                entries[path] = current
                components.removeLast()
            }
        }
        return nil
    }

    private static func entry(_ header: OpaquePointer) -> Entry? {
        var macMetadataBytes = 0
        guard archive_entry_is_encrypted(header) == 0,
              archive_entry_hardlink(header) == nil, archive_entry_xattr_count(header) == 0,
              archive_entry_mac_metadata(header, &macMetadataBytes) == nil, macMetadataBytes == 0,
              let raw = archive_entry_pathname_utf8(header), let name = String(validatingCString: raw) else { return nil }
        let type = archive_entry_filetype(header)
        let directory = type == S_IFDIR
        guard directory || type == S_IFREG else { return nil }
        let path = directory && name.hasSuffix("/") ? String(name.dropLast()) : name
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 32, path.utf8.count <= 4_096,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0 != "__MACOSX" && !$0.hasPrefix("._") }),
              !path.contains("\\"), !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let bytes = archive_entry_size(header)
        guard directory ? bytes == 0 : archive_entry_size_is_set(header) != 0 && bytes >= 0 else { return nil }
        return Entry(path: path, size: UInt64(bytes), directory: directory)
    }

    private static func rootPrefixes(_ manifest: [String: Entry]) -> [String] {
        let roots = manifest.values.filter { !$0.path.contains("/") }
        guard roots.count == 1, let root = roots.first, root.directory else { return [""] }
        return [root.path + "/", ""]
    }

    private func matchTree(_ manifest: [String: Entry], prefix: String, root: LargeFileContentSnapshot, avoiding targets: Set<String>,
                           budget: inout ZIPBudget) -> [String: LargeFileContentSnapshot]? {
        let expectedCount = manifest.count - (prefix.isEmpty ? 0 : 1)
        guard let sample = manifest.values.filter({ !$0.directory }).min(by: { $0.path < $1.path }),
              let first = LargeFileContentAnalyzer.eligibleSnapshot(root.url.appendingPathComponent(String(sample.path.dropFirst(prefix.count))), context: context),
              !first.isDirectory, first.bytes == sample.size else { return nil }
        var accessFailed = false
        guard let iterator = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            accessFailed = true
            return false
        }) else { return nil }
        var matched: [String: LargeFileContentSnapshot] = [:]
        for case let url as URL in iterator {
            guard budget.take(bytes: 0, entries: 1) else { return nil }
            let path = prefix + String(url.standardizedFileURL.path.dropFirst(root.url.path.count + 1))
            guard let entry = manifest[path], let snapshot = LargeFileContentAnalyzer.eligibleSnapshot(url, context: context),
                  entry.directory == snapshot.isDirectory, entry.directory || entry.size == snapshot.bytes,
                  !snapshot.isWithin(any: targets) else { return nil }
            matched[path] = snapshot
        }
        return !accessFailed && matched.count == expectedCount && root.isCurrent ? matched : nil
    }

    private func verify(_ reader: OpaquePointer, manifest: [String: Entry], prefix: String,
                        files: [String: LargeFileContentSnapshot], budget: inout ZIPBudget) -> Bool? {
        while budget.take(bytes: 0, entries: 1) {
            var header: OpaquePointer?
            let status = archive_read_next_header(reader, &header)
            if status == CleanerArchiveEOF { return true }
            guard status == CleanerArchiveOK, let header, let entry = Self.entry(header),
                  manifest[entry.path]?.size == entry.size else { return false }
            if entry.directory { continue }
            guard entry.path.hasPrefix(prefix), let disk = files[entry.path],
                  compare(reader, to: disk, budget: &budget) else { return false }
        }
        return false
    }

    private func compare(_ reader: OpaquePointer, to disk: LargeFileContentSnapshot, budget: inout ZIPBudget) -> Bool {
        guard let fd = LargeFileContentIO.openFile(disk) else { return false }
        defer { close(fd) }
        var data = Data(count: LargeFileContentIO.chunkBytes)
        var remaining = disk.bytes
        while remaining > 0 {
            let count = Int(min(remaining, UInt64(data.count)))
            guard budget.take(bytes: UInt64(count) * 2, entries: 0) else { return false }
            let read = data.withUnsafeMutableBytes { archive_read_data(reader, $0.baseAddress, count) }
            guard read > 0, read <= count,
                  let local = LargeFileContentIO.readChunk(fd, count: read), local == data.prefix(read) else { return false }
            remaining -= UInt64(read)
        }
        // Reading through end-of-entry also verifies the archive's CRC and size.
        var extra: UInt8 = 0
        return archive_read_data(reader, &extra, 1) == 0 && LargeFileContentIO.matches(fd, disk) && disk.isCurrent
    }

    private static func stopOnAccessError(_ url: URL, _ error: Error) -> Bool { false }
}
