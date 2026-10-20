import CleanerCore
import Foundation

func runCleanupModeContracts() {
    require(CleanupMode.userFacingCases.map(\.displayTitle) == [L10n.text("自动清理"), L10n.text("手动选择")], "cleanup center must expose automatic and manual modes")
    require(CleanupMode.defaultMode == .deep, "automatic cleanup must be the default one-click plan")

    let recommended = modeCandidate(name: "Recommended", category: .cache, risk: .safe)
    let deep = modeCandidate(name: "Deep", category: .developerCache, risk: .review)
    let retained = modeCandidate(name: "Retained", category: .agentSession, risk: .review)
    let blocked = modeCandidate(name: "Blocked", category: .credential, risk: .blocked)
    let candidates = [recommended, deep, retained, blocked]
    let otherModuleSelectionID = UUID()
    var state = CleanupModeSelectionState(
        mode: .custom,
        selectedIDs: [retained.id, blocked.id, otherModuleSelectionID]
    )

    require(
        state.applying(.custom, to: candidates).selectedIDs == Set([retained.id, otherModuleSelectionID]),
        "custom mode must drop blocked items only inside its module and preserve other-module selection"
    )
    state = state.applying(.smart, to: candidates)
    require(state.mode == .smart, "smart transition records mode")
    require(
        state.selectedIDs == Set([recommended.id, otherModuleSelectionID]),
        "smart transition must replace only the current module selection"
    )
    state = state.applying(.deep, to: candidates)
    require(
        state.selectedIDs == Set([recommended.id, deep.id, otherModuleSelectionID]),
        "deep transition must expand only the current module recommendation"
    )
    state = state.applying(.custom, to: candidates)
    require(
        state.selectedIDs == Set([recommended.id, deep.id, otherModuleSelectionID]),
        "custom transition must preserve the current plan across modules"
    )
    state = state.removing([recommended, deep])
    require(
        state.selectedIDs == [otherModuleSelectionID],
        "single-module execution must clear only attempted candidates and preserve other-module selection"
    )

    var strategy = CleanupStrategySelectionState(
        strategy: .smart,
        generationID: UUID(),
        selectedIDs: [recommended.id],
        excludedBaseIDs: []
    )
    strategy.toggle(recommended, baseEligibleIDs: [recommended.id])
    require(strategy.strategy == .smart, "excluding an item must keep the recommended strategy visible")
    require(strategy.selectedIDs.isEmpty && strategy.excludedBaseIDs == [recommended.id], "strategy exclusion must remove only the chosen base item")
    strategy.toggle(recommended, baseEligibleIDs: [recommended.id])
    require(strategy.selectedIDs == [recommended.id] && strategy.excludedBaseIDs.isEmpty, "rechecking restores the strategy base item")
    strategy.toggle(blocked, baseEligibleIDs: [recommended.id])
    require(!strategy.selectedIDs.contains(blocked.id), "blocked items must never enter strategy selection")
    require(strategy.selectionState(for: [recommended.id, deep.id]) == .partial, "category selection state must expose partial selection")

    let large = modeCandidate(name: "Large", category: .largeFile, risk: .safe)
    let agent = CleanupCandidate(
        url: URL(fileURLWithPath: "/tmp/Agent"),
        displayName: "Agent",
        category: .agentPackageCache,
        bytes: 1,
        risk: .safe,
        evidence: [],
        identity: FileIdentity(device: 1, inode: 777, size: 1, modificationTime: 1, kind: .directory),
        source: .agentWorkspace,
        lastAccessDate: nil,
        isActive: false
    )
    let centerScope = CleanupScopePolicy().cleanupCenterCandidates(from: [recommended, deep, large, agent])
    require(centerScope.map(\.id) == [recommended.id, deep.id], "cleanup center must include developer cache but exclude large-file and Agent modules")
    require(CleanupMode.userFacingCases.map(\.displayTitle) == [L10n.text("自动清理"), L10n.text("手动选择")], "strategy names must communicate automatic versus manual control")
    require(ByteCountFormatter.cleanerString(bytes: 0) == "0 KB", "zero-byte formatting")
    require(ByteCountFormatter.cleanerString(bytes: 1) == "< 1 KB", "tiny nonzero values must not appear as zero")
    require(CleanupScopePolicy().candidates(for: .largeFiles, from: [recommended, large, agent]) == [large], "large-file plans stay inside the large-file page")
    require(CleanupScopePolicy().candidates(for: .agentEnvironment, from: [recommended, large, agent]) == [agent], "Agent plans stay inside the Agent page")

}

private func modeCandidate(name: String, category: CleanupCategory, risk: RiskLevel) -> CleanupCandidate {
    CleanupCandidate(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        displayName: name,
        category: category,
        bytes: 1,
        risk: risk,
        evidence: [],
        identity: FileIdentity(device: 1, inode: UInt64.random(in: 1...UInt64.max), size: 1, modificationTime: 1, kind: .directory),
        source: .general,
        lastAccessDate: nil,
        isActive: false
    )
}
