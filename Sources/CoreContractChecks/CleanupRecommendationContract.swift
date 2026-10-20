import CleanerCore
import Foundation

func runCleanupRecommendationContracts() {
    let safe = recommendationCandidate(name: "Safe", category: .cache, risk: .safe)
    let cache = recommendationCandidate(name: "Cache", category: .cache, risk: .review)
    let model = recommendationCandidate(name: "Model", category: .agentModelCache, risk: .review)
    let session = recommendationCandidate(name: "Session", category: .agentSession, risk: .review)
    let activeCache = recommendationCandidate(name: "Active", category: .developerCache, risk: .review, isActive: true)
    let blocked = recommendationCandidate(name: "Credential", category: .credential, risk: .blocked)
    let policy = CleanupRecommendationPolicy()

    require(policy.disposition(for: safe) == .recommended, "safe candidate is recommended")
    require(policy.disposition(for: cache) == .deepClean, "review cache is deep-clean eligible")
    require(policy.disposition(for: model) == .deepClean, "model cache is deep-clean eligible")
    require(policy.disposition(for: session) == .retain, "agent session is retained")
    require(policy.disposition(for: activeCache) == .retain, "active cache is retained")
    require(policy.disposition(for: blocked) == .protected, "blocked candidate is protected")

    let breakdown = policy.breakdown(for: [safe, cache, model, session, activeCache, blocked])
    require(breakdown.recommended == [safe], "recommendation breakdown exposes recommended candidates independently")
    require(breakdown.deepClean == [cache, model], "recommendation breakdown must not present deep-clean candidates as retained")
    require(breakdown.retained == [session, activeCache], "recommendation breakdown contains only genuinely retained candidates")
    require(breakdown.protected == [blocked], "recommendation breakdown keeps protected candidates separate")

    let candidates = [safe, cache, model, session, activeCache, blocked]
    require(
        policy.selectedIDs(for: candidates, mode: .smart, currentSelection: []) == Set([safe.id]),
        "smart mode selects only recommended candidates"
    )
    require(
        policy.selectedIDs(for: candidates, mode: .deep, currentSelection: []) == Set([safe.id, cache.id, model.id]),
        "deep mode adds only rebuildable inactive candidates"
    )
    require(
        policy.selectedIDs(for: candidates, mode: .custom, currentSelection: [session.id, blocked.id]) == Set([session.id]),
        "custom mode preserves selectable choices but removes blocked candidates"
    )

}

private func recommendationCandidate(
    name: String,
    category: CleanupCategory,
    risk: RiskLevel,
    isActive: Bool = false,
    source: CandidateSource = .general
) -> CleanupCandidate {
    CleanupCandidate(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        displayName: name,
        category: category,
        bytes: 1,
        risk: risk,
        evidence: [Evidence(code: "fixture", summary: "Fixture")],
        identity: FileIdentity(device: 1, inode: UInt64.random(in: 1...UInt64.max), size: 1, modificationTime: 1, kind: .directory),
        source: source,
        lastAccessDate: nil,
        isActive: isActive
    )
}
