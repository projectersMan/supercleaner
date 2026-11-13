import Foundation

/// A selected directory is one filesystem operation and already includes its
/// selected descendants. Keep the scan entries for review, not repeated moves.
public enum CleanupSelection {
    public static func executionCandidates(from selected: [CleanupCandidate]) -> [CleanupCandidate] {
        let paths = selected.map { CleanupPathIndex.path($0.url) }
        let directories = Set(zip(selected, paths).compactMap { candidate, path in
            candidate.identity.kind == .directory ? path : nil
        })
        var seen = Set<String>()
        let operations = zip(selected, paths).compactMap { candidate, path -> CleanupCandidate? in
            var ancestor = path
            while ancestor != "/", let slash = ancestor.lastIndex(of: "/") {
                ancestor = slash == ancestor.startIndex ? "/" : String(ancestor[..<slash])
                if directories.contains(ancestor) { return nil }
            }
            return seen.insert(path).inserted ? candidate : nil
        }
        // Agent traversal records each file/directory's own size. Other scanners
        // already give directory candidates recursive sizes, so only Agent sizes
        // must be rolled up when their child operations are consolidated.
        let agentRoots = Set(operations.filter { $0.source == .agentWorkspace }.map { CleanupPathIndex.path($0.url) })
        guard !agentRoots.isEmpty else { return operations }
        var bytesByRoot = [String: UInt64]()
        var counted = Set<String>()
        for (candidate, path) in zip(selected, paths) where candidate.source == .agentWorkspace && counted.insert(path).inserted {
            var root = path
            while !agentRoots.contains(root), root != "/", let slash = root.lastIndex(of: "/") {
                root = slash == root.startIndex ? "/" : String(root[..<slash])
            }
            guard agentRoots.contains(root) else { continue }
            let sum = (bytesByRoot[root] ?? 0).addingReportingOverflow(candidate.bytes)
            bytesByRoot[root] = sum.overflow ? .max : sum.partialValue
        }
        return operations.map { candidate in
            guard let bytes = bytesByRoot[CleanupPathIndex.path(candidate.url)] else { return candidate }
            return CleanupCandidate(id: candidate.id, url: candidate.url, displayName: candidate.displayName,
                category: candidate.category, bytes: bytes, risk: candidate.risk, evidence: candidate.evidence,
                identity: candidate.identity, source: candidate.source, lastAccessDate: candidate.lastAccessDate,
                isActive: candidate.isActive, ruleID: candidate.ruleID, defaultSelection: candidate.defaultSelection,
                requiresExplicitSelection: candidate.requiresExplicitSelection, cleanupApplication: candidate.cleanupApplication,
                largeFileProof: candidate.largeFileProof)
        }
    }
}
