import Foundation

/// Signed device proof for new privileged cleanup. Recovery stays available.
public struct CommercialAuthorization: Codable, Hashable, Sendable {
    public let license: SignedLicense
    public let deviceID: UUID

    public init(license: SignedLicense, deviceID: UUID) {
        self.license = license
        self.deviceID = deviceID
    }
}
