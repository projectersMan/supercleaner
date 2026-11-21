import CryptoKit
import Foundation

public enum CommercialFeature: String, Codable, Hashable, Sendable, CaseIterable {
    case standardScan, agentScan, newCleanup
    case history, restore, removeHelper, exportReceipts

    public var isSafetyRight: Bool {
        [.history, .restore, .removeHelper, .exportReceipts].contains(self)
    }
}

public enum LicenseAuthorizationError: Error, LocalizedError, Equatable, Sendable {
    case invalidPublicKey, invalidSignature, invalidClaims, wrongProduct, wrongDevice
    case futureIssued, invalidLease, clockRollback, licenseRequired, offlineLeaseExpired
    case capabilityMissing(CommercialFeature)

    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey: L10n.text("授权验签公钥无效，请检查商业配置。")
        case .invalidSignature: L10n.text("授权签名无效，请重新联网激活。")
        case .invalidClaims: L10n.text("授权凭证内容无效，请重新联网激活。")
        case .wrongProduct: L10n.text("授权凭证不属于当前产品。")
        case .wrongDevice: L10n.text("授权凭证不属于当前设备，请在本机激活。")
        case .futureIssued: L10n.text("授权签发时间晚于当前时间，请校准系统时钟。")
        case .invalidLease: L10n.text("授权离线租约无效，请重新联网激活。")
        case .clockRollback: L10n.text("检测到系统时钟回拨，请校准时间后联网刷新授权。")
        case .licenseRequired: L10n.text("请购买并激活买断授权后使用此功能。")
        case .offlineLeaseExpired: L10n.text("离线授权租约已过期，请联网刷新；买断权益不会到期。")
        case .capabilityMissing: L10n.text("当前授权未包含此功能。")
        }
    }
}

/// The purchase is perpetual. Only this device's offline authorization lease expires.
/// Timestamps are Unix seconds, matching the service's signed JSON without date conversion.
public struct LicenseClaims: Codable, Hashable, Sendable {
    public let licenseID: UUID
    public let productID: String
    public let email: String
    public let deviceID: UUID
    public let issuedAt: Int64
    public let offlineValidUntil: Int64
    public let capabilities: Set<CommercialFeature>

    public init(licenseID: UUID, productID: String, email: String, deviceID: UUID,
                issuedAt: Int64, offlineValidUntil: Int64, capabilities: Set<CommercialFeature>) {
        self.licenseID = licenseID
        self.productID = productID
        self.email = email
        self.deviceID = deviceID
        self.issuedAt = issuedAt
        self.offlineValidUntil = offlineValidUntil
        self.capabilities = capabilities
    }
}

public struct SignedLicense: Codable, Hashable, Sendable {
    public let claimsData: Data
    public let signature: Data

    public init(claimsData: Data, signature: Data) {
        self.claimsData = claimsData
        self.signature = signature
    }
}

public struct LicenseStore: Sendable {
    public let claims: LicenseClaims?
    private let trustedTime: Date

    public init(publicKey: Data, signedLicense: SignedLicense?, productID: String,
                deviceID: UUID, now: Date, lastTrustedTime: Date?) throws {
        guard publicKey.count == 32, publicKey.contains(where: { $0 != 0 }) else {
            throw LicenseAuthorizationError.invalidPublicKey
        }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard !productID.isEmpty, productID == productID.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw LicenseAuthorizationError.wrongProduct
        }
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else {
            throw LicenseAuthorizationError.clockRollback
        }
        if let lastTrustedTime {
            guard lastTrustedTime.timeIntervalSince1970.isFinite, lastTrustedTime <= now else {
                throw LicenseAuthorizationError.clockRollback
            }
        }
        trustedTime = now
        guard let signedLicense else {
            claims = nil
            return
        }
        guard signedLicense.claimsData.count <= 65_536,
              signedLicense.signature.count == 64,
              key.isValidSignature(signedLicense.signature, for: signedLicense.claimsData) else {
            throw LicenseAuthorizationError.invalidSignature
        }
        // Never inspect or reserialize untrusted claims before verifying the original bytes.
        let decoded = try JSONDecoder().decode(LicenseClaims.self, from: signedLicense.claimsData)
        guard decoded.productID == productID else { throw LicenseAuthorizationError.wrongProduct }
        guard decoded.deviceID == deviceID else { throw LicenseAuthorizationError.wrongDevice }
        let emailParts = decoded.email.split(separator: "@", omittingEmptySubsequences: false)
        guard decoded.email.count <= 254, emailParts.count == 2, !emailParts[0].isEmpty, !emailParts[1].isEmpty,
              decoded.email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !decoded.capabilities.isEmpty,
              decoded.capabilities.isSubset(of: [.standardScan, .agentScan, .newCleanup]) else {
            throw LicenseAuthorizationError.invalidClaims
        }
        // 366 days is a protocol safety ceiling, not the deployment's business lease duration.
        // The service must explicitly configure its actual (shorter) offline duration.
        guard decoded.issuedAt > 0,
              decoded.offlineValidUntil > decoded.issuedAt,
              decoded.offlineValidUntil <= 9_007_199_254_740_991,
              decoded.offlineValidUntil - decoded.issuedAt <= 366 * 24 * 60 * 60 else {
            throw LicenseAuthorizationError.invalidLease
        }
        guard TimeInterval(decoded.issuedAt) <= now.timeIntervalSince1970 else {
            throw LicenseAuthorizationError.futureIssued
        }
        claims = decoded
    }

    public func require(_ feature: CommercialFeature, now: Date) throws {
        if let failure = denial(for: feature, now: now) { throw failure }
    }

    public func isAllowed(_ feature: CommercialFeature, now: Date) -> Bool {
        denial(for: feature, now: now) == nil
    }

    private func denial(for feature: CommercialFeature, now: Date) -> LicenseAuthorizationError? {
        if feature.isSafetyRight { return nil }
        guard let claims else { return .licenseRequired }
        guard now.timeIntervalSince1970.isFinite, now >= trustedTime else { return .clockRollback }
        guard TimeInterval(claims.issuedAt) <= now.timeIntervalSince1970 else { return .futureIssued }
        guard TimeInterval(claims.offlineValidUntil) > now.timeIntervalSince1970 else { return .offlineLeaseExpired }
        guard claims.capabilities.contains(feature) else { return .capabilityMissing(feature) }
        return nil
    }
}
