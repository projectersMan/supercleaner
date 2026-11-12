import AppKit

@MainActor public protocol ApplicationQuitProcess: AnyObject {
    var bundleURL: URL? { get }
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    func terminate() -> Bool
}

extension NSRunningApplication: ApplicationQuitProcess {}

public enum ApplicationQuitResult: Equatable, Sendable {
    case terminated, notRunning, refused, stillRunning, protectedApplication
}

/// Requests normal termination only. Exact bundle paths distinguish installed
/// copies, and retained process handles prevent accidentally targeting a restart.
@MainActor public enum ApplicationQuitService {
    public static func quit(_ application: InstalledApplication) async -> ApplicationQuitResult {
        await quit(application, processes: NSWorkspace.shared.runningApplications,
            currentPID: ProcessInfo.processInfo.processIdentifier,
            pause: { try? await Task.sleep(for: .milliseconds(250)) })
    }

    static func quit(_ application: InstalledApplication, processes: [any ApplicationQuitProcess],
                     currentPID: pid_t, pause: () async -> Void) async -> ApplicationQuitResult {
        guard !application.isSystem else { return .protectedApplication }
        let path = application.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let targets = processes.filter {
            !$0.isTerminated && $0.bundleIdentifier == application.bundleIdentifier
                && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == path
        }
        guard !targets.contains(where: { $0.processIdentifier == currentPID }) else { return .protectedApplication }
        guard !targets.isEmpty else { return .notRunning }
        var refused = false
        for target in targets where !target.isTerminated {
            if !target.terminate() { refused = true }
        }
        for _ in 0..<32 {
            if targets.allSatisfy(\.isTerminated) { return .terminated }
            if Task.isCancelled { break }
            await pause()
        }
        if targets.allSatisfy(\.isTerminated) { return .terminated }
        return refused ? .refused : .stillRunning
    }
}
