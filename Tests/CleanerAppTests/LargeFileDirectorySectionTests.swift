import CleanerCore
import Foundation
import XCTest
@testable import CleanerApp

final class LargeFileDirectorySectionTests: XCTestCase {
    func testRecommendationsAppearOnceBeforeFlatDirectoryDescendants() {
        let recommended = file("/Users/tester/Downloads/setup.dmg")
        let direct = file("/Users/tester/code/data.bin")
        let nested = file("/Users/tester/code/project/output/deep.bin")
        let document = file("/Users/tester/Documents/book.pdf")
        let sections = LargeFileDirectorySection.sections(files: [nested, recommended, direct, document, nested],
            home: URL(fileURLWithPath: "/Users/tester"), recommendedURLs: [recommended.url], query: "")
        XCTAssertEqual(sections.map(\.id), ["recommended", "/Users/tester/code", "/Users/tester/Documents"])
        XCTAssertEqual(sections[0].files.map(\.id), [recommended.id])
        XCTAssertEqual(sections[1].files.map(\.id), [direct.id, nested.id])
        XCTAssertEqual(sections.flatMap(\.files).count, 4)
    }

    func testSearchMatchesNestedFullPathsAndOmitsEmptyGroups() {
        let nested = file("/Users/tester/code/project/output/deep.bin")
        let sections = LargeFileDirectorySection.sections(files: [file("/Users/tester/Downloads/setup.dmg"), nested],
            home: URL(fileURLWithPath: "/Users/tester"), recommendedURLs: [], query: " PROJECT/output ")
        XCTAssertEqual(sections.map(\.id), ["/Users/tester/code/project/output"])
        XCTAssertEqual(sections.flatMap(\.files).map(\.id), [nested.id])
    }

    func testHomeFilesAndSiblingPrefixesStayInTheirOwnDirectories() {
        let sections = LargeFileDirectorySection.sections(files: [file("/Users/tester/root.bin"), file("/Users/tester-other/data.bin")],
            home: URL(fileURLWithPath: "/Users/tester"), recommendedURLs: [], query: "")
        XCTAssertEqual(Set(sections.map(\.id)), ["/Users/tester", "/Users/tester-other"])
    }

    func testDenseBranchesSplitAtMeaningfulPathsAndSkipSingleChildChains() {
        let files = ["project-a", "project-b", "project-c"].flatMap { project in
            (0..<40).map { file("/Users/tester/code/\(project)/output/deep/file-\($0).bin") }
        }
        let sections = LargeFileDirectorySection.sections(files: files, home: URL(fileURLWithPath: "/Users/tester"),
            recommendedURLs: [], query: "")
        XCTAssertEqual(sections.map(\.id), ["project-a", "project-b", "project-c"].map { "/Users/tester/code/\($0)/output/deep" })
        XCTAssertTrue(sections.allSatisfy { $0.files.count == 40 })
    }

    func testSparseFoldersMergeInsteadOfCreatingOneHeadingPerDirectory() {
        let files = (0..<50).flatMap { directory in
            (0..<2).map { file("/Users/tester/code/project-\(directory)/file-\($0).bin") }
        }
        let sections = LargeFileDirectorySection.sections(files: files, home: URL(fileURLWithPath: "/Users/tester"),
            recommendedURLs: [], query: "")
        XCTAssertEqual(sections.map(\.id), ["/Users/tester/code"])
        XCTAssertEqual(sections[0].files.count, 100)
    }

    func testDominantBranchCanSplitWithoutLosingSparseAncestorFiles() {
        let files = ["project-a", "project-b"].flatMap { project in
            (0..<100).map { file("/Users/tester/code/\(project)/file-\($0).bin") }
        } + (0..<5).map { file("/Users/tester/misc/file-\($0).bin") }
        let sections = LargeFileDirectorySection.sections(files: files, home: URL(fileURLWithPath: "/Users/tester"),
            recommendedURLs: [], query: "")
        XCTAssertEqual(Set(sections.map(\.id)), ["/Users/tester/code/project-a", "/Users/tester/code/project-b", "/Users/tester/misc"])
        XCTAssertEqual(sections.flatMap(\.files).count, files.count)
        XCTAssertEqual(Set(sections.flatMap(\.files).map(\.id)).count, files.count)
    }

