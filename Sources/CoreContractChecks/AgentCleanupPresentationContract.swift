import CleanerCore
import Foundation

func runAgentCleanupPresentationContracts() {
    let assets = (0..<20_000).map { index in
        let candidate = CleanupCandidate(
            url: URL(fileURLWithPath: "/Users/tester/cache/item-\(index)"),
            displayName: "Cache \(index)", category: .developerCache, bytes: 100,
            risk: .safe, evidence: [],
            identity: FileIdentity(device: 1, inode: UInt64(index), size: 100, modificationTime: 1, kind: .file),
            source: .agentWorkspace, lastAccessDate: nil, isActive: false
        )
        return AgentAssetRecord(
            candidate: candidate, provider: index.isMultiple(of: 2) ? .codex : .claude,
            scope: index.isMultiple(of: 3) ? .project : .global,
            resourceKind: index.isMultiple(of: 5) ? .skill : .buildCache,
            activity: index.isMultiple(of: 7) ? .active : .completed,
            cleanupEligibility: index.isMultiple(of: 5) ? .protected : .recommended,
            cleanupUnitURL: candidate.url
        )
    }
    let empty = AgentCleanupPresentation(assets: assets, provider: nil)
    require(empty.groups.isEmpty, "no platform selection must expose no cleanup content")
    let snapshot = AgentCleanupPresentation(assets: assets, provider: .codex)
    let expected = assets.filter {
        $0.provider == .codex && $0.cleanupEligibility == .recommended && $0.activity != .active
    }
    require(snapshot.assetCount == expected.count, "cleanup presentation must contain only eligible inactive assets from the selected platform")
    require(snapshot.resourceKinds(scope: nil) == [.buildCache], "protected resource types must not appear in cleanup filters")
    require(snapshot.groups.flatMap(\.assets).allSatisfy { $0.provider == .codex }, "platforms must remain isolated")
    require(snapshot.filteredGroups(scope: nil, kind: nil) == snapshot.groups, "the unfiltered Agent view must expose every cleanup group")
    require(snapshot.filteredGroups(scope: .shared, kind: nil).isEmpty, "unavailable cleanup scopes must return no groups")
    let projectGroups = snapshot.filteredGroups(scope: .project, kind: .buildCache)
    require(projectGroups.allSatisfy { $0.scope == .project && $0.resourceKind == .buildCache }, "cleanup filters must select matching groups")
    require(snapshot.groups.reduce(0) { $0 + $1.bytes } == UInt64(expected.count * 100), "cleanup totals must match eligible assets")
    let start = Date()
    for _ in 0..<1_000 {
        require(!snapshot.filteredGroups(scope: .project, kind: .buildCache).isEmpty, "cached filter must retain project cache")
    }
    print("Agent cached filters: \(Date().timeIntervalSince(start)) seconds for 1,000 updates / 20,000 source assets")
}

func runAgentSkillPresentationPerformanceContract() {
    let skillCount = 300
    let assetCount = 20_000
    let skills = (0..<skillCount).map { index in
        let root = URL(fileURLWithPath: "/Users/tester/.agents/skills/skill-\(index)", isDirectory: true)
        return SkillCatalogEntry(
            id: root.path,
            logicalID: "skill \(index)",
            provider: .codex,
            scope: .global,
            source: .userInstalled,
            kind: .workflow,
            skillRootURL: root,
            manifestURL: root.appendingPathComponent("SKILL.md"),
            displayName: "Skill \(index)",
            summary: nil,
            tags: [],
            triggers: [],
            tools: [],
            pluginName: nil,
            registryName: nil,
            pluginVersion: nil,
            parseStatus: .manifestParsed,
            sourceAssetURLs: [root]
        )
    }
    let assets = (0..<assetCount).map { index in
        let skillIndex = index % skillCount
        let url = URL(fileURLWithPath: "/Users/tester/.agents/skills/skill-\(skillIndex)/cache/item-\(index)")
        let candidate = CleanupCandidate(
            url: url,
            displayName: "Item \(index)",
            category: .agentSandbox,
            bytes: 100,
            risk: .review,
            evidence: [],
            identity: FileIdentity(device: 1, inode: UInt64(index + 1), size: 100, modificationTime: 1, kind: .file),
            source: .agentWorkspace,
            lastAccessDate: nil,
            isActive: false
        )
        return AgentAssetRecord(
            candidate: candidate,
            provider: .codex,
            scope: .global,
            resourceKind: .buildCache,
            activity: .completed,
            cleanupEligibility: .retained,
            cleanupUnitURL: url
        )
    }
    let start = Date()
    let presentation = AgentSkillCatalogPresentation(skills: skills, assets: assets, selectedIDs: [])
    let elapsed = Date().timeIntervalSince(start)
    require(presentation.bindingsByID.count == skillCount, "Skill presentation must retain every Skill")
    require(
        presentation.bindingsByID.values.reduce(0) { $0 + $1.linkedAssets.count } == assetCount,
        "Skill presentation must associate every nested asset exactly once"
    )
    require(elapsed < 2, "Skill presentation must remain interactive for 300 Skills / 20,000 assets (elapsed: \(elapsed)s)")
    print("Agent Skill presentation: \(elapsed) seconds for \(skillCount) Skills / \(assetCount) assets")
}
