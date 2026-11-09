import CleanerCore
import Darwin
import Foundation

/// Records read denials without changing scanner errors or cleanup eligibility.
actor ScanAccessTrackingFileSystem: FileSystemAccess {
    let base: any FileSystemAccess
    private(set) var deniedPaths = Set<URL>()

    init(base: any FileSystemAccess) { self.base = base }

    func identity(at url: URL) async throws -> FileIdentity {
        do { return try await base.identity(at: url) }
        catch { record(error, at: url); throw error }
    }

    func children(of url: URL) async throws -> [URL] {
        do { return try await base.children(of: url) }
        catch { record(error, at: url); throw error }
    }

    func readText(at url: URL, maximumBytes: Int) async throws -> String {
        do { return try await base.readText(at: url, maximumBytes: maximumBytes) }
        catch { record(error, at: url); throw error }
    }

    func readData(at url: URL, maximumBytes: Int) async throws -> Data {
        do { return try await base.readData(at: url, maximumBytes: maximumBytes) }
        catch { record(error, at: url); throw error }
    }

    func isReadable(_ url: URL) async -> Bool {
        let readable = await base.isReadable(url)
        if !readable, await base.fileExists(url) { deniedPaths.insert(url.standardizedFileURL) }
        return readable
    }

    func fileExists(_ url: URL) async -> Bool { await base.fileExists(url) }
    func isWritable(_ url: URL) async -> Bool { await base.isWritable(url) }
    func move(_ source: URL, to destination: URL) async throws { try await base.move(source, to: destination) }
    func createDirectory(_ url: URL) async throws { try await base.createDirectory(url) }
    func removeEmptyDirectory(_ url: URL) async throws { try await base.removeEmptyDirectory(url) }
    func trash(_ url: URL) async throws -> URL { try await base.trash(url) }

    private func record(_ error: any Error, at url: URL) {
        let failure = error as NSError
        if (failure.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(failure.code))
            || (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError) {
            deniedPaths.insert(url.standardizedFileURL)
        }
    }
}

struct ScanAccessPresentation {
    let deniedPaths: Set<URL>

    func skips(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return deniedPaths.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    func shows(_ limitation: ScanLimitation) -> Bool {
        if limitation.reason == .budget || limitation.reason == .cancelled || limitation.reason == .changed { return true }
        guard let path = limitation.path else { return true }
        return !skips(path)
    }

    func status(for result: SystemScanModuleResult) -> ScanModuleStatus {
        let original = result.status
        guard original.state == .limited, !deniedPaths.isEmpty else { return original }
        let limited: Bool
        switch result.payload {
        case let .general(report):
            limited = report.failures.contains { failure in
                failure.path == nil || failure.reason != .access || !skips(failure.path!)
            }
        case let .applications(inventory):
            let coverage = [inventory.applicationInventory.coverage, inventory.associationCoverage]
            limited = coverage.contains { !$0.budgetLimitedModules.isEmpty || $0.unavailableRoots.contains { !skips($0) } }
                || inventory.analyses.contains { analysis in
                    guard [.limited, .unavailable].contains(analysis.state) else { return false }
                    return analysis.limitations.isEmpty || analysis.limitations.contains(where: shows)
                }
        case let .largeFiles(tree, _):
            limited = tree.coverage.unavailableRoots.isEmpty || !tree.coverage.budgetLimitedModules.isEmpty
                || tree.coverage.unavailableRoots.contains { !skips($0) }
                || original.limitations.contains(where: shows)
        case let .agentEnvironment(inventory):
            limited = inventory.reachedBudget || inventory.coverage.unavailableRoots.contains { !skips($0) }
                || inventory.limitations.contains(where: shows)
        }
        return ScanModuleStatus(module: original.module, state: limited ? .limited : .completed,
            startedAt: original.startedAt, completedAt: original.completedAt,
            message: limited ? original.message : nil, limitations: original.limitations.filter(shows))
    }
}
