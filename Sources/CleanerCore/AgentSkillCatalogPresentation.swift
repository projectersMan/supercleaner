import Foundation

public enum AgentSkillDecision: String, Codable, Hashable, Sendable, CaseIterable {
    case retain
    case plannedForDeletion
    case deletionUnavailable

    public var displayTitle: String {
        switch self {
        case .retain: "保留"
        case .plannedForDeletion: "加入删除计划"
        case .deletionUnavailable: "不可删除"
        }
    }
}

public struct AgentSkillCleanupBinding: Identifiable, Hashable, Sendable {
    public let skill: SkillCatalogEntry
    public let group: AgentCatalogGroup
    public let linkedAssets: [AgentAssetRecord]
    public let selectableCandidateIDs: Set<UUID>
    public let selectedCandidateIDs: Set<UUID>
    public let reclaimableBytes: UInt64
    public let totalLinkedBytes: UInt64
    public let containsProtectedAssets: Bool
    public let containsAmbiguousOwnership: Bool
    public let decisionReason: String

    public var id: String { skill.id }
    public var decision: AgentSkillDecision {
        guard isDeletionAvailable else { return .deletionUnavailable }
        return selectedCandidateIDs.isEmpty ? .retain : .plannedForDeletion
    }
    public var isDeletionAvailable: Bool {
        !selectableCandidateIDs.isEmpty && !containsProtectedAssets && !containsAmbiguousOwnership
    }

    public init(
        skill: SkillCatalogEntry,
        group: AgentCatalogGroup,
        linkedAssets: [AgentAssetRecord],
        selectableCandidateIDs: Set<UUID>,
        selectedCandidateIDs: Set<UUID>,
        reclaimableBytes: UInt64,
        totalLinkedBytes: UInt64,
        containsProtectedAssets: Bool,
        containsAmbiguousOwnership: Bool,
        decisionReason: String
    ) {
        self.skill = skill
        self.group = group
        self.linkedAssets = linkedAssets
        self.selectableCandidateIDs = selectableCandidateIDs
        self.selectedCandidateIDs = selectedCandidateIDs
        self.reclaimableBytes = reclaimableBytes
        self.totalLinkedBytes = totalLinkedBytes
        self.containsProtectedAssets = containsProtectedAssets
        self.containsAmbiguousOwnership = containsAmbiguousOwnership
        self.decisionReason = decisionReason
    }
}

public struct AgentSkillCatalogSection: Identifiable, Hashable, Sendable {
    public let group: AgentCatalogGroup
    public let skills: [AgentSkillCleanupBinding]

    public var id: String { group.id }
    public var skillCount: Int { skills.count }
    public var selectedSkillCount: Int {
        skills.filter { $0.decision == .plannedForDeletion }.count
    }
    public var reclaimableBytes: UInt64 {
        skills.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public init(group: AgentCatalogGroup, skills: [AgentSkillCleanupBinding]) {
        self.group = group
        self.skills = skills
    }
}

public struct AgentSkillCatalogPresentation: Sendable {
    public let sections: [AgentSkillCatalogSection]
    public let bindingsByID: [String: AgentSkillCleanupBinding]

    public init(
        skills: [SkillCatalogEntry],
        assets: [AgentAssetRecord],
        selectedIDs: Set<UUID>
    ) {
        let registry = AgentCatalogRegistry.shared
        let linkage = Self.makeLinkage(skills: skills, assets: assets)
        let bindings = skills.map {
            Self.makeBinding(
                skill: $0,
                linkedAssets: linkage.assetsBySkillID[$0.id, default: []],
                selectedIDs: selectedIDs,
                ambiguityByCandidateID: linkage.ambiguityByCandidateID,
                registry: registry
            )
        }
        let grouped = Dictionary(grouping: bindings, by: \.group)
        sections = grouped.keys.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }.compactMap { group in
            guard let groupBindings = grouped[group], !groupBindings.isEmpty else { return nil }
            return AgentSkillCatalogSection(
                group: group,
                skills: groupBindings.sorted(by: Self.compareBindings)
            )
        }
        bindingsByID = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
    }

    public func filteredSections(
        query: String,
        scope: AgentScope?,
        provider: AgentProvider?,
        deletableOnly: Bool
    ) -> [AgentSkillCatalogSection] {
        let normalizedQuery = SkillCatalogSupport.normalizedSearchToken(query)
        return sections.compactMap { section in
            let skills = section.skills.filter { binding in
                let scopeMatches = scope == nil || binding.skill.scope == scope
                let providerMatches = provider == nil || binding.skill.provider == provider
                let decisionMatches = !deletableOnly || binding.isDeletionAvailable
                let queryMatches = normalizedQuery.isEmpty || Self.matches(binding: binding, normalizedQuery: normalizedQuery)
                return providerMatches && scopeMatches && decisionMatches && queryMatches
            }
            guard !skills.isEmpty else { return nil }
            return AgentSkillCatalogSection(group: section.group, skills: skills)
        }
    }

    public func binding(for skillID: String?) -> AgentSkillCleanupBinding? {
        guard let skillID else { return sections.first?.skills.first }
        return bindingsByID[skillID] ?? sections.first?.skills.first
    }

