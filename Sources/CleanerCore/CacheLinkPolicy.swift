import Foundation

/// Links wholly contained within an approved cleanup root are removed without
/// following their targets. Links escaping that root are never accepted here.
enum CacheLinkPolicy {
    static func permitsInternalLink(_ entry: URL, within root: URL, allowed: Bool) -> Bool {
        guard allowed, entry.path != root.path else { return false }
        let physicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let target = entry.resolvingSymlinksInPath().standardizedFileURL.path
        return target == physicalRoot || target.hasPrefix(physicalRoot + "/")
    }
}
