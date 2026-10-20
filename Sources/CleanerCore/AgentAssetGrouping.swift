import Foundation

public struct AgentResourceGroup: Identifiable, Hashable, Sendable {
    public var id: String { "\(provider.rawValue)/\(scope.rawValue)/\(resourceKind.rawValue)" }
    public let provider: AgentProvider
    public let scope: AgentScope
    public let resourceKind: AgentResourceKind
    public let assets: [AgentAssetRecord]

    public let bytes: UInt64
    public let selectableIDs: Set<UUID>
    public var selectableCount: Int { selectableIDs.count }

    init(provider: AgentProvider, scope: AgentScope, resourceKind: AgentResourceKind, assets: [AgentAssetRecord]) {
        self.provider = provider
        self.scope = scope
        self.resourceKind = resourceKind
        self.assets = assets
        bytes = assets.reduce(0) { $0 + $1.candidate.bytes }
        selectableIDs = Set(assets.filter {
            $0.candidate.risk.isSelectable
                && !$0.candidate.isActive
                && $0.activity != .active
                && [.recommended, .deep].contains($0.cleanupEligibility)
        }.map(\.id))
    }
}

public struct AgentScopeGroup: Identifiable, Hashable, Sendable {
    public var id: String { "\(provider.rawValue)/\(scope.rawValue)" }
    public let provider: AgentProvider
    public let scope: AgentScope
    public let resourceGroups: [AgentResourceGroup]
}

public struct AgentAssetGroup: Identifiable, Hashable, Sendable {
    public var id: AgentProvider { provider }
    public let provider: AgentProvider
    public let scopes: [AgentScopeGroup]
}

public enum AgentAssetGrouping {
    public static func group(_ assets: [AgentAssetRecord]) -> [AgentAssetGroup] {
        Dictionary(grouping: assets, by: \.provider)
            .map { provider, providerAssets in
                let scopes = Dictionary(grouping: providerAssets, by: \.scope)
                    .map { scope, scopeAssets in
                        let resources = Dictionary(grouping: scopeAssets, by: \.resourceKind)
                            .map { kind, records in
                                AgentResourceGroup(
                                    provider: provider,
                                    scope: scope,
                                    resourceKind: kind,
                                    assets: records.sorted {
                                        $0.candidate.url.path.localizedStandardCompare($1.candidate.url.path) == .orderedAscending
                                    }
                                )
                            }
                            .sorted { $0.resourceKind.rawValue < $1.resourceKind.rawValue }
                        return AgentScopeGroup(provider: provider, scope: scope, resourceGroups: resources)
                    }
                    .sorted { $0.scope.rawValue < $1.scope.rawValue }
                return AgentAssetGroup(provider: provider, scopes: scopes)
            }
            .sorted { providerOrder($0.provider) < providerOrder($1.provider) }
    }

    public static func selectableIDs(in group: AgentResourceGroup) -> Set<UUID> {
        group.selectableIDs
    }

    private static func providerOrder(_ provider: AgentProvider) -> Int {
        switch provider {
        case .codex: 0
        case .claude: 1
        case .cursor: 2
        case .trae: 3
        case .shared: 4
        case .genericMCP: 5
        case .git: 6
        }
    }
}
