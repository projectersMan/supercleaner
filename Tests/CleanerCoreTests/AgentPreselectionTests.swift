import Foundation
import XCTest
@testable import CleanerCore

final class AgentPreselectionTests: XCTestCase {
    func testUniqueCacheIsKeptWithoutCoverageOrIndex() {
        XCTAssertTrue(AgentOverlapAnalyzer.preselectedSourceIDs(index: .init(), activeIDs: ["cache"],
            eligibleIDs: ["cache"], cacheIDs: ["cache"], manuallySelectedIDs: [], retainedIDs: [], threshold: 0.85).isEmpty)
    }

    func testCacheDuplicatesKeepAtLeastOneActualSource() {
        let index = duplicateIndex(["cache-a", "cache-b", "cache-c"])
        let selected = select(index, cache: Set(index.entries.keys))
        XCTAssertEqual(selected.count, 2)
        for source in selected {
            XCTAssertNotNil(AgentOverlapAnalyzer.supportingTargets(for: source,
                allowedIDs: Set(index.entries.keys).subtracting(selected), preferredIDs: [], threshold: 0.85, index: index))
        }
    }

    func testManualDeletionCannotSupplyCoverage() {
        let index = duplicateIndex(["cache", "manual"])
        XCTAssertTrue(select(index, cache: ["cache"], manual: ["manual"]).isEmpty)
    }

    func testGlobalResourcesStayAndCacheIsChosenFirst() {
        for kind in [AgentOverlapKind.skill, .mcp] {
            var index = duplicateIndex(["a-global", "b-project", "z-cache"])
            for id in index.entries.keys {
                let old = index.entries[id]!
                index.entries[id] = .init(id: id, cacheID: old.cacheID, kind: kind, title: id,
                    featureTexts: old.featureTexts, featureVectors: old.featureVectors, platform: .codex)
            }
            let active = Set(index.entries.keys)
            let selected = AgentOverlapAnalyzer.preselectedSourceIDs(index: index, activeIDs: active,
                eligibleIDs: active, cacheIDs: ["z-cache"], manuallySelectedIDs: [], retainedIDs: [],
                threshold: 0.85, globalIDs: ["a-global"])
            XCTAssertEqual(selected, ["b-project", "z-cache"])
            XCTAssertTrue(select(index, cache: ["z-cache"], manual: ["a-global", "b-project"]).isEmpty)
        }
    }

    func testCacheNeverBecomesKeeperInsteadOfProjectCopy() {
        let index = duplicateIndex(["a-project", "z-cache"])
        XCTAssertEqual(select(index, cache: ["z-cache"]), ["z-cache"])
    }

    func testExplicitKeepAndIneligibleCopiesAreNeverSelected() {
        let index = duplicateIndex(["a", "b"])
        XCTAssertEqual(AgentOverlapAnalyzer.preselectedSourceIDs(index: index, activeIDs: ["a", "b"],
            eligibleIDs: ["b"], cacheIDs: ["a", "b"], manuallySelectedIDs: [], retainedIDs: ["a"], threshold: 0.85), ["b"])
    }

    private func select(_ index: AgentOverlapIndex, cache: Set<String> = [], manual: Set<String> = []) -> Set<String> {
        let active = Set(index.entries.keys)
        return AgentOverlapAnalyzer.preselectedSourceIDs(index: index, activeIDs: active, eligibleIDs: active,
            cacheIDs: cache, manuallySelectedIDs: manual, retainedIDs: [], threshold: 0.85)
    }

    private func duplicateIndex(_ ids: [String]) -> AgentOverlapIndex {
        var index = AgentOverlapIndex()
        for (position, id) in ids.enumerated() {
            index.entries[id] = .init(id: id, cacheID: position, kind: .skill, title: id,
                featureTexts: ["Search source files"], featureVectors: [[1, 0]])
        }
        for first in ids.indices {
            for second in ids.indices where first < second {
                index.matches["\(first):\(second)"] = .init(firstID: ids[first], secondID: ids[second],
                    firstCovered: Data([1]), secondCovered: Data([1]))
            }
        }
        return index
    }
}
