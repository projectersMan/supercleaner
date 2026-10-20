import Darwin
import Foundation
import Security

public enum HelperClientError: Error, LocalizedError, Sendable {
    case unavailable, invalidSignature, invalidConfiguration, notAuthorized, timedOut, invalidResponse, rejected(HelperRejection)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Helper 未启用或连接已中断"
        case .invalidSignature: return "需要正式签名且同团队的主应用和 Helper"
        case .invalidConfiguration: return "Helper 发布身份配置无效"
        case .notAuthorized: return "此会话尚未获得操作授权，或授权已过期"
        case .timedOut: return "Helper 响应超时；请刷新恢复记录，不自动重试文件操作"
        case .invalidResponse: return "Helper 返回格式或协议版本无效"
        case let .rejected(reason): return "Helper 拒绝操作：\(reason.rawValue)"
        }
    }
}

public struct HelperSigningIdentity: Sendable, Equatable {
    public let applicationIdentifier: String
    public let teamIdentifier: String
    public var serviceName: String { applicationIdentifier + ".helper" }
    public var daemonPlistName: String { serviceName + ".plist" }
    public var callerRequirement: String { Self.requirement(identifier: applicationIdentifier, team: teamIdentifier) }
    public var helperRequirement: String { Self.requirement(identifier: serviceName, team: teamIdentifier) }

    public init(applicationIdentifier: String, teamIdentifier: String) throws {
        guard applicationIdentifier.split(separator: ".").count >= 3, applicationIdentifier.count < 200,
              !applicationIdentifier.hasPrefix("com.example."),
              applicationIdentifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }),
              teamIdentifier.count == 10, teamIdentifier.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
            throw HelperClientError.invalidConfiguration
        }
        self.applicationIdentifier = applicationIdentifier; self.teamIdentifier = teamIdentifier
    }

    private static func requirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and ! entitlement[\"com.apple.security.get-task-allow\"] exists"
    }

    public static func current(isHelper: Bool = false) throws -> HelperSigningIdentity {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String,
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String else { throw HelperClientError.invalidSignature }
        let appID: String
        if isHelper {
            guard identifier.hasSuffix(".helper") else { throw HelperClientError.invalidSignature }
            appID = String(identifier.dropLast(".helper".count))
        } else { appID = identifier }
        let identity = try HelperSigningIdentity(applicationIdentifier: appID, teamIdentifier: team)
        var requirement: SecRequirement?
        let expected = isHelper ? identity.helperRequirement : identity.callerRequirement
        guard SecRequirementCreateWithString(expected as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { throw HelperClientError.invalidSignature }
        return identity
    }
}

/// The opaque authorization is held only in memory, never logged, encoded into
/// receipts, put on disk or acquired by an automatic background operation.
public final class HelperAuthorizationSession: @unchecked Sendable {
    private let lock = NSLock()
    private var authorization: AuthorizationRef?
    private var validUntil: Date = .distantPast
    public init() {}
    deinit { revoke() }

    public func authorizeUserInteraction() throws {
        var created: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &created) == errAuthorizationSuccess, let created else { throw HelperClientError.notAuthorized }
        var granted = false
        defer { if !granted { AuthorizationFree(created, [.destroyRights]) } }
        let status = kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(created, &rights, nil, [.interactionAllowed, .extendRights], nil)
            }
        }
        guard status == errAuthorizationSuccess else { throw HelperClientError.notAuthorized }
        lock.withLock {
            if let authorization { AuthorizationFree(authorization, [.destroyRights]) }
            authorization = created; validUntil = Date().addingTimeInterval(300)
        }
        granted = true
    }

    public var isAuthorized: Bool {
        lock.withLock {
            if validUntil <= Date(), let authorization {
                AuthorizationFree(authorization, [.destroyRights]); self.authorization = nil
            }
            return authorization != nil && validUntil > Date()
        }
    }
    public func externalForm() throws -> Data {
        try lock.withLock {
            guard let authorization, validUntil > Date() else { throw HelperClientError.notAuthorized }
            var form = AuthorizationExternalForm()
            guard AuthorizationMakeExternalForm(authorization, &form) == errAuthorizationSuccess else { throw HelperClientError.notAuthorized }
            return withUnsafeBytes(of: &form) { Data($0) }
        }
    }
    public func revoke() {
        lock.withLock {
            if let authorization { AuthorizationFree(authorization, [.destroyRights]) }
            authorization = nil; validUntil = .distantPast
        }
    }

    public static func validateExternalForm(_ data: Data?) -> Bool {
        guard let data, data.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
        var form = AuthorizationExternalForm()
        _ = withUnsafeMutableBytes(of: &form) { data.copyBytes(to: $0) }
        var authorization: AuthorizationRef?
        guard AuthorizationCreateFromExternalForm(&form, &authorization) == errAuthorizationSuccess, let authorization else { return false }
        defer { AuthorizationFree(authorization, []) }
        return kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                // No UI or attempt to acquire new authority in a root daemon.
                return AuthorizationCopyRights(authorization, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
            }
        }
    }
}
