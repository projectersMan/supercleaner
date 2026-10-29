import Foundation

public struct ApplicationRuntimeObservation: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case sampled, unavailable, cancelled }
    public let directories: [URL]
    public let sampleCount: Int
    public let state: State
    public let observedAt: Date

    public init(directories: [URL], sampleCount: Int, state: State, observedAt: Date = Date()) {
        self.directories = Array(Set(directories)).sorted { $0.path < $1.path }
        self.sampleCount = sampleCount
        self.state = state
        self.observedAt = observedAt
    }

    public var summary: String {
        switch state {
        case .sampled: return L10n.text("已完成 {0} 次打开文件采样；短暂访问和未使用功能可能未被记录。访问记录不等于可删除。", String(sampleCount))
        case .unavailable: return L10n.text("部分进程或打开文件不可读取，观察范围受限；基础扫描结果仍然有效。")
        case .cancelled: return L10n.text("观察已停止，已发现的路径保留；这不是完整访问记录。")
        }
    }
}

public protocol ApplicationFileObserving: Sendable {
    func capture(applications: [InstalledApplication], home: URL) async -> [URL: ApplicationRuntimeObservation]
}

/// Unprivileged, point-in-time open-file snapshots. Never launches applications,
/// reads file contents, or promotes observed paths to deletion ownership.
public struct LocalApplicationFileObserver: ApplicationFileObserving {
    public init() {}
    public func capture(applications: [InstalledApplication], home: URL) async -> [URL: ApplicationRuntimeObservation] {
        let unavailable = Dictionary(uniqueKeysWithValues: applications.map {
            ($0.id, ApplicationRuntimeObservation(directories: [], sampleCount: 0, state: .unavailable))
        })
        guard !applications.isEmpty, !Task.isCancelled else { return unavailable }
        do {
            let processes = try await BoundedProcess.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,comm="], timeout: 2)
            guard processes.status == 0, let processText = String(data: processes.stdout, encoding: .utf8) else { return unavailable }
            let owners = Self.processOwners(processText, applications: applications)
            guard !owners.isEmpty, owners.count <= 256 else { return unavailable }
            let result = try await BoundedProcess.run("/usr/sbin/lsof", arguments: ["-nP", "-a", "-p", owners.keys.sorted().map(String.init).joined(separator: ","), "-Fpfn"], timeout: 2, maximumOutputBytes: 4_194_304)
            guard let text = String(data: result.stdout, encoding: .utf8) else { return unavailable }
            let parsed = Self.parseOpenFiles(text, owners: owners, home: home)
            return Dictionary(uniqueKeysWithValues: applications.map { app in
                let visible = parsed.seenOwners.contains(app.id)
                return (app.id, ApplicationRuntimeObservation(directories: parsed.paths[app.id, default: []], sampleCount: visible ? 1 : 0,
                    state: visible && result.status == 0 && result.stderr.isEmpty ? .sampled : .unavailable))
            })
        } catch { return unavailable }
    }

