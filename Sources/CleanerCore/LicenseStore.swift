import CryptoKit
import Foundation

public enum CommercialFeature: String, Codable, Hashable, Sendable, CaseIterable {
    case standardScan, agentScan, newCleanup
    case history, restore, removeHelper, exportReceipts

    public var isSafetyRight: Bool {
        [.history, .restore, .removeHelper, .exportReceipts].contains(self)
    }
}

public enum LicenseTier: String, Codable, Hashable, Sendable { case trial, paid }

public struct LicenseClaims: Codable, Hashable, Sendable {
    public let licenseID: UUID
    public let tier: LicenseTier
    public let issuedAt: Date
    public let expiresAt: Date?
    public let capabilities: Set<CommercialFeature>
    public init(licenseID: UUID, tier: LicenseTier, issuedAt: Date, expiresAt: Date?, capabilities: Set<CommercialFeature>) {
        self.licenseID = licenseID; self.tier = tier; self.issuedAt = issuedAt; self.expiresAt = expiresAt; self.capabilities = capabilities
    }
}

public struct SignedLicense: Codable, Hashable, Sendable {
    public let claimsData: Data
    public let signature: Data
    public init(claimsData: Data, signature: Data) { self.claimsData = claimsData; self.signature = signature }
}

public struct LicenseStore: Sendable {
    private let claims: LicenseClaims?

    public init(publicKey: Data, signedLicense: SignedLicense?) {
        guard let signedLicense,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signedLicense.signature, for: signedLicense.claimsData),
              let decoded = try? JSONDecoder().decode(LicenseClaims.self, from: signedLicense.claimsData)
        else { claims = nil; return }
        claims = decoded
    }

    public func isAllowed(_ feature: CommercialFeature, now: Date = Date()) -> Bool {
        if feature.isSafetyRight { return true }
        guard let claims, claims.issuedAt <= now, claims.expiresAt.map({ $0 > now }) ?? true else { return false }
        return claims.capabilities.contains(feature)
    }
}
