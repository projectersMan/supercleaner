import Foundation

public enum RiskLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case safe
    case review
    case blocked

    public var isSelectableByDefault: Bool { self == .safe }
    public var isSelectable: Bool { self != .blocked }
}

public enum CleanupCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case cache
    case log
    case temporaryFile
    case installerArtifact
    case developerCache
    case largeFile
    case application
    case applicationSupport
    case agentSkill
    case agentMCP
    case agentSession
    case agentSandbox
    case agentWorktree
    case agentModelCache
    case agentPackageCache
    case agentUnknown
    case credential
    case configuration
    case userKnowledge
}

public enum CandidateSource: String, Codable, Sendable, CaseIterable, Hashable {
    case general
    case historicalApplicationResidue
    case agentWorkspace
    case application
    case diskAnalysis
    case projectArtifacts
}

public struct Evidence: Codable, Hashable, Sendable {
    public let code: String
    public let summary: String
    public let details: String?

    public init(code: String, summary: String, details: String? = nil) {
        self.code = code
        self.summary = summary
        self.details = details
    }
}

public struct FileIdentity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case file
        case directory
        case symbolicLink
        case other
    }

    public let device: UInt64
    public let inode: UInt64
    public let size: UInt64
    public let modificationTime: Int64
    public let kind: Kind

    public init(device: UInt64, inode: UInt64, size: UInt64, modificationTime: Int64, kind: Kind) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modificationTime = modificationTime
        self.kind = kind
    }
}

public struct CleanupCandidate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let displayName: String
    public let category: CleanupCategory
    public let bytes: UInt64
    public let risk: RiskLevel
    public let evidence: [Evidence]
    public let identity: FileIdentity
    public let source: CandidateSource
    public let lastAccessDate: Date?
    public let isActive: Bool
    public let ruleID: String?
    public let defaultSelection: Bool?

    public init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        category: CleanupCategory,
        bytes: UInt64,
        risk: RiskLevel,
        evidence: [Evidence],
        identity: FileIdentity,
        source: CandidateSource,
        lastAccessDate: Date?,
        isActive: Bool,
        ruleID: String? = nil,
        defaultSelection: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.category = category
        self.bytes = bytes
        self.risk = risk
        self.evidence = evidence
        self.identity = identity
        self.source = source
        self.lastAccessDate = lastAccessDate
        self.isActive = isActive
        self.ruleID = ruleID
        self.defaultSelection = defaultSelection
    }

    public func replacing(risk: RiskLevel, evidence: [Evidence]) -> CleanupCandidate {
        CleanupCandidate(
            id: id, url: url, displayName: displayName, category: category, bytes: bytes,
            risk: risk, evidence: evidence, identity: identity, source: source,
            lastAccessDate: lastAccessDate, isActive: isActive,
            ruleID: ruleID, defaultSelection: defaultSelection
        )
    }
}

public struct PlanItem: Identifiable, Codable, Hashable, Sendable {
    public enum Action: String, Codable, Hashable, Sendable {
        case quarantine
        case trash
    }

    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public var isSelected: Bool
    public let action: Action
    public let evidenceDigest: String

    public init(candidate: CleanupCandidate, isSelected: Bool? = nil, action: Action = .quarantine, evidenceDigest: String = "") {
        self.candidate = candidate
        self.isSelected = candidate.risk.isSelectable && (isSelected ?? (candidate.defaultSelection ?? candidate.risk.isSelectableByDefault))
        self.action = action
        self.evidenceDigest = evidenceDigest
    }
}

public struct CleanupPlan: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public var items: [PlanItem]
    public let engineVersion: String
    public let ruleVersion: String
    public let operatingSystemVersion: String

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        expiresAt: Date,
        items: [PlanItem],
        engineVersion: String = "development",
        ruleVersion: String = "bundled",
        operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.items = items
        self.engineVersion = engineVersion
        self.ruleVersion = ruleVersion
        self.operatingSystemVersion = operatingSystemVersion
    }

    public var selectedItems: [PlanItem] { items.filter(\.isSelected) }
    public var blockedItems: [PlanItem] { items.filter { $0.candidate.risk == .blocked } }
    public var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.candidate.bytes } }
    public func isExpired(at date: Date = Date()) -> Bool { date >= expiresAt }
}

