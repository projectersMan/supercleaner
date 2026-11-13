import Foundation

/// A denied operation is paused before it has a final result. Retrying always
/// returns through the executor's live safety checks, within the original plan.
public struct UninstallPermissionRequest: Identifiable, Sendable, Equatable {
    public enum Decision: Sendable { case retry, stop }
    public enum Resource: Sendable, Equatable { case applicationBundle, applicationData, installationReceipts }
    public enum Cause: Sendable, Equatable { case privacyOrSystemPolicy, filePermissions, administratorAuthorization }
    public let id: UUID
    public let url: URL
    public let resource: Resource
    public let cause: Cause
    public var isApplicationBundle: Bool { resource == .applicationBundle }
    public let attempt: Int

    public init(id: UUID = UUID(), url: URL, resource: Resource, cause: Cause = .privacyOrSystemPolicy, attempt: Int) {
        self.id = id
        self.url = url
        self.resource = resource
        self.cause = cause
        self.attempt = attempt
    }

    public var requiresAdministrator: Bool {
        resource == .installationReceipts || cause == .filePermissions || cause == .administratorAuthorization
    }

    public var supportsPrivilegedHelper: Bool {
        switch resource {
        case .applicationBundle: url.standardizedFileURL.path.hasPrefix("/Applications/")
        case .installationReceipts: true
        case .applicationData: false
        }
    }

    public var settingsURL: URL? {
        guard !requiresAdministrator else { return nil }
        return isApplicationBundle ? PermissionStatusService.appManagementSettingsURL
            : PermissionStatusService.fullDiskAccessSettingsURL
    }

    static func isPermissionDenied(_ error: any Error) -> Bool {
        permissionCause(for: error) != nil
    }

    static func permissionCause(for error: any Error) -> Cause? {
        if let helper = error as? HelperClientError {
            switch helper {
            case .notAuthorized, .rejected(.authorizationRequired): return .administratorAuthorization
            default: break
            }
        }
        // Foundation wraps EACCES and EPERM in the same Cocoa permission error.
        // Inspect the underlying errno before choosing the recovery instructions.
        var cocoaPermissionError = false
        var failure = error as NSError
        for _ in 0..<8 {
            if failure.domain == NSCocoaErrorDomain,
               [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(failure.code) { cocoaPermissionError = true }
            if failure.domain == NSPOSIXErrorDomain {
                if failure.code == 13 { return .filePermissions }
                if failure.code == 1 { return .privacyOrSystemPolicy }
                return nil
            }
            guard let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            failure = underlying
        }
        return cocoaPermissionError ? .privacyOrSystemPolicy : nil
    }
}
