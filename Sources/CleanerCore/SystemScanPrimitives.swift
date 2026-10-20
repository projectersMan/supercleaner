import Foundation

public enum ScanModuleID: String, Codable, CaseIterable, Hashable, Sendable {
    case general
    case applications
    case largeFiles
    case agentEnvironment
}

public enum ScanModuleState: String, Codable, Hashable, Sendable {
    case waiting
    case scanning
    case completed
    case limited
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .waiting, .scanning: false
        case .completed, .limited, .failed, .cancelled: true
        }
    }
}

public struct ScanModuleStatus: Codable, Hashable, Sendable {
    public let module: ScanModuleID
    public let state: ScanModuleState
    public let startedAt: Date?
    public let completedAt: Date?
    public let message: String?
    public let limitations: [ScanLimitation]

    public init(
        module: ScanModuleID,
        state: ScanModuleState,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        message: String? = nil,
        limitations: [ScanLimitation] = []
    ) {
        self.module = module
        self.state = state
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.message = message
        self.limitations = limitations
    }
}

public struct ScanLimitation: Identifiable, Codable, Hashable, Sendable {
    public var id: String { [title, path?.path, impact].compactMap { $0 }.joined(separator: "|") }
    public let title: String
    public let path: URL?
    public let impact: String
    public let recovery: String

    public init(title: String, path: URL? = nil, impact: String, recovery: String) {
        self.title = title
        self.path = path?.standardizedFileURL
        self.impact = impact
        self.recovery = recovery
    }
}

public struct ScanGenerationMetadata: Codable, Hashable, Sendable {
    public let generationID: UUID
    public let startedAt: Date
    public let completedAt: Date
    public let rulesetVersion: String

    public init(
        generationID: UUID = UUID(),
        startedAt: Date,
        completedAt: Date,
        rulesetVersion: String
    ) {
        self.generationID = generationID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.rulesetVersion = rulesetVersion
    }
}

public struct CoverageSummary: Codable, Hashable, Sendable {
    public let scannedRoots: [URL]
    public let unavailableRoots: [URL]
    public let budgetLimitedModules: Set<ScanModuleID>

    public init(
        scannedRoots: [URL] = [],
        unavailableRoots: [URL] = [],
        budgetLimitedModules: Set<ScanModuleID> = []
    ) {
        self.scannedRoots = Self.normalized(scannedRoots)
        self.unavailableRoots = Self.normalized(unavailableRoots)
        self.budgetLimitedModules = budgetLimitedModules
    }

    private static func normalized(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