    private static func makeBinding(
        skill: SkillCatalogEntry,
        linkedAssets: [AgentAssetRecord],
        selectedIDs: Set<UUID>,
        ambiguityByCandidateID: [UUID: Bool],
        registry: AgentCatalogRegistryStore
    ) -> AgentSkillCleanupBinding {
        let containsAmbiguousOwnership = linkedAssets.contains { ambiguityByCandidateID[$0.id] == true }
        let containsProtectedAssets = linkedAssets.contains {
            !$0.candidate.risk.isSelectable || $0.activity == .active || $0.cleanupEligibility == .protected
        }
        let selectableAssets = linkedAssets.filter {
            $0.candidate.risk.isSelectable
                && $0.activity != .active
                && $0.cleanupEligibility != .protected
                && ambiguityByCandidateID[$0.id] != true
        }
        let selectableCandidateIDs = Set(selectableAssets.map(\.id))
        let selectedCandidateIDs = selectedIDs.intersection(selectableCandidateIDs)
        let reclaimableBytes = selectableAssets.reduce(0) { $0 + $1.candidate.bytes }
        let totalLinkedBytes = linkedAssets.reduce(0) { $0 + $1.candidate.bytes }
        let decisionReason = makeDecisionReason(
            linkedAssets: linkedAssets,
            selectableCandidateIDs: selectableCandidateIDs,
            containsProtectedAssets: containsProtectedAssets,
            containsAmbiguousOwnership: containsAmbiguousOwnership
        )
        return AgentSkillCleanupBinding(
            skill: skill,
            group: registry.group(for: skill),
            linkedAssets: linkedAssets,
            selectableCandidateIDs: selectableCandidateIDs,
            selectedCandidateIDs: selectedCandidateIDs,
            reclaimableBytes: reclaimableBytes,
            totalLinkedBytes: totalLinkedBytes,
            containsProtectedAssets: containsProtectedAssets,
            containsAmbiguousOwnership: containsAmbiguousOwnership,
            decisionReason: decisionReason
        )
    }

    private struct SkillLinkage {
        let assetsBySkillID: [String: [AgentAssetRecord]]
        let ambiguityByCandidateID: [UUID: Bool]
    }

    /// Builds all Skill-to-asset relationships in one pass over asset paths. Looking up
    /// path ancestors avoids rescanning the complete asset inventory for every Skill.
    private static func makeLinkage(
        skills: [SkillCatalogEntry],
        assets: [AgentAssetRecord]
    ) -> SkillLinkage {
        var skillIDsByProviderAndRoot: [AgentProvider: [String: [String]]] = [:]
        for skill in skills {
            let rootPath = skill.skillRootURL.standardizedFileURL.path
            skillIDsByProviderAndRoot[skill.provider, default: [:]][rootPath, default: []].append(skill.id)
        }
        var assetsBySkillID: [String: [AgentAssetRecord]] = [:]
        var ambiguityByCandidateID: [UUID: Bool] = [:]
        for asset in assets {
            guard let roots = skillIDsByProviderAndRoot[asset.provider] else { continue }
            var currentPath = asset.cleanupUnitURL.standardizedFileURL.path
            var ownerIDs = Set<String>()
            while true {
                if let matchingIDs = roots[currentPath] {
                    ownerIDs.formUnion(matchingIDs)
                }
                guard currentPath != "/", let separator = currentPath.lastIndex(of: "/") else { break }
                currentPath = separator == currentPath.startIndex ? "/" : String(currentPath[..<separator])
            }
            for ownerID in ownerIDs {
                assetsBySkillID[ownerID, default: []].append(asset)
            }
            if ownerIDs.count > 1 { ambiguityByCandidateID[asset.id] = true }
        }
        return SkillLinkage(
            assetsBySkillID: assetsBySkillID,
            ambiguityByCandidateID: ambiguityByCandidateID
        )
    }

    private static func makeDecisionReason(
        linkedAssets: [AgentAssetRecord],
        selectableCandidateIDs: Set<UUID>,
        containsProtectedAssets: Bool,
        containsAmbiguousOwnership: Bool
    ) -> String {
        if linkedAssets.isEmpty {
            return "本轮扫描没有拉出该 Skill 的实体目录内容。"
        }
        if containsAmbiguousOwnership {
            return "该 Skill 关联的目录与其它 Skill 存在归属重叠，需要先在目录视图中确认。"
        }
        if containsProtectedAssets {
            return "该 Skill 目录内包含当前不可删或仍受保护的内容，因此不能整体加入删除计划。"
        }
        if selectableCandidateIDs.isEmpty {
            return "该 Skill 当前没有可加入删除计划的目录单元。"
        }
        return "删除时会把该 Skill 目录下已确认可删的内容一起加入当前计划。"
    }

    private static func matches(
        binding: AgentSkillCleanupBinding,
        normalizedQuery: String
    ) -> Bool {
        let tokens = [
            binding.skill.displayName,
            binding.skill.summary ?? "",
            binding.skill.provider.rawValue,
            binding.skill.scope.rawValue,
            binding.group.title,
            binding.skill.source.rawValue,
            binding.skill.kind.rawValue,
            binding.skill.skillRootURL.path,
            binding.skill.manifestURL?.path ?? "",
            binding.skill.tags.joined(separator: " "),
            binding.skill.triggers.joined(separator: " "),
            binding.skill.tools.joined(separator: " "),
        ]
        return tokens.contains {
            SkillCatalogSupport.normalizedSearchToken($0).contains(normalizedQuery)
        }
    }

    private static func compareBindings(_ lhs: AgentSkillCleanupBinding, _ rhs: AgentSkillCleanupBinding) -> Bool {
        if lhs.reclaimableBytes != rhs.reclaimableBytes {
            return lhs.reclaimableBytes > rhs.reclaimableBytes
        }
        return lhs.skill.displayName.localizedStandardCompare(rhs.skill.displayName) == .orderedAscending
    }
}
