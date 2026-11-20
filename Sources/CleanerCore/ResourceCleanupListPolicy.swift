import Foundation

public enum ResourceCleanupListScope: Int, CaseIterable, Sendable {
    case all
    case cleanable
    case protected
    case selected

    public static func scopes(for destination: AppDestination) -> [Self] {
        destination == .projects ? [.all, .protected, .selected] : allCases
    }
}

public enum ResourceCleanupListPolicy {
    public static func projectReviewCandidates(_ candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        let directories = CleanupPathIndex(paths: Set(candidates.filter {
            $0.source == .projectArtifacts && $0.identity.kind == .directory && isSelectable($0)
        }.map { CleanupPathIndex.path($0.url) }))
        return candidates.filter {
            $0.source != .projectArtifacts || $0.identity.kind != .file || $0.url.pathExtension.lowercased() != "dmg"
                || !directories.contains($0.url)
        }
    }

    public static func isSelectable(_ candidate: CleanupCandidate) -> Bool {
        candidate.risk.isSelectable && !candidate.isActive && !candidate.hasIncompleteScan
    }

    public static func selectableCandidates(_ candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        candidates.filter(isSelectable)
    }

    public static func visibleCandidates(_ candidates: [CleanupCandidate], query: String, scope: ResourceCleanupListScope,
        sortOrder: LargeFileSortOrder, selectedIDs: Set<UUID>) -> [CleanupCandidate] {
        let search = ReviewCandidateFilter(query: query, risks: Set(RiskLevel.allCases), selectedOnly: false)
        return candidates.filter { candidate in
            guard search.includes(candidate, selectedIDs: selectedIDs) else { return false }
            switch scope {
            case .all: return true
            case .cleanable: return isSelectable(candidate)
            case .protected: return !isSelectable(candidate)
            case .selected: return selectedIDs.contains(candidate.id)
            }
        }.sorted { lhs, rhs in
            if sortOrder == .selection {
                let leftSelected = selectedIDs.contains(lhs.id)
                let rightSelected = selectedIDs.contains(rhs.id)
                if leftSelected != rightSelected { return leftSelected }
            }
            if sortOrder == .directory {
                let leftDirectory = lhs.url.deletingLastPathComponent().path
                let rightDirectory = rhs.url.deletingLastPathComponent().path
                if leftDirectory != rightDirectory {
                    return leftDirectory.localizedStandardCompare(rightDirectory) == .orderedAscending
                }
            }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }
}
