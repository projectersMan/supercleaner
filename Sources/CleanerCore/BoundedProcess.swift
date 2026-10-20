import Darwin
import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}

public enum ProcessFailure: Error, Sendable { case timedOut, outputLimit, cancelled }

/// Fixed executable paths and argument arrays avoid shell interpretation. Each
/// pipe is drained independently, bounded in memory, and cancellation kills the
/// launched process before completing the caller.
public enum BoundedProcess {
    public static func run(
        _ executable: String, arguments: [String], directory: URL? = nil,
        timeout: TimeInterval = 5, maximumOutputBytes: Int = 1_048_576,
        environment: [String: String]? = nil
    ) async throws -> ProcessOutput {
        let invocation = ProcessInvocation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try invocation.start(executable, arguments: arguments, directory: directory, environment: environment)
                        let stdout = ProcessCapture(limit: maximumOutputBytes)
                        let stderr = ProcessCapture(limit: maximumOutputBytes)
                        let readers = DispatchGroup()
                        for (pipe, capture) in [(invocation.stdout, stdout), (invocation.stderr, stderr)] {
                            readers.enter()
                            DispatchQueue.global(qos: .utility).async {
                                defer { readers.leave() }
                                while let data = try? pipe.fileHandleForReading.read(upToCount: 16_384), !data.isEmpty {
                                    if !capture.append(data) { invocation.stop(.outputLimit) }
                                }
                            }
                        }
                        let timer = DispatchWorkItem { invocation.stop(.timedOut) }
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.05, timeout), execute: timer)
                        invocation.process.waitUntilExit()
                        timer.cancel()
                        if readers.wait(timeout: .now() + 1) == .timedOut {
                            throw invocation.failure ?? ProcessFailure.timedOut
                        }
                        if let error = invocation.failure { throw error }
                        continuation.resume(returning: ProcessOutput(status: invocation.process.terminationStatus, stdout: stdout.data, stderr: stderr.data))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { invocation.stop(.cancelled) }
    }
}

private final class ProcessInvocation: @unchecked Sendable {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    private let lock = NSLock()
    private var storedFailure: ProcessFailure?
    var failure: ProcessFailure? { lock.withLock { storedFailure } }

    func start(_ executable: String, arguments: [String], directory: URL?, environment: [String: String]?) throws {
        try lock.withLock {
            if let storedFailure { throw storedFailure }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }
    }

    func stop(_ error: ProcessFailure) {
        lock.withLock {
            // A completed process must not acquire a timeout after its exit.
            if !process.isRunning, process.processIdentifier != 0 { return }
            if storedFailure == nil { storedFailure = error }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

private final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var buffer = Data()
    init(limit: Int) { self.limit = max(1, limit) }
    var data: Data { lock.withLock { buffer } }
    func append(_ data: Data) -> Bool {
        lock.withLock {
            let room = max(0, limit - buffer.count)
            buffer.append(data.prefix(room))
            return data.count <= room
        }
    }
}

public struct ActivitySnapshot: Sendable {
    public let processNames: Set<String>
    public let isAvailable: Bool
    public let buildProcessIDs: [Int32]

    public static func capture() async -> ActivitySnapshot {
        do {
            let output = try await BoundedProcess.run("/bin/ps", arguments: ["-axo", "pid=,comm="], timeout: 3)
            guard output.status == 0, let text = String(data: output.stdout, encoding: .utf8) else {
                return ActivitySnapshot(processNames: [], isAvailable: false, buildProcessIDs: [])
            }
            var names = Set<String>()
            var buildPIDs: [Int32] = []
            for line in text.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
                let name = URL(fileURLWithPath: String(parts[1])).lastPathComponent.lowercased()
                names.insert(name)
                if ProjectActivityProbe.toolNames.contains(name) { buildPIDs.append(pid) }
            }
            return ActivitySnapshot(processNames: names, isAvailable: true, buildProcessIDs: buildPIDs)
        } catch { return ActivitySnapshot(processNames: [], isAvailable: false, buildProcessIDs: []) }
    }
}

public enum ProjectActivityProbe {
    static let toolNames: Set<String> = ["node", "npm", "pnpm", "yarn", "bun", "cargo", "rustc", "swift", "swift-frontend", "xcodebuild", "gradle", "java", "cmake", "ninja", "make", "clang", "gcc", "python", "python3"]

    public static func capture(activity: ActivitySnapshot, roots: [URL]) async -> (paths: Set<URL>, isAvailable: Bool) {
        guard activity.isAvailable, activity.buildProcessIDs.count <= 256 else { return ([], false) }
        guard !activity.buildProcessIDs.isEmpty else { return ([], true) }
        do {
            let pids = activity.buildProcessIDs.map(String.init).joined(separator: ",")
            let output = try await BoundedProcess.run("/usr/sbin/lsof", arguments: ["-n", "-a", "-p", pids, "-Fn"], timeout: 5, maximumOutputBytes: 4_194_304)
            guard output.status == 0, let text = String(data: output.stdout, encoding: .utf8) else { return ([], false) }
            let normalized = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            let paths = text.split(separator: "\n").compactMap { line -> URL? in
                guard line.hasPrefix("n/") else { return nil }
                let url = URL(fileURLWithPath: String(line.dropFirst())).standardizedFileURL
                guard normalized.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { return nil }
                return url
            }
            return (Set(paths), true)
        } catch { return ([], false) }
    }
}
