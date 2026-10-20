import Foundation

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
    func isReadable(_ url: URL) async -> Bool
    func isWritable(_ url: URL) async -> Bool
    func fileExists(_ url: URL) async -> Bool
    func readText(at url: URL, maximumBytes: Int) async throws -> String
    func readData(at url: URL, maximumBytes: Int) async throws -> Data
    func move(_ source: URL, to destination: URL) async throws
    func createDirectory(_ url: URL) async throws
    func removeEmptyDirectory(_ url: URL) async throws
    func trash(_ url: URL) async throws -> URL
}

public extension FileSystemAccess {
    func readData(at url: URL, maximumBytes: Int) async throws -> Data {
        Data(try await readText(at: url, maximumBytes: maximumBytes).utf8)
    }
    func readText(at url: URL, maximumBytes: Int) async throws -> String {
        throw FileSystemError.unreadableContent(url)
    }
}

public struct LocalFileSystem: FileSystemAccess {
    public init() {}

    public func identity(at url: URL) async throws -> FileIdentity {
        let manager = FileManager.default
        // Query the entry itself. fileExists follows the target and incorrectly
        // rejects dangling symlinks such as Electron's SingletonCookie.
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) {
                throw FileSystemError.missing(url)
            }
            throw error
        }
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            throw FileSystemError.invalidAttributes(url)
        }

        let kind: FileIdentity.Kind
        switch attributes[.type] as? FileAttributeType {
        case .typeRegular: kind = .file
        case .typeDirectory: kind = .directory
        case .typeSymbolicLink: kind = .symbolicLink
        default: kind = .other
        }

        return FileIdentity(
            device: device,
            inode: inode,
            size: size,
            modificationTime: Int64(modificationDate.timeIntervalSince1970),
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