    func testDistinctCoherentBranchesHaveNoGroupLimitAndSearchKeepsPaths() {
        let files = (0..<30).flatMap { directory in
            (0..<20).map { file("/Users/tester/code/project-\(directory)/file-\($0).bin") }
        }
        let home = URL(fileURLWithPath: "/Users/tester")
        let sections = LargeFileDirectorySection.sections(files: files, home: home, recommendedURLs: [], query: "")
        let reversed = LargeFileDirectorySection.sections(files: files.reversed(), home: home, recommendedURLs: [], query: "")
        let filtered = LargeFileDirectorySection.sections(files: files, home: home, recommendedURLs: [], query: "project-29/")
        XCTAssertEqual(sections.count, 30)
        XCTAssertEqual(sections.map(\.id), reversed.map(\.id))
        XCTAssertEqual(sections.flatMap(\.files).map(\.id), reversed.flatMap(\.files).map(\.id))
        XCTAssertEqual(sections.flatMap(\.files).count, files.count)
        XCTAssertEqual(Set(sections.flatMap(\.files).map(\.id)).count, files.count)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, sections.first { $0.files.contains { $0.url.path.contains("project-29/") } }?.id)
        XCTAssertEqual(filtered.flatMap(\.files).count, 20)
    }

    func testUnrelatedHomeBranchesNeverMergeToMeetAGroupCount() {
        let files = [file("/Users/tester/Documents/a.bin"), file("/Users/tester/Library/b.bin")]
        let sections = LargeFileDirectorySection.sections(files: files, home: URL(fileURLWithPath: "/Users/tester"),
            recommendedURLs: [], query: "")
        XCTAssertEqual(sections.map(\.id), ["/Users/tester/Documents", "/Users/tester/Library"])
    }

    func testSparseSiblingsStayTogetherAlongsideAConcentratedBranch() {
        let dense = (0..<40).map { file("/Users/tester/code/project/output/deep/file-\($0).bin") }
        let sparse = (0..<10).map { file("/Users/tester/code/misc-\($0)/file.bin") }
        let sections = LargeFileDirectorySection.sections(files: dense + sparse, home: URL(fileURLWithPath: "/Users/tester"),
            recommendedURLs: [], query: "")
        XCTAssertEqual(sections.map(\.id), ["/Users/tester/code", "/Users/tester/code/project/output/deep"])
        XCTAssertEqual(sections.map { $0.files.count }, [10, 40])
        XCTAssertEqual(Set(sections.flatMap(\.files).map(\.id)).count, 50)
    }

    func testGroupSelectionExcludesProtectedUnreadableAndUnrepresentedFiles() {
        let manual = candidate("manual", risk: .review)
        let protected = candidate("protected", risk: .blocked)
        let unreadable = candidate("unreadable", risk: .review)
        let hidden = candidate("hidden", risk: .review)
        let unavailable = DiskUsageNode(url: unreadable.url, kind: .file, ownBytes: 100, recursiveBytes: 100,
            childCount: 0, modifiedAt: Date(timeIntervalSince1970: 0), isReadable: false, children: .loaded([]))
        let section = LargeFileDirectorySection(directory: URL(fileURLWithPath: "/Users/tester/code"),
            files: [file(manual.url.path), file(protected.url.path), unavailable])
        XCTAssertEqual(section.selectableCandidates(from: [manual, protected, unreadable, hidden]).map(\.id), [manual.id])
        XCTAssertTrue(section.selectableCandidates(from: [protected, unreadable, hidden]).isEmpty)
    }

    func testExpandAndCollapseAllUseCurrentSectionIDsOnly() {
        let sections = [
            LargeFileDirectorySection(directory: URL(fileURLWithPath: "/Users/tester/Documents"), files: [file("/Users/tester/Documents/a")]),
            LargeFileDirectorySection(directory: nil, files: [file("/Users/tester/Downloads/a")])
        ]
        XCTAssertTrue(LargeFileDirectorySection.collapsedIDs(for: sections, expanded: true).isEmpty)
        XCTAssertEqual(LargeFileDirectorySection.collapsedIDs(for: sections, expanded: false), Set(sections.map(\.id)))
    }

    private func candidate(_ name: String, risk: RiskLevel) -> CleanupCandidate {
        CleanupCandidate(url: URL(fileURLWithPath: "/Users/tester/code/" + name), displayName: name,
            category: .largeFile, bytes: 100, risk: risk, evidence: [],
            identity: .init(device: 1, inode: 1, size: 100, modificationTime: 1, kind: .file),
            source: .diskAnalysis, lastAccessDate: nil, isActive: false, requiresExplicitSelection: true)
    }

    private func file(_ path: String) -> DiskUsageNode {
        DiskUsageNode(url: URL(fileURLWithPath: path), kind: .file, ownBytes: 100, recursiveBytes: 100,
            childCount: 0, modifiedAt: Date(timeIntervalSince1970: 0), isReadable: true, children: .loaded([]))
    }
}
