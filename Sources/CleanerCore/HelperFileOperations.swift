import Darwin
import Foundation

/// This scope comes from the authenticated connection's uid and the system
/// account database, never from a path/uid supplied by the client.
public struct HelperFileScope: Sendable {
    public let userID: UInt32
    public let homePath: String
    public let applicationsPath: String
    public var quarantinePath: String { homePath + "/Library/Application Support/SuperCleaner/Quarantine" }
    public init(userID: UInt32, homePath: String, applicationsPath: String = "/Applications") throws {
        guard userID > 0, Self.validPath(homePath), Self.validPath(applicationsPath), homePath != applicationsPath else { throw HelperRejection.invalidPath }
        self.userID = userID; self.homePath = homePath; self.applicationsPath = applicationsPath
    }
    public static func forUser(_ userID: UInt32) throws -> Self {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var storage = [CChar](repeating: 0, count: 16_384)
        let (status, home) = storage.withUnsafeMutableBufferPointer { buffer -> (Int32, String?) in
            let status = getpwuid_r(userID, &record, buffer.baseAddress!, buffer.count, &result)
            return (status, result != nil ? record.pw_dir.map { String(cString: $0) } : nil)
        }
        guard status == 0, let home else { throw HelperRejection.invalidPath }
        return try .init(userID: userID, homePath: home)
    }
    static func validPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return path.hasPrefix("/") && path.count > 1 && path.utf8.count < 4096
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    func isApplication(_ path: String) -> Bool {
        guard Self.validPath(path), path.hasPrefix(applicationsPath + "/"), path.lowercased().hasSuffix(".app") else { return false }
        let relative = path.dropFirst(applicationsPath.count + 1).split(separator: "/")
        return relative.dropLast().allSatisfy { !$0.lowercased().hasSuffix(".app") }
    }
    func isQuarantineItem(_ path: String, planID: UUID? = nil) -> Bool {
        guard Self.validPath(path), path.hasPrefix(quarantinePath + "/"), path.lowercased().hasSuffix(".app") else { return false }
        let relative = path.dropFirst(quarantinePath.count + 1).split(separator: "/").map(String.init)
        guard relative.count == 2, let plan = UUID(uuidString: relative[0]), relative[1].count > 37,
              UUID(uuidString: String(relative[1].prefix(36))) != nil, relative[1].dropFirst(36).hasPrefix("-") else { return false }
        return planID == nil || planID == plan
    }
    func isQuarantinePlan(_ path: String, planID: UUID) -> Bool { path == quarantinePath + "/" + planID.uuidString }
}

/// fd-relative, no-follow filesystem operations. No shell, rm, launchctl,
/// arbitrary write, overwrite, recursive chmod/chown or generic system delete.
public struct HelperFileOperations: Sendable {
    public let scope: HelperFileScope
    private let maximumEntries: Int
    private let maximumDepth: Int
    private let timeout: TimeInterval
    public init(scope: HelperFileScope, maximumEntries: Int = 100_000, maximumDepth: Int = 64, timeout: TimeInterval = 20) {
        self.scope = scope; self.maximumEntries = max(1, min(maximumEntries, 100_000))
        self.maximumDepth = max(1, min(maximumDepth, 64)); self.timeout = max(0.05, min(timeout, 20))
    }

    public func inspect(_ path: String) throws -> FileIdentity {
        guard scope.isApplication(path) || scope.isQuarantineItem(path) else { throw HelperRejection.invalidPath }
        let parent = try openParent(path)
        defer { close(parent) }
        return try identity(parent: parent, name: basename(path))
    }

