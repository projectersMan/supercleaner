import AppKit

/// Launch Services can block while resolving process properties. Keep that IPC
/// off the UI actor; callers receive only immutable identifiers.
public enum RunningApplicationSnapshot {
    public static func identifiers() async -> Set<String> {
        await identifiers(read: {
            Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        })
    }

    static func identifiers(read: @escaping @Sendable () -> Set<String>) async -> Set<String> {
        await Task.detached(priority: .utility, operation: read).value
    }
}
