import Darwin
import Foundation

public struct LargeFileCleanupProof: Codable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable { case identicalCopy, extractedZIP }

    public let reason: Reason
    public let target: LargeFileContentSnapshot
    public let retained: [LargeFileContentSnapshot]

    public var title: String {
        switch reason {
        case .identicalCopy: L10n.text("内容完全相同")
        case .extractedZIP: L10n.text("ZIP 已完整解压")
        }
    }

    func matches(_ candidate: CleanupCandidate) -> Bool {
        candidate.category == .largeFile && candidate.source == .diskAnalysis
            && candidate.url.standardizedFileURL.path == target.url.path
            && candidate.identity.device == target.device && candidate.identity.inode == target.inode
            && candidate.identity.size == target.bytes && !retained.isEmpty
            && retained.allSatisfy { !target.isSameObject(as: $0) }
    }

    func isCurrent(for candidate: CleanupCandidate) -> Bool {
        matches(candidate) && LargeFileContentIO.withLocalAccess {
            target.isCurrent && retained.allSatisfy { $0.isCurrent && access($0.url.path, R_OK) == 0 }
        } == true
    }

    static func conflictingCandidate(in candidates: [CleanupCandidate]) -> CleanupCandidate? {
        guard candidates.contains(where: { $0.largeFileProof != nil }) else { return nil }
        let paths = Set(candidates.flatMap { candidate in
            [candidate.url.standardizedFileURL.path, candidate.url.resolvingSymlinksInPath().standardizedFileURL.path]
        })
        let targets = Set(candidates.map { FileObject(device: $0.identity.device, inode: $0.identity.inode) })
        return candidates.first { candidate in
            guard let proof = candidate.largeFileProof else { return false }
            return !proof.matches(candidate) || proof.retained.contains { item in
                targets.contains(FileObject(device: item.device, inode: item.inode)) || item.isWithin(any: paths)
            }
        }
    }

    private struct FileObject: Hashable {
        let device: UInt64
        let inode: UInt64
    }
}

public struct LargeFileContentSnapshot: Codable, Hashable, Sendable {
    public let url: URL
    let device: UInt64
    let inode: UInt64
    let bytes: UInt64
    let mode: mode_t
    let links: UInt16
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int

    init?(url: URL, facts: stat) {
        let kind = facts.st_mode & S_IFMT
        guard kind == S_IFDIR || (kind == S_IFREG && facts.st_nlink == 1),
              facts.st_flags & UInt32(SF_DATALESS) == 0, facts.st_size >= 0 else { return nil }
        self.url = url.standardizedFileURL
        device = UInt64(UInt32(bitPattern: facts.st_dev))
        inode = facts.st_ino
        bytes = UInt64(facts.st_size)
        mode = facts.st_mode
        links = facts.st_nlink
        modifiedSeconds = facts.st_mtimespec.tv_sec
        modifiedNanos = facts.st_mtimespec.tv_nsec
        changedSeconds = facts.st_ctimespec.tv_sec
        changedNanos = facts.st_ctimespec.tv_nsec
    }

    var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
    var isCurrent: Bool { Self.at(url) == self }

    static func at(_ url: URL) -> Self? {
        let literal = url.standardizedFileURL
        var facts = stat()
        var volume = statfs()
        guard literal.path == literal.resolvingSymlinksInPath().standardizedFileURL.path,
              lstat(literal.path, &facts) == 0,
              statfs(literal.path, &volume) == 0, volume.f_flags & UInt32(MNT_LOCAL) != 0 else { return nil }
        return Self(url: literal, facts: facts)
    }

    func isSameObject(as other: Self) -> Bool { device == other.device && inode == other.inode }

    func isWithin(any paths: Set<String>) -> Bool {
        var parent = url
        while true {
            if paths.contains(parent.path) { return true }
            if parent.path == "/" { return false }
            parent.deleteLastPathComponent()
        }
    }
}

enum LargeFileContentIO {
    static let chunkBytes = 1_048_576

    // This setting belongs to the current thread, so keep the body synchronous.
    static func withLocalAccess<T>(_ body: () -> T) -> T? {
        let kind = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let scope = IOPOL_SCOPE_THREAD
        let previous = getiopolicy_np(kind, scope)
        guard previous >= 0, setiopolicy_np(kind, scope, IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0 else { return nil }
        defer { _ = setiopolicy_np(kind, scope, previous) }
        return body()
    }

    static func openFile(_ snapshot: LargeFileContentSnapshot) -> Int32? {
        guard !snapshot.isDirectory else { return nil }
        let fd = open(snapshot.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        guard matches(fd, snapshot) else { close(fd); return nil }
        return fd
    }

    static func matches(_ fd: Int32, _ snapshot: LargeFileContentSnapshot) -> Bool {
        var facts = stat()
        return fstat(fd, &facts) == 0 && LargeFileContentSnapshot(url: snapshot.url, facts: facts) == snapshot
    }

    static func readChunk(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var filled = 0
        while filled < count {
            let n = data.withUnsafeMutableBytes { buffer in
                read(fd, buffer.baseAddress?.advanced(by: filled), count - filled)
            }
            if n == 0 { break }
            if n < 0 { return nil }
            filled += n
        }
        data.count = filled
        return data
    }

    static func attributes(_ fd: Int32) -> [String: Data]? {
        let length = flistxattr(fd, nil, 0, 0)
        guard length >= 0, length <= chunkBytes else { return nil }
        if length == 0 { return [:] }
        var names = [CChar](repeating: 0, count: length)
        guard flistxattr(fd, &names, length, 0) == length else { return nil }
        var result: [String: Data] = [:]
        var remaining = chunkBytes
        for encoded in names.split(separator: 0) {
            guard let name = String(bytes: encoded.map { UInt8(bitPattern: $0) }, encoding: .utf8) else { return nil }
            let size = fgetxattr(fd, name, nil, 0, 0, 0)
            guard size >= 0, size <= remaining else { return nil }
            var value = Data(count: size)
            guard value.withUnsafeMutableBytes({ fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }) == size else { return nil }
            result[name] = value
            remaining -= size
        }
        return result
    }
}
