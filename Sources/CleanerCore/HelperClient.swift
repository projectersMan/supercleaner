import Darwin
import Foundation
import Security
import ServiceManagement

public final class XPCPrivilegedHelperClient: PrivilegedHelperClient, @unchecked Sendable {
    private let identity: HelperSigningIdentity
    public init(identity: HelperSigningIdentity) { self.identity = identity }
    public func ping() async throws -> Int {
        let connection = NSXPCConnection(machServiceName: identity.serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: CleanerHelperXPCProtocol.self)
        connection.setCodeSigningRequirement(identity.helperRequirement)
        let pending = XPCPendingReply<Int>(connection: connection)
        connection.invalidationHandler = { pending.finish(.failure(HelperClientError.unavailable)) }
        connection.interruptionHandler = { pending.finish(.failure(HelperClientError.unavailable)) }
        connection.resume()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.begin(continuation) else { return }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in pending.finish(.failure(HelperClientError.unavailable)) }) as? CleanerHelperXPCProtocol else {
                    pending.finish(.failure(HelperClientError.unavailable)); return
                }
                proxy.ping { version in
                    pending.finish(version == 2 ? .success(version) : .failure(HelperClientError.invalidResponse))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { pending.finish(.failure(HelperClientError.timedOut)) }
            }
        } onCancel: { pending.finish(.failure(CancellationError())) }
    }
    public func perform(_ request: HelperRequest) async throws -> HelperResponse {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(request)
        guard data.count <= 65_536 else { throw HelperClientError.invalidResponse }
        let connection = NSXPCConnection(machServiceName: identity.serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: CleanerHelperXPCProtocol.self)
        // Framework enforcement applies to every peer message and survives PID
        // reuse/exec. Do not replace this with a PID-only SecCode lookup.
        connection.setCodeSigningRequirement(identity.helperRequirement)
        let pending = XPCPendingReply<HelperResponse>(connection: connection)
        connection.invalidationHandler = { pending.finish(.failure(HelperClientError.unavailable)) }
        connection.interruptionHandler = { pending.finish(.failure(HelperClientError.unavailable)) }
        connection.resume()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.begin(continuation) else { return }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    pending.finish(.failure(HelperClientError.unavailable))
                }) as? CleanerHelperXPCProtocol else {
                    pending.finish(.failure(HelperClientError.unavailable)); return
                }
                guard pending.markSent() else { return }
                proxy.perform(requestData: data) { responseData in
                    guard responseData.count <= 65_536, let response = try? JSONDecoder().decode(HelperResponse.self, from: responseData) else {
                        pending.finish(.failure(HelperClientError.invalidResponse)); return
                    }
                    pending.finish(.success(response))
                }
                let deadline = min(150, max(1, request.token.expiresAt.timeIntervalSinceNow + 25))
                DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { pending.finish(.failure(HelperClientError.timedOut)) }
            }
        } onCancel: {
            if case .inspect = request.operation { pending.finish(.failure(CancellationError())) }
            else { pending.cancelUnsent() }
        }
    }
}

private final class XPCPendingReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection
    private var continuation: CheckedContinuation<Value, any Error>?
    private var outcome: Result<Value, any Error>?
    private var sent = false
    init(connection: NSXPCConnection) { self.connection = connection }
    func begin(_ continuation: CheckedContinuation<Value, any Error>) -> Bool {
        let completed = lock.withLock { () -> Result<Value, any Error>? in
            if let outcome { return outcome }
            self.continuation = continuation; return nil
        }
        if let completed { continuation.resume(with: completed) }
        return completed == nil
    }
    func markSent() -> Bool { lock.withLock { guard outcome == nil else { return false }; sent = true; return true } }
    func cancelUnsent() { complete(.failure(CancellationError()), onlyIfUnsent: true) }
    func finish(_ outcome: Result<Value, any Error>) { complete(outcome) }
    private func complete(_ outcome: Result<Value, any Error>, onlyIfUnsent: Bool = false) {
        let completed = lock.withLock { () -> (Bool, CheckedContinuation<Value, any Error>?) in
            guard self.outcome == nil else { return (false, nil) }
            guard !onlyIfUnsent || !sent else { return (false, nil) }
            self.outcome = outcome
            let pending = continuation; continuation = nil
            return (true, pending)
        }
        guard completed.0 else { return }
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        completed.1?.resume(with: outcome)
    }
}

public enum HelperRegistrationStatus: String, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unavailable
    public var title: String {
        switch self {
        case .notRegistered: L10n.text("未安装")
        case .enabled: L10n.text("系统已批准")
        case .requiresApproval: L10n.text("等待系统批准")
        case .notFound: L10n.text("未找到已打包 Helper")
        case .unavailable: L10n.text("当前构建不可启用")
        }
    }
}