public enum OperationDisposition: String, Codable, Sendable, Hashable {
    case quarantined
    case trashed
    case permanentlyDeleted
    case unavailable
    case skipped
    case failed
    case restored
}

public enum OperationStatus: String, Codable, Sendable, Hashable {
    case succeeded
    case skippedIdentityChanged
    case skippedProtected
    case skippedActive
    case skippedCancelled
    case failed
    case restored
    case restoreConflict
    case sourceMissing
}

public struct OperationResult: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let candidateID: UUID
    public let originalURL: URL
    public let destinationURL: URL?
    public let disposition: OperationDisposition
    public let status: OperationStatus
    public let bytes: UInt64
    public let message: String?
    public let verificationNotBefore: Date?

    public init(
        id: UUID = UUID(),
        candidateID: UUID,
        originalURL: URL,
        destinationURL: URL? = nil,
        disposition: OperationDisposition,
        status: OperationStatus? = nil,
        bytes: UInt64,
        message: String? = nil,
        verificationNotBefore: Date? = nil
    ) {
        self.id = id
        self.candidateID = candidateID
        self.originalURL = originalURL
        self.destinationURL = destinationURL
        self.disposition = disposition
        self.status = status ?? (disposition == .failed || disposition == .skipped ? .failed : .succeeded)
        self.bytes = bytes
        self.message = message
        self.verificationNotBefore = verificationNotBefore
    }
}

public struct OperationReceipt: Identifiable, Codable, Hashable, Sendable {
    public enum OverallStatus: String, Codable, Hashable, Sendable {
        case completed
        case partial
        case rejected
        case failed
    }

    public let id: UUID
    public let planID: UUID
    public let startedAt: Date
    public let completedAt: Date
    public let results: [OperationResult]
    public let overallStatus: OverallStatus
    public let rejectionReason: String?

    public init(
        id: UUID = UUID(),
        planID: UUID,
        startedAt: Date,
        completedAt: Date,
        results: [OperationResult],
        overallStatus: OverallStatus = .completed,
        rejectionReason: String? = nil
    ) {
        self.id = id
        self.planID = planID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.results = results
        self.overallStatus = overallStatus
        self.rejectionReason = rejectionReason
    }

    public var recoveredBytes: UInt64 {
        results.filter { [.quarantined, .trashed, .permanentlyDeleted].contains($0.disposition) }
            .reduce(0) { $0 + $1.bytes }
    }

    public func applying(resolutionResults: [OperationResult]) -> OperationReceipt {
        let successfulResolutions = Dictionary(
            resolutionResults.compactMap { result -> (UUID, OperationResult)? in
                let resolved = result.disposition == .permanentlyDeleted
                    || result.disposition == .trashed
                    || result.disposition == .unavailable
                    || (result.disposition == .restored && [.restored, .restoreConflict].contains(result.status))
                return resolved ? (result.candidateID, result) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        let updatedResults = results.map { result in
            guard result.disposition == .quarantined else { return result }
            return successfulResolutions[result.candidateID] ?? result
        }
        return OperationReceipt(
            id: id,
            planID: planID,
            startedAt: startedAt,
            completedAt: completedAt,
            results: updatedResults,
            overallStatus: overallStatus,
            rejectionReason: rejectionReason
        )
    }
}

public struct RestoreReceipt: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sourceReceiptID: UUID
    public let completedAt: Date
    public let results: [OperationResult]

    public init(id: UUID = UUID(), sourceReceiptID: UUID, completedAt: Date, results: [OperationResult]) {
        self.id = id
        self.sourceReceiptID = sourceReceiptID
        self.completedAt = completedAt
        self.results = results
    }
}

public struct PurgeReceipt: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sourceReceiptID: UUID
    public let completedAt: Date
    public let results: [OperationResult]

    public init(id: UUID = UUID(), sourceReceiptID: UUID, completedAt: Date, results: [OperationResult]) {
        self.id = id
        self.sourceReceiptID = sourceReceiptID
        self.completedAt = completedAt
        self.results = results
    }
}
