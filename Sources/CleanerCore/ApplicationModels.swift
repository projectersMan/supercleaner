import Foundation

public struct InstalledApplication: Identifiable, Codable, Hashable, Sendable {
    public var id: URL { bundleURL }
    public let bundleURL: URL
    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    public let isRunning: Bool
    public let isSystem: Bool
    public let teamIdentifier: String?
    public let applicationGroups: [String]?
    public let associatedBundleIdentifiers: [String]?
    public let applicationGroupsComplete: Bool?

    public init(bundleURL: URL, bundleIdentifier: String, name: String, version: String?, isRunning: Bool, isSystem: Bool, teamIdentifier: String? = nil, applicationGroups: [String]? = nil, associatedBundleIdentifiers: [String]? = nil, applicationGroupsComplete: Bool? = nil) {
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
        self.applicationGroupsComplete = applicationGroupsComplete ?? (applicationGroups != nil)
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.isRunning = isRunning
        self.isSystem = isSystem
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }

    public func withRunningState(_ isRunning: Bool) -> Self {
        guard self.isRunning != isRunning else { return self }
        return Self(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier, name: name, version: version,
            isRunning: isRunning, isSystem: isSystem, teamIdentifier: teamIdentifier,
            applicationGroups: applicationGroups, associatedBundleIdentifiers: associatedBundleIdentifiers,
            applicationGroupsComplete: applicationGroupsComplete)
    }

    public var isUninstallProtected: Bool { isSystem }

    public var uninstallProtectionReason: String? {
        if isSystem { return L10n.text("这是由 macOS 管理的系统应用，无论是否运行都不会提供卸载操作。") }
        return nil
    }
}

public struct ApplicationBundleMetadata: Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    public let teamIdentifier: String?
    public let applicationGroups: [String]?
    public let associatedBundleIdentifiers: [String]?
    public let applicationGroupsComplete: Bool?

    public init(bundleIdentifier: String, name: String, version: String?, teamIdentifier: String? = nil, applicationGroups: [String]? = nil, associatedBundleIdentifiers: [String]? = nil, applicationGroupsComplete: Bool? = nil) {
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
        self.applicationGroupsComplete = applicationGroupsComplete ?? (applicationGroups != nil)
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }
}


public struct ApplicationInventory: Codable, Hashable, Sendable {
    public let applications: [InstalledApplication]
    public let coverage: CoverageSummary
    public let scannedAt: Date

    public init(applications: [InstalledApplication], coverage: CoverageSummary, scannedAt: Date) {
        self.applications = applications
        self.coverage = coverage
        self.scannedAt = scannedAt
    }
}


public struct ApplicationAssociation: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case cache
        case applicationSupport
        case preference
        case savedState
        case launchAgent
        case container
        case sharedContainer
        case log
        case webData
        case launchDaemon
        case privilegedHelper
        case diagnosticReport
        case applicationScripts, cookies, plugin, installationReceipt, temporary, searchIndex
    }

    public enum RemovalPolicy: String, Codable, Hashable, Sendable { case recoverable, referenceOnly }
    public let removalPolicy: RemovalPolicy?

    public enum OwnershipBasis: String, Codable, Hashable, Sendable {
        case bundleDataDeclaration, diagnosticReportIdentity, crashReporterRecord, diagnosticNameOnly
        case bundleIdentifier, applicationGroup, displayName, serviceDefinition, compatibilityHint
    }
    public let ownershipBasis: OwnershipBasis?
    public let declarationSource: String?
    public var id: URL { url }
    public let url: URL
    public let kind: Kind
    public let ownershipEvidence: String
    public let containsUserData: Bool
    public let isShared: Bool
    public let risk: RiskLevel
    public let ownerBundleURLs: [URL]?
    public let references: [ApplicationReferenceLocation]?
    public let isSystemResource: Bool?

    /// Ownership matching still consumes canonical evidence. Translate only its display copy,
    /// so changing language or wording cannot change deletion eligibility.
    public var localizedOwnershipEvidence: String {
        let separator = L10n.language == .english ? "; " : "；"
        return ownershipEvidence.components(separatedBy: "；").map { L10n.text($0) }.joined(separator: separator)
    }

    public init(url: URL, kind: Kind, ownershipEvidence: String, containsUserData: Bool, isShared: Bool, risk: RiskLevel, ownerBundleURLs: [URL]? = nil, references: [ApplicationReferenceLocation]? = nil, isSystemResource: Bool = false, ownershipBasis: OwnershipBasis? = nil, declarationSource: String? = nil, removalPolicy: RemovalPolicy? = nil) {
        self.removalPolicy = removalPolicy
        self.ownershipBasis = ownershipBasis
        self.declarationSource = declarationSource
        self.url = url
        self.kind = kind
        self.ownershipEvidence = ownershipEvidence
        self.containsUserData = containsUserData
        self.isShared = isShared
        self.risk = risk
        self.ownerBundleURLs = ownerBundleURLs
        self.references = references
        self.isSystemResource = isSystemResource
    }
}

public struct ApplicationAssociationIndex: Codable, Hashable, Sendable {
    public let associations: [URL: [ApplicationAssociation]]
    public let coverage: CoverageSummary
    public let ownershipGraph: ApplicationOwnershipGraph?

    public init(
        associations: [URL: [ApplicationAssociation]],
        coverage: CoverageSummary,
        ownershipGraph: ApplicationOwnershipGraph? = nil
    ) {
        self.associations = associations
        self.coverage = coverage
        self.ownershipGraph = ownershipGraph
    }
}

public struct UninstallItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public let containsUserData: Bool
    public let isShared: Bool

    public init(candidate: CleanupCandidate, containsUserData: Bool, isShared: Bool) {
        self.candidate = candidate
        self.containsUserData = containsUserData
        self.isShared = isShared
    }
}

public struct UninstallPlan: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let application: InstalledApplication
    public let items: [UninstallItem]

    public init(id: UUID = UUID(), application: InstalledApplication, items: [UninstallItem]) {
        self.id = id
        self.application = application
        self.items = items
    }

    public var selectableItemIDs: Set<UUID> {
        guard !application.isUninstallProtected else { return [] }
        return Set(items.lazy.filter { item in
            item.candidate.risk.isSelectable && !item.candidate.isActive && !item.isShared
        }.map(\.id))
    }
}
