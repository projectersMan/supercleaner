import CleanerCore
import Foundation

func runReviewFilterContracts() {
    let codexReview = reviewFilterCandidate(name: "Codex Cache", path: "/tmp/codex-cache", risk: .review, evidence: "model cache")
    let codexBlocked = reviewFilterCandidate(name: "Codex Skills", path: "/tmp/codex-skills", risk: .blocked, evidence: "protected knowledge")
    let unrelated = reviewFilterCandidate(name: "Safari Cache", path: "/tmp/safari", risk: .review, evidence: "browser cache")

    let filtered = ReviewCandidateFilter(query: "codex", risks: [.review], selectedOnly: false)
    require(filtered.includes(codexReview, selectedIDs: []), "query and risk must include matching candidate")
    require(!filtered.includes(codexBlocked, selectedIDs: []), "risk filter must exclude blocked candidate")
    require(!filtered.includes(unrelated, selectedIDs: []), "query must exclude unrelated candidate")

    let evidenceSearch = ReviewCandidateFilter(query: "knowledge")
    require(evidenceSearch.includes(codexBlocked, selectedIDs: []), "evidence details must be searchable")

    let selectedOnly = ReviewCandidateFilter(selectedOnly: true)
    require(!selectedOnly.includes(codexReview, selectedIDs: []), "selected-only must hide unselected candidate")
    require(selectedOnly.includes(codexReview, selectedIDs: [codexReview.id]), "selected-only must retain selected candidate")
}

private func reviewFilterCandidate(name: String, path: String, risk: RiskLevel, evidence: String) -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: path),
        displayName: name,
        category: .cache,
        bytes: 1,
        risk: risk,
        evidence: [Evidence(code: "fixture", summary: evidence, details: "detail \(evidence)")],
        identity: FileIdentity(device: 1, inode: UInt64(abs(path.hashValue)), size: 1, modificationTime: 1, kind: .file),
        source: .general,
        lastAccessDate: nil,
        isActive: false
    )
}
