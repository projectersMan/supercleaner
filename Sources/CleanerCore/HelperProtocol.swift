import CryptoKit
import Foundation

public enum HelperOperation: Codable, Hashable, Sendable {
    case inspect(path: String)
    case moveToQuarantine(path: String, destination: String)
    case restoreFromQuarantine(path: String, destination: String)
    case purgeOwnedQuarantine(path: String)
    case removeOwnedQuarantine(path: String)
    case unloadVerifiedService(label: String, plistPath: String)

    public var sourcePath: String {
        switch self {
        case let .inspect(path), let .removeOwnedQuarantine(path), let .purgeOwnedQuarantine(path): path
        case let .moveToQuarantine(path, _), let .restoreFromQuarantine(path, _): path
        case let .unloadVerifiedService(_, plistPath): plistPath
        }
    }

    public var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CapabilityToken: Codable, Hashable, Sendable {
    public let id: UUID
    public let planID: UUID
    public let operationDigest: String
    public let expiresAt: Date
    public let nonce: UUID
    public let callerRequirement: String
    public let identity: FileIdentity
    public let callerUserID: UInt32?

    public init(id: UUID = UUID(), planID: UUID, operationDigest: String, expiresAt: Date, nonce: UUID = UUID(), callerRequirement: String, identity: FileIdentity, callerUserID: UInt32? = nil) {
        self.id = id
        self.planID = planID
        self.operationDigest = operationDigest
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.callerRequirement = callerRequirement
        self.identity = identity
        self.callerUserID = callerUserID
    }

    public static func issue(operation: HelperOperation, planID: UUID, identity: FileIdentity, callerRequirement: String, expiresAt: Date) -> CapabilityToken {
        CapabilityToken(planID: planID, operationDigest: operation.digest, expiresAt: expiresAt, callerRequirement: callerRequirement, identity: identity)
    }

    public static func issueForTesting(operation: HelperOperation, identity: FileIdentity, callerRequirement: String, expiresAt: Date) -> CapabilityToken {
        issue(operation: operation, planID: UUID(), identity: identity, callerRequirement: callerRequirement, expiresAt: expiresAt)
    }
}

public enum HelperRejection: String, Codable, Hashable, Sendable, Error {
    case expired
    case callerMismatch
    case operationMismatch
    case identityMismatch
    case replayedNonce
    case invalidPath
    case unsupported
    case executionFailed
    case authorizationRequired
    case rateLimited
}

public enum HelperAuthorization: Codable, Hashable, Sendable {
    case accepted
    case rejected(HelperRejection)
}

public actor HelperAuthorizer {
    private let expectedCallerRequirement: String
    private var consumedNonces: [UUID: Date] = [:]

    public init(expectedCallerRequirement: String) {
        self.expectedCallerRequirement = expectedCallerRequirement
    }

    public func authorize(operation: HelperOperation, token: CapabilityToken, currentIdentity: FileIdentity, now: Date = Date()) -> HelperAuthorization {
        guard token.expiresAt > now, token.expiresAt <= now.addingTimeInterval(120) else { return .rejected(.expired) }
        guard token.callerRequirement == expectedCallerRequirement else { return .rejected(.callerMismatch) }
        guard token.operationDigest == operation.digest else { return .rejected(.operationMismatch) }
        guard token.identity == currentIdentity else { return .rejected(.identityMismatch) }
        consumedNonces = consumedNonces.filter { $0.value > now }
        guard consumedNonces[token.nonce] == nil else { return .rejected(.replayedNonce) }
        guard consumedNonces.count < 10_000 else { return .rejected(.rateLimited) }
        consumedNonces[token.nonce] = token.expiresAt
        return .accepted
    }
}

public struct HelperRequest: Codable, Hashable, Sendable {
    public let operation: HelperOperation
    public let token: CapabilityToken
    public let authorizationExternalForm: Data?
    public init(operation: HelperOperation, token: CapabilityToken, authorizationExternalForm: Data? = nil) {
        self.operation = operation; self.token = token; self.authorizationExternalForm = authorizationExternalForm
    }
}

public struct HelperResponse: Codable, Hashable, Sendable {
    public let authorization: HelperAuthorization
    public let identity: FileIdentity?
    public let message: String?
    public init(authorization: HelperAuthorization, identity: FileIdentity? = nil, message: String? = nil) {
        self.authorization = authorization
        self.identity = identity
        self.message = message
    }
}

public protocol PrivilegedHelperClient: Sendable {
    func perform(_ request: HelperRequest) async throws -> HelperResponse
    func ping() async throws -> Int
}
public extension PrivilegedHelperClient {
    func ping() async throws -> Int { throw HelperClientError.unavailable }
}

@objc public protocol CleanerHelperXPCProtocol {
    func perform(requestData: Data, withReply reply: @escaping @Sendable (Data) -> Void)
    func ping(withReply reply: @escaping @Sendable (Int) -> Void)
}
