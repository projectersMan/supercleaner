import CleanerCore
import Foundation

func runReviewInteractionContracts() {
    let first = UUID()
    let second = UUID()
    let hidden = UUID()

    var state = ReviewFocusState(focusedCandidateID: hidden)
    state.reconcile(visibleIDs: [first, second])
    require(state.focusedCandidateID == first, "invisible focus must move to first visible candidate")

    state.focus(second, visibleIDs: [first, second])
    require(state.focusedCandidateID == second, "visible row focus must be retained")

    state.focus(hidden, visibleIDs: [first, second])
    require(state.focusedCandidateID == first, "hidden candidate cannot become focused")

    state.reconcile(visibleIDs: [])
    require(state.focusedCandidateID == nil, "empty visible list must clear focus")

    require(
        DirectoryRowInteraction.action(clickCount: 1, kind: .directory, hasChildren: true) == .selectAndToggleExpansion,
        "single-clicking a directory must select it and toggle expansion"
    )
    require(
        DirectoryRowInteraction.action(clickCount: 2, kind: .directory, hasChildren: true) == .selectAndToggleExpansion,
        "double-clicking a non-empty directory must select it and toggle expansion"
    )
    require(
        DirectoryRowInteraction.action(clickCount: 2, kind: .file, hasChildren: false) == .select,
        "double-clicking a file must not attempt directory expansion"
    )
    require(
        DirectoryRowInteraction.action(clickCount: 2, kind: .directory, hasChildren: false) == .select,
        "double-clicking an empty directory must not create a false expanded state"
    )
    runLargeFileSortingContracts()
}

private func runLargeFileSortingContracts() {
    func file(_ path: String, bytes: UInt64) -> DiskUsageNode {
        DiskUsageNode(
            url: URL(fileURLWithPath: path), kind: .file,
            ownBytes: bytes, recursiveBytes: bytes, childCount: 0,
            modifiedAt: Date(timeIntervalSince1970: 1), isReadable: true, children: .loaded([])
        )
    }
    let largest = file("/Users/tester/z-project/large.bin", bytes: 900)
    let smaller = file("/Users/tester/a-project/small.bin", bytes: 100)
    let middle = file("/Users/tester/a-project/middle.bin", bytes: 300)
    let tied = file("/Users/tester/a-project/other.bin", bytes: 300)
    let nodes = [smaller, largest, tied, middle]
    let selected: Set<URL> = [smaller.url]
    let sizeOrder = LargeFileSortOrder.size.sorted(nodes)
    require(sizeOrder.map(\.id) == [largest.id, middle.id, tied.id, smaller.id], "size order must descend by bytes with a deterministic path tie-breaker")
    require(
        LargeFileSortOrder.size.sorted(nodes, selectedFileURLs: selected).map(\.id) == sizeOrder.map(\.id),
        "checking a smaller file must not move rows in size order"
    )
    let directoryOrder = LargeFileSortOrder.directory.sorted(nodes)
    require(
        directoryOrder.map(\.id) == [middle.id, tied.id, smaller.id, largest.id],
        "directory order must keep files from the same parent together and order each directory by size"
    )
    require(
        LargeFileSortOrder.directory.sorted(nodes, selectedFileURLs: selected).map(\.id) == directoryOrder.map(\.id),
        "checking a file must not move rows in directory order"
    )
    require(
        LargeFileSortOrder.selection.sorted(nodes, selectedFileURLs: selected).first?.id == smaller.id,
        "selection order must explicitly bring checked files to the top"
    )
    let parent = DiskUsageNode(
        url: smaller.url.deletingLastPathComponent(), kind: .directory,
        ownBytes: 0, recursiveBytes: 100, childCount: 1,
        modifiedAt: Date(timeIntervalSince1970: 1), isReadable: true, children: .loaded([smaller])
    )
    require(
        LargeFileSortOrder.selection.sorted([largest, parent], selectedFileURLs: selected).first?.id == parent.id,
        "selection order must also prioritize directories containing checked descendants"
    )
    require(
        LargeFileSortOrder.size.sorted(nodes, selectedFileURLs: selected).map(\.id) == sizeOrder.map(\.id),
        "switching back from selection order must restore size order"
    )
}