    public func perform(_ operation: HelperOperation, token: CapabilityToken) throws -> FileIdentity? {
        guard token.expiresAt > Date() else { throw HelperRejection.expired }
        let source = operation.sourcePath
        guard HelperFileScope.validPath(source) else { throw HelperRejection.invalidPath }
        switch operation {
        case .inspect:
            return try inspect(source)
        case let .moveToQuarantine(_, destination):
            guard scope.isApplication(source), scope.isQuarantineItem(destination, planID: token.planID) else { throw HelperRejection.invalidPath }
            try move(source, destination: destination, expected: token.identity, expiresAt: token.expiresAt)
        case let .restoreFromQuarantine(_, destination):
            guard scope.isQuarantineItem(source, planID: token.planID), scope.isApplication(destination) else { throw HelperRejection.invalidPath }
            try move(source, destination: destination, expected: token.identity, expiresAt: token.expiresAt)
        case .purgeOwnedQuarantine:
            guard scope.isQuarantineItem(source, planID: token.planID) else { throw HelperRejection.invalidPath }
            let parent = try openParent(source)
            defer { close(parent) }
            guard try identity(parent: parent, name: basename(source)) == token.identity, token.identity.kind == .directory else { throw HelperRejection.identityMismatch }
            guard try identity(fd: parent).device == token.identity.device else { throw HelperRejection.invalidPath }
            let directory = try openChild(parent: parent, name: basename(source))
            defer { close(directory) }
            guard try identity(fd: directory) == token.identity else { throw HelperRejection.identityMismatch }
            var remaining = maximumEntries
            let deadline = min(token.expiresAt, Date().addingTimeInterval(timeout))
            try purgeContents(directory, device: token.identity.device, depth: 0, remaining: &remaining, deadline: deadline)
            try verifyEntry(parent: parent, name: basename(source), matches: token.identity)
            guard Date() < deadline else { throw HelperRejection.expired }
            guard unlinkat(parent, basename(source), AT_REMOVEDIR) == 0 else { throw posixFailure() }
        case .removeOwnedQuarantine:
            guard scope.isQuarantinePlan(source, planID: token.planID) else { throw HelperRejection.invalidPath }
            let parent = try openParent(source)
            defer { close(parent) }
            guard try identity(parent: parent, name: basename(source)) == token.identity else { throw HelperRejection.identityMismatch }
            guard unlinkat(parent, basename(source), AT_REMOVEDIR) == 0 else { throw posixFailure() }
        case .unloadVerifiedService:
            throw HelperRejection.unsupported
        }
        return nil
    }

    private func move(_ source: String, destination: String, expected: FileIdentity, expiresAt: Date) throws {
        guard expected.kind == .directory else { throw HelperRejection.invalidPath }
        let sourceParent = try openParent(source)
        defer { close(sourceParent) }
        let destinationParent = try openParent(destination)
        defer { close(destinationParent) }
        guard try identity(parent: sourceParent, name: basename(source)) == expected else { throw HelperRejection.identityMismatch }
        guard Date() < expiresAt else { throw HelperRejection.expired }
        guard renameatx_np(sourceParent, basename(source), destinationParent, basename(destination), UInt32(RENAME_EXCL)) == 0 else { throw posixFailure() }
        guard (try? identity(parent: destinationParent, name: basename(destination))) == expected else {
            // A racing replacement is never silently accepted. Roll back only if
            // the original slot is still empty; do not overwrite either entry.
            _ = renameatx_np(destinationParent, basename(destination), sourceParent, basename(source), UInt32(RENAME_EXCL))
            throw HelperRejection.identityMismatch
        }
    }