    public static func processOwners(_ text: String, applications: [InstalledApplication]) -> [Int32: Set<URL>] {
        var parents: [Int32: Int32] = [:]
        var owners: [Int32: Set<URL>] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), pid > 1, let parent = Int32(fields[1]) else { continue }
            parents[pid] = parent
            let executable = String(fields[2])
            let physical = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            let matches = applications.filter {
                ApplicationOwnershipGraphBuilder.isWithin(executable, $0.id.path)
                    || ApplicationOwnershipGraphBuilder.isWithin(physical, $0.id.resolvingSymlinksInPath().path)
            }.map(\.id)
            if !matches.isEmpty { owners[pid] = Set(matches) }
        }
        // Bounded ancestry propagation includes helpers outside the app bundle.
        // A directly identified application keeps its own identity.
        for _ in 0..<16 {
            var changed = false
            for (pid, parent) in parents where owners[pid] == nil {
                if let inherited = owners[parent] { owners[pid] = inherited; changed = true }
            }
            if !changed { break }
        }
        return owners
    }

    public static func parseOpenFiles(_ text: String, owners: [Int32: Set<URL>], home: URL) -> (paths: [URL: [URL]], seenOwners: Set<URL>) {
        var currentOwners = Set<URL>()
        var seenOwners = Set<URL>()
        var paths: [URL: Set<URL>] = [:]
        for line in text.split(separator: "\n") {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) {
                currentOwners = owners[pid, default: []]
                seenOwners.formUnion(currentOwners)
            } else if line.hasPrefix("n/"), let directory = candidateDirectory(for: String(line.dropFirst()), home: home) {
                for owner in currentOwners { paths[owner, default: []].insert(directory) }
            }
        }
        return (paths.mapValues { Array($0) }, seenOwners)
    }

    public static func candidateDirectory(for path: String, home: URL) -> URL? {
        guard !path.contains("\n"), !path.contains(" (deleted)"), !path.contains("\\"),
              !path.split(separator: "/").contains("..") else { return nil }
        // Kernel tools can spell the same location as /private/var while
        // Foundation exposes /var. Compare physical paths on both sides.
        let physicalPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let roots = ApplicationAssociationPathRegistry.roots(home: home).filter {
            !$0.isSystem && $0.removalPolicy == .recoverable && $0.matching != .diagnostic
        }.sorted { $0.url.path.count > $1.url.path.count }
        for spec in roots {
            let root = spec.url.resolvingSymlinksInPath().path + "/"
            guard physicalPath.hasPrefix(root), let child = physicalPath.dropFirst(root.count).split(separator: "/").first,
                  !child.hasPrefix(".") else { continue }
            var url = URL(fileURLWithPath: root + child)
            if spec.isVendorDirectory(url, for: []) {
                let components = physicalPath.dropFirst(root.count).split(separator: "/")
                guard components.count > 1, !components[1].hasPrefix(".") else { return nil }
                url.appendPathComponent(String(components[1]))
            }
            guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { return nil }
            return url
        }
        return nil
    }
}

public struct ApplicationRuntimeSampler: Sendable {
    private let observer: any ApplicationFileObserving
    private let samples: Int
    private let interval: UInt64
    public init(observer: any ApplicationFileObserving = LocalApplicationFileObserver(), samples: Int = 3, intervalNanoseconds: UInt64 = 1_000_000_000) {
        self.observer = observer; self.samples = min(5, max(1, samples)); self.interval = min(intervalNanoseconds, 2_000_000_000)
    }
    public func observe(applications: [InstalledApplication], home: URL,
                        progress: @escaping @Sendable ([URL: ApplicationRuntimeObservation]) async -> Void = { _ in }) async -> [URL: ApplicationRuntimeObservation] {
        guard !applications.isEmpty else { return [:] }
        var accumulated: [URL: ApplicationRuntimeObservation] = [:]
        for index in 0..<samples {
            if Task.isCancelled { break }
            let current = await observer.capture(applications: applications, home: home)
            for app in applications {
                let previous = accumulated[app.id]
                let next = current[app.id] ?? .init(directories: [], sampleCount: 0, state: .unavailable)
                accumulated[app.id] = .init(directories: (previous?.directories ?? []) + next.directories,
                    sampleCount: (previous?.sampleCount ?? 0) + next.sampleCount,
                    state: previous?.state == .unavailable || next.state == .unavailable ? .unavailable : .sampled)
            }
            await progress(accumulated)
            if index + 1 < samples { try? await Task.sleep(nanoseconds: interval) }
        }
        if Task.isCancelled {
            for app in applications {
                let value = accumulated[app.id]
                accumulated[app.id] = .init(directories: value?.directories ?? [], sampleCount: value?.sampleCount ?? 0, state: .cancelled)
            }
        }
        return accumulated
    }
}

public enum ApplicationObservationLifecycle {
    public static func shouldRequestQuit(processID: Int32, preexistingProcessIDs: Set<Int32>, launchDate: Date?, observationStartedAt: Date) -> Bool {
        !preexistingProcessIDs.contains(processID) && launchDate.map { $0 >= observationStartedAt } == true
    }

    public static func hasLiveBundleProcesses(_ application: InstalledApplication, dataDirectory: URL? = nil) async throws -> Bool {
        let snapshot = try await BoundedProcess.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,comm="], timeout: 2)
        guard snapshot.status == 0, let text = String(data: snapshot.stdout, encoding: .utf8) else { throw ApplicationExecutionRejection.ownershipChanged }
        if !LocalApplicationFileObserver.processOwners(text, applications: [application]).isEmpty { return true }
        guard let dataDirectory else { return false }
        return text.split(separator: "\n").contains { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3 else { return false }
            let path = URL(fileURLWithPath: String(fields[2])).resolvingSymlinksInPath().path
            return ApplicationOwnershipGraphBuilder.isWithin(path, dataDirectory.resolvingSymlinksInPath().path)
        }
    }
}