@MainActor public final class HelperServiceManager {
    private let service: SMAppService
    private let bundle: Bundle
    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        service = .daemon(plistName: (bundle.bundleIdentifier ?? "com.example.SuperCleaner") + ".helper.plist")
    }
    public var status: HelperRegistrationStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return (try? HelperSigningIdentity.current()) == nil ? .unavailable : .notRegistered
        @unknown default: return .unavailable
        }
    }
    public func install() throws {
        let identity = try HelperSigningIdentity.current()
        guard bundle.bundleIdentifier == identity.applicationIdentifier,
              bundle.bundleURL.deletingLastPathComponent().path == "/Applications" else { throw HelperClientError.invalidConfiguration }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + identity.serviceName)
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(identity.helperRequirement as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { throw HelperClientError.invalidSignature }
        try service.register()
    }
    public func remove() async throws {
        if service.status == .notRegistered || service.status == .notFound { return }
        try await service.unregister()
    }
    public func reregisterAfterUpgrade() async throws {
        let wasRegistered = service.status == .enabled || service.status == .requiresApproval
        guard wasRegistered else { return }
        try await remove()
        try install()
    }
    public func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}

public protocol PrivilegedApplicationOperations: Sendable {
    func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) async throws -> Bool
    func restore(source: URL, destination: URL, planID: UUID) async throws -> Bool
    func purge(source: URL, planID: UUID) async throws -> Bool
}

public struct HelperMutationUncertain: Error, LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { L10n.text("Helper 操作结果待确认；保留日志，待在途请求过期后复验，不自动重试。") }
}

/// Explicit opt-in session. Returning false means no privileged operation was
/// attempted. A sent request which fails is never retried using another path.
public actor AuthorizedApplicationOperations: PrivilegedApplicationOperations {
    private let session: HelperAuthorizationSession
    private let registrationEnabled: @Sendable () async -> Bool
    private let client: (any PrivilegedHelperClient)?
    private let signingIdentity: HelperSigningIdentity?
    private let fileSystem: any FileSystemAccess
    private let userID: UInt32
    public init(session: HelperAuthorizationSession, registrationEnabled: @escaping @Sendable () async -> Bool, identity: HelperSigningIdentity?, client: (any PrivilegedHelperClient)? = nil, fileSystem: any FileSystemAccess = LocalFileSystem(), userID: UInt32 = getuid()) {
        self.session = session; self.registrationEnabled = registrationEnabled; signingIdentity = identity
        self.client = client ?? identity.map { XPCPrivilegedHelperClient(identity: $0) }
        self.fileSystem = fileSystem; self.userID = userID
    }
    public func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) async throws -> Bool {
        guard candidate.source == .application, candidate.category == .application, candidate.url.path.hasPrefix("/Applications/") else { return false }
        return try await perform(.moveToQuarantine(path: candidate.url.path, destination: destination.path), planID: planID, identity: candidate.identity)
    }
    public func restore(source: URL, destination: URL, planID: UUID) async throws -> Bool {
        guard source.pathExtension.lowercased() == "app", destination.path.hasPrefix("/Applications/") else { return false }
        return try await perform(.restoreFromQuarantine(path: source.path, destination: destination.path), planID: planID, identity: try await fileSystem.identity(at: source))
    }
    public func purge(source: URL, planID: UUID) async throws -> Bool {
        guard source.pathExtension.lowercased() == "app" else { return false }
        return try await perform(.purgeOwnedQuarantine(path: source.path), planID: planID, identity: try await fileSystem.identity(at: source))
    }
    private func perform(_ operation: HelperOperation, planID: UUID, identity: FileIdentity) async throws -> Bool {
        guard session.isAuthorized else { return false }
        guard await registrationEnabled(), let client, let signingIdentity else { throw HelperClientError.unavailable }
        let token = CapabilityToken(planID: planID, operationDigest: operation.digest, expiresAt: Date().addingTimeInterval(60), callerRequirement: signingIdentity.callerRequirement, identity: identity, callerUserID: userID)
        let externalForm = try session.externalForm()
        let response: HelperResponse
        do { response = try await client.perform(.init(operation: operation, token: token, authorizationExternalForm: externalForm)) }
        catch is CancellationError { throw CancellationError() }
        catch { throw HelperMutationUncertain() }
        guard response.authorization == .accepted else {
            if case let .rejected(reason) = response.authorization {
                if reason == .executionFailed || reason == .identityMismatch { throw HelperMutationUncertain() }
                throw HelperClientError.rejected(reason)
            }
            throw HelperClientError.invalidResponse
        }
        return true
    }
}