    private func openParent(_ path: String) throws -> Int32 {
        guard HelperFileScope.validPath(path) else { throw HelperRejection.invalidPath }
        let parent = String(path.prefix(upTo: path.lastIndex(of: "/")!))
        let fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw posixFailure() }
        var current = fd
        do {
            var walked = ""
            for component in parent.split(separator: "/") {
                let next = try openChild(parent: current, name: String(component))
                close(current); current = next
                walked += "/" + component
                var facts = stat()
                guard fstat(current, &facts) == 0 else { throw posixFailure() }
                var volume = statfs()
                guard fstatfs(current, &volume) == 0, volume.f_flags & UInt32(MNT_LOCAL) != 0 else { throw HelperRejection.invalidPath }
                if walked == scope.homePath || walked.hasPrefix(scope.homePath + "/") {
                    guard facts.st_uid == scope.userID else { throw HelperRejection.invalidPath }
                }
                if walked == scope.applicationsPath || walked.hasPrefix(scope.applicationsPath + "/") {
                    guard (facts.st_uid == 0 || facts.st_uid == scope.userID), facts.st_mode & mode_t(S_IWOTH) == 0 else { throw HelperRejection.invalidPath }
                }
            }
            return current
        } catch { close(current); throw error }
    }

    private func openChild(parent: Int32, name: String) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posixFailure() }
        return fd
    }
    private func basename(_ path: String) -> String { String(path.split(separator: "/").last!) }
    private func identity(parent: Int32, name: String) throws -> FileIdentity {
        var facts = stat()
        guard fstatat(parent, name, &facts, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixFailure() }
        return identity(facts)
    }
    private func identity(fd: Int32) throws -> FileIdentity {
        var facts = stat()
        guard fstat(fd, &facts) == 0 else { throw posixFailure() }
        return identity(facts)
    }
    private func identity(_ facts: stat) -> FileIdentity {
        let kind: FileIdentity.Kind
        switch facts.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFDIR): kind = .directory
        case mode_t(S_IFREG): kind = .file
        case mode_t(S_IFLNK): kind = .symbolicLink
        default: kind = .other
        }
        return FileIdentity(device: UInt64(UInt32(bitPattern: facts.st_dev)), inode: UInt64(facts.st_ino), size: UInt64(max(0, facts.st_size)), modificationTime: Int64(facts.st_mtimespec.tv_sec), kind: kind)
    }
    private func verifyEntry(parent: Int32, name: String, matches expected: FileIdentity) throws {
        let current = try identity(parent: parent, name: name)
        guard current.device == expected.device, current.inode == expected.inode, current.kind == expected.kind else { throw HelperRejection.identityMismatch }
    }
    private func purgeContents(_ directory: Int32, device: UInt64, depth: Int, remaining: inout Int, deadline: Date) throws {
        guard depth < maximumDepth, Date() < deadline else { throw HelperRejection.executionFailed }
        let duplicate = dup(directory)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else { if duplicate >= 0 { close(duplicate) }; throw posixFailure() }
        defer { closedir(stream) }
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard remaining > 0, Date() < deadline else { throw HelperRejection.executionFailed }
            remaining -= 1
            let expected = try identity(parent: directory, name: name)
            guard expected.device == device else { throw HelperRejection.invalidPath }
            if expected.kind == .directory {
                let child = try openChild(parent: directory, name: name)
                defer { close(child) }
                guard try identity(fd: child) == expected else { throw HelperRejection.identityMismatch }
                try purgeContents(child, device: device, depth: depth + 1, remaining: &remaining, deadline: deadline)
                try verifyEntry(parent: directory, name: name, matches: expected)
                guard Date() < deadline else { throw HelperRejection.expired }
                guard unlinkat(directory, name, AT_REMOVEDIR) == 0 else { throw posixFailure() }
            } else {
                // unlinkat removes a link itself, never its target.
                try verifyEntry(parent: directory, name: name, matches: expected)
                guard Date() < deadline else { throw HelperRejection.expired }
                guard unlinkat(directory, name, 0) == 0 else { throw posixFailure() }
            }
            errno = 0
        }
        guard errno == 0 else { throw posixFailure() }
    }
    private func posixFailure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

public actor HelperRequestHandler {
    private let authorizer: HelperAuthorizer
    private let authorizationCheck: @Sendable (Data?) -> Bool
    public init(authorizer: HelperAuthorizer, authorizationCheck: @escaping @Sendable (Data?) -> Bool = HelperAuthorizationSession.validateExternalForm) {
        self.authorizer = authorizer; self.authorizationCheck = authorizationCheck
    }
    public func handle(_ data: Data, scope: HelperFileScope) async -> HelperResponse {
        guard data.count <= 65_536, let request = try? JSONDecoder().decode(HelperRequest.self, from: data) else { return .init(authorization: .rejected(.unsupported)) }
        guard request.token.callerUserID == scope.userID else { return .init(authorization: .rejected(.callerMismatch)) }
        let operations = HelperFileOperations(scope: scope)
        do {
            let identity: FileIdentity
            if case .removeOwnedQuarantine = request.operation {
                return .init(authorization: .rejected(.unsupported)) // no caller can remove recovery containers
            } else { identity = try operations.inspect(request.operation.sourcePath) }
            let decision = await authorizer.authorize(operation: request.operation, token: request.token, currentIdentity: identity)
            guard decision == .accepted else { return .init(authorization: decision) }
            if case .inspect = request.operation { } else {
                guard authorizationCheck(request.authorizationExternalForm) else { return .init(authorization: .rejected(.authorizationRequired)) }
            }
            return .init(authorization: .accepted, identity: try operations.perform(request.operation, token: request.token))
        } catch let rejection as HelperRejection { return .init(authorization: .rejected(rejection)) }
        catch { return .init(authorization: .rejected(.executionFailed), message: "受限文件操作未完成；请检查恢复记录") }
    }
}
