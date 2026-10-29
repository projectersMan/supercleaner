import Foundation

public protocol Scanner: Sendable {
    var id: String { get }
    var category: CleanupCategory { get }
    func scan(context: ScanContext) async throws -> [CleanupCandidate]
    func scanResult(context: ScanContext) async throws -> ScannerResult
}

public struct ScannerResult: Sendable {
    public var candidates: [CleanupCandidate]
    public var failures: [ScanFailure]
    public init(candidates: [CleanupCandidate] = [], failures: [ScanFailure] = []) {
        self.candidates = candidates; self.failures = failures
    }
}

public extension Scanner {
    func scanResult(context: ScanContext) async throws -> ScannerResult {
        ScannerResult(candidates: try await scan(context: context))
    }
}

public struct ScanContext: Sendable {
    public let homeDirectory: URL
    public let fileSystem: any FileSystemAccess
    public let pathPolicy: PathPolicy
    public let now: Date
    public let activePaths: Set<URL>
    public let protectionPolicy: ProtectionPolicy
    public let runningBundleIdentifiers: Set<String>
    public let activeProcessNames: Set<String>
    public let activityProbeAvailable: Bool
    public let projectActivityAvailable: Bool

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any FileSystemAccess = LocalFileSystem(),
        pathPolicy: PathPolicy? = nil,
        now: Date = Date(),
        activePaths: Set<URL> = [],
        protectionPolicy: ProtectionPolicy? = nil,
        runningBundleIdentifiers: Set<String> = [],
        activeProcessNames: Set<String> = [],
        activityProbeAvailable: Bool = true,
        projectActivityAvailable: Bool = true
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.fileSystem = fileSystem
        self.pathPolicy = pathPolicy ?? PathPolicy(homeDirectory: homeDirectory)
        self.now = now
        self.activePaths = Set(activePaths.map(\.standardizedFileURL))
        self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.activeProcessNames = activeProcessNames
        self.activityProbeAvailable = activityProbeAvailable
        self.projectActivityAvailable = projectActivityAvailable
    }

    public func isActive(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return activePaths.contains { active in
            let activePath = active.path
            return candidate == activePath || candidate.hasPrefix(activePath + "/") || activePath.hasPrefix(candidate + "/")
        }
    }
}

public struct ScanProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let scannerID: String?

    public init(completed: Int, total: Int, scannerID: String? = nil) {
        self.completed = completed
        self.total = total
        self.scannerID = scannerID
    }
}

public struct ScanFailure: Codable, Hashable, Sendable {
    public let scannerID: String
    public enum Reason: String, Codable, Sendable { case budget, access, changed, cancelled }
    public let message: String
    public let path: URL?
    public let reason: Reason?

    public init(scannerID: String, message: String, path: URL? = nil, reason: Reason? = nil) {
        self.scannerID = scannerID; self.message = message; self.path = path; self.reason = reason
    }

    public static func from(error: Error, scannerID: String, path: URL? = nil) -> Self {
        let reason: Reason
        switch error {
        case is CancellationError: reason = .cancelled
        case FileSystemError.missing: reason = .changed
        case RuleScanError.budgetExceeded: reason = .budget
        default: reason = .access
        }
        let message: String
        switch reason {
        case .budget: message = L10n.text("达到扫描数量上限")
        case .access: message = L10n.text("目录无法完整检查")
        case .changed: message = L10n.text("位置已发生变化")
        case .cancelled: message = L10n.text("扫描已取消")
        }
        return Self(scannerID: scannerID, message: message, path: path, reason: reason)
    }

    public var limitation: ScanLimitation {
        ScanLimitation(title: message, path: path,
            impact: L10n.text("已保留完成验证的项目；未完整检查的内容不会自动清理"),
            recovery: L10n.text("检查目录访问权限，关闭相关应用后重新扫描"), reason: reason)
    }
}

public struct ScanReport: Sendable {
    public let candidates: [CleanupCandidate]
    public let failures: [ScanFailure]
    public let startedAt: Date
    public let completedAt: Date

    public var coverage: CoverageSummary {
        CoverageSummary(scannedRoots: candidates.map(\.url), unavailableRoots: failures.compactMap(\.path),
            budgetLimitedModules: failures.contains { $0.reason == .budget } ? [.general] : [])
    }

    public init(candidates: [CleanupCandidate], failures: [ScanFailure], startedAt: Date, completedAt: Date) {
        self.candidates = candidates
        self.failures = failures
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

private enum ScannerOutcome: Sendable {
    case success(ScannerResult)
    case failure(ScanFailure)
}

public actor ScanCoordinator {
    public let maxConcurrentScanners: Int

    public init(maxConcurrentScanners: Int = 3) {
        self.maxConcurrentScanners = max(1, maxConcurrentScanners)
    }

    public func scan(using scanners: [any Scanner], context: ScanContext) async -> ScanReport {
        let startedAt = Date()
        var candidates: [CleanupCandidate] = []
        var failures: [ScanFailure] = context.protectionPolicy.isAvailable ? [] : [
            ScanFailure(scannerID: "protection-policy", message: L10n.text("保护清单无法读取；所有删除均被阻止"))
        ]

        for batchStart in stride(from: 0, to: scanners.count, by: maxConcurrentScanners) {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + maxConcurrentScanners, scanners.count)
            let batch = Array(scanners[batchStart..<batchEnd])
            await withTaskGroup(of: ScannerOutcome.self) { group in
                for scanner in batch {
                    group.addTask {
                        do {
                            return .success(try await scanner.scanResult(context: context))
                        } catch {
                            return .failure(ScanFailure.from(error: error, scannerID: scanner.id))
                        }
                    }
                }

                for await outcome in group {
                    switch outcome {
                    case let .success(result):
                        candidates.append(contentsOf: result.candidates.map(context.protectionPolicy.applying))
                        failures.append(contentsOf: result.failures)
                    case let .failure(failure): failures.append(failure)
                    }
                }
            }
        }

        candidates.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        failures.sort { $0.scannerID < $1.scannerID }
        return ScanReport(candidates: candidates, failures: failures, startedAt: startedAt, completedAt: Date())
    }
}
