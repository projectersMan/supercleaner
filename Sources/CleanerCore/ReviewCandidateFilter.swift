import Foundation

public struct ReviewCandidateFilter: Equatable, Sendable {
    public var query: String
    public var risks: Set<RiskLevel>
    public var selectedOnly: Bool

    public init(
        query: String = "",
        risks: Set<RiskLevel> = Set(RiskLevel.allCases),
        selectedOnly: Bool = false
    ) {
        self.query = query
        self.risks = risks
        self.selectedOnly = selectedOnly
    }

    public func includes(_ candidate: CleanupCandidate, selectedIDs: Set<UUID>) -> Bool {
        guard risks.contains(candidate.risk) else { return false }
        guard !selectedOnly || selectedIDs.contains(candidate.id) else { return false }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }

        let searchable = [
            candidate.displayName,
            candidate.url.path,
            candidate.source.rawValue,
            candidate.category.rawValue,
        ] + candidate.evidence.flatMap { [$0.summary, $0.details ?? ""] }

        return searchable.contains { $0.lowercased().contains(needle) }
    }
}
