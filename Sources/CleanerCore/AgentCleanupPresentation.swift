import Foundation

/// Prepared away from the UI thread once per platform and scan generation.
/// Subsequent filter changes operate on resource groups, not individual assets.
public struct AgentCleanupPresentation: Sendable {
    public let provider: AgentProvider?
    public let groups: [AgentResourceGroup]
    public let candidates: [CleanupCandidate]
    public let assetCount: Int
    public let bytes: UInt64

    public init(assets: [AgentAssetRecord], provider: AgentProvider?) {
        self.provider = provider
        guard let provider else {
            groups = []
            candidates = []
            assetCount = 0
            bytes = 0
            return
        }
        let eligible = assets.filter {
            $0.provider == provider
                && $0.candidate.risk.isSelectable
                && !$0.candidate.isActive
                && $0.activity != .active
                && [.recommended, .deep].contains($0.cleanupEligibility)
        }
        groups = AgentAssetGrouping.group(eligible).flatMap(\.scopes).flatMap(\.resourceGroups)
        candidates = eligible.map(\.candidate)
        assetCount = eligible.count
        bytes = eligible.reduce(0) { $0 + $1.candidate.bytes }
    }

    public var scopes: [AgentScope] {
        AgentScope.allCases.filter { scope in groups.contains { $0.scope == scope } }
    }

    public func resourceKinds(scope: AgentScope?) -> [AgentResourceKind] {
        AgentResourceKind.allCases.filter { kind in
            groups.contains { $0.resourceKind == kind && (scope == nil || $0.scope == scope) }
        }
    }

    public func filteredGroups(scope: AgentScope?, kind: AgentResourceKind?) -> [AgentResourceGroup] {
        groups.filter {
            (scope == nil || $0.scope == scope) && (kind == nil || $0.resourceKind == kind)
        }
    }
}
