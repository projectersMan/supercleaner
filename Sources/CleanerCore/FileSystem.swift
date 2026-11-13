import Foundation
import Darwin

public enum FileSystemError: Error, Equatable, Sendable {
    case missing(URL)
    case invalidAttributes(URL)
    case directoryNotEmpty(URL)
    case trashUnavailable(URL)
    case unreadableContent(URL)
}

public protocol FileSystemAccess: Sendable {
    func identity(at url: URL) async throws -> FileIdentity
    func children(of url: URL) async throws -> [URL]
    /// A precise directory generation; nil disables snapshot reuse for virtual filesystems.
    func directoryGeneration(at url: URL) async throws -> String?
    func itemGeneration(at url: URL) async throws -> String?
    func isReadable(_ url: URL) async -> Bool
    func isWritable(_ url: URL) async -> Bool
    func isDeletable(_ url: URL) async -> Bool
    /// Read-only preflight for moving a directory into a different parent.
    /// This neither changes permissions nor guarantees future authorization.
    func canMoveDirectory(_ url: URL) async -> Bool
    func fileExists(_ url: URL) async -> Bool
    func readText(at url: URL, maximumBytes: Int) async throws -> String
    func readData(at url: URL, maximumBytes: Int) async throws -> Data
    func move(_ source: URL, to destination: URL) async throws
    func createDirectory(_ url: URL) async throws
    func removeEmptyDirectory(_ url: URL) async throws
    func trash(_ url: URL) async throws -> URL
}

public extension FileSystemAccess {
    func directoryGeneration(at url: URL) async throws -> String? { nil }
    func itemGeneration(at url: URL) async throws -> String? { nil }
    func isDeletable(_ url: URL) async -> Bool { await isWritable(url.deletingLastPathComponent()) }
    func canMoveDirectory(_ url: URL) async -> Bool {
        guard await isWritable(url) else { return false }
        return await isDeletable(url)
    }
    func readData(at url: URL, maximumBytes: Int) async throws -> Data {
        Data(try await readText(at: url, maximumBytes: maximumBytes).utf8)
    }
    func readText(at url: URL, maximumBytes: Int) async throws -> String {
        throw FileSystemError.unreadableContent(url)
    }
}

public struct LocalFileSystem: FileSystemAccess {
    public init() {}

    public func itemGeneration(at url: URL) async throws -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return "\(info.st_dev)|\(info.st_ino)|\(info.st_mode)|\(info.st_size)|\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)|\(info.st_uid)|\(info.st_gid)"
    }

    public func directoryGeneration(at url: URL) async throws -> String? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFDIR, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return "\(info.st_dev)|\(info.st_ino)|\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)|\(info.st_mode)|\(info.st_uid)|\(info.st_gid)"
    }

    public func identity(at url: URL) async throws -> FileIdentity {
        // attributesOfItem also resolves owner/group names via Directory Services.
        // Identity needs only lstat fields; never follow dangling or live symlinks.
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            let code = errno
            if code == ENOENT || code == ENOTDIR { throw FileSystemError.missing(url) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        guard info.st_size >= 0 else { throw FileSystemError.invalidAttributes(url) }

        let kind: FileIdentity.Kind
        switch info.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }

        return FileIdentity(
            device: UInt64(bitPattern: Int64(info.st_dev)),
            inode: UInt64(info.st_ino),
            size: UInt64(info.st_size),
            modificationTime: Int64(Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000),
            kind: kind
        )
    }

    public func children(of url: URL) async throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey],
            options: []
        )
    }

    public func isReadable(_ url: URL) async -> Bool { FileManager.default.isReadableFile(atPath: url.path) }
    public func isWritable(_ url: URL) async -> Bool { FileManager.default.isWritableFile(atPath: url.path) }
    public func isDeletable(_ url: URL) async -> Bool { FileManager.default.isDeletableFile(atPath: url.path) }
    public func fileExists(_ url: URL) async -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func readText(at url: URL, maximumBytes: Int) async throws -> String {
        guard maximumBytes > 0 else { return "" }
        let data = try await readData(at: url, maximumBytes: maximumBytes)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? String(data: data, encoding: .ascii)
        else {
            throw FileSystemError.unreadableContent(url)
        }
        return text
    }

    public func readData(at url: URL, maximumBytes: Int) async throws -> Data {
        let before = try await identity(at: url)
        guard maximumBytes > 0, before.kind == .file, before.size <= UInt64(maximumBytes) else {
            throw FileSystemError.unreadableContent(url)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes, try await identity(at: url) == before else {
            throw FileSystemError.unreadableContent(url)
        }
        return data
    }

    public func move(_ source: URL, to destination: URL) async throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func createDirectory(_ url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func removeEmptyDirectory(_ url: URL) async throws {
        let manager = FileManager.default
        guard try manager.contentsOfDirectory(atPath: url.path).isEmpty else {
            throw FileSystemError.directoryNotEmpty(url)
        }
        try manager.removeItem(at: url)
    }

    public func trash(_ url: URL) async throws -> URL {
        let manager = FileManager.default
        var resultingURL: NSURL?
        try manager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let resultingURL else { throw FileSystemError.trashUnavailable(url) }
        return resultingURL as URL
    }
}
