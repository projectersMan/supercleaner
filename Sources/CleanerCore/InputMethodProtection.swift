import Foundation

/// Input methods live outside Applications and participate in system-wide text
/// input. Their complete runtime caches are not generic cleanup candidates.
enum InputMethodProtection {
    static func applicationRoots(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Library/Input Methods"), home.appendingPathComponent("Library/Input Methods"),
         URL(fileURLWithPath: "/System/Library/Input Methods")]
    }

    static func contains(_ bundle: URL, home: URL) -> Bool {
        applicationRoots(home: home).contains { bundle.deletingLastPathComponent().path.lowercased() == $0.path.lowercased() }
    }

    static func cacheRoots(applications: [InstalledApplication], home: URL) -> [URL] {
        let identifiers = applications.filter { contains($0.bundleURL, home: home) }.flatMap {
            [$0.bundleIdentifier] + ($0.associatedBundleIdentifiers ?? []) + ($0.applicationGroups ?? [])
        }
        return Set(identifiers).filter { !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }
            .map { home.appendingPathComponent("Library/Caches").appendingPathComponent($0) }
    }

    static func overlaps(_ url: URL, roots: [URL]) -> Bool {
        let path = CleanupPathIndex.path(url).lowercased()
        return roots.contains {
            let root = CleanupPathIndex.path($0).lowercased()
            return path == root || path.hasPrefix(root + "/") || root.hasPrefix(path + "/")
        }
    }

    static func validate(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        let cache = context.homeDirectory.appendingPathComponent("Library/Caches").path.lowercased()
        let path = candidate.url.path.lowercased()
        guard path == cache || path.hasPrefix(cache + "/") else { return }
        let inventory = await ApplicationScanner(applicationRoots: applicationRoots(home: context.homeDirectory))
            .installedApplications(context: context)
        guard inventory.coverage.unavailableRoots.isEmpty, inventory.coverage.budgetLimitedModules.isEmpty else {
            throw PathPolicyError.protectedPath(candidate.url.path)
        }
        guard !overlaps(candidate.url, roots: cacheRoots(applications: inventory.applications, home: context.homeDirectory)) else {
            throw PathPolicyError.protectedPath(candidate.url.path)
        }
    }
}
