import CleanerCore
import Foundation

/// Group by shared directory structure, without a count or depth quota.
/// Recommendations are disjoint; searching filters an already chosen partition.
struct LargeFileDirectorySection: Identifiable {
    let directory: URL?
    let files: [DiskUsageNode]

    var id: String { directory?.path ?? "recommended" }
    var title: String { directory?.path ?? L10n.text("建议清理") }

    static func collapsedIDs(for sections: [Self], expanded: Bool) -> Set<String> {
        expanded ? [] : Set(sections.map(\.id))
    }

    func selectableCandidates(from candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        let readable = Set(files.filter { $0.kind == .file && $0.isReadable }.map(\.id))
        return candidates.filter { $0.identity.kind == .file && $0.risk.isSelectable && readable.contains($0.url.standardizedFileURL) }
    }

    static func sections(files: [DiskUsageNode], home: URL, recommendedURLs: Set<URL>, query: String) -> [Self] {
        var seen = Set<URL>()
        let unique = files.filter { $0.kind == .file && seen.insert($0.id).inserted }
        let recommended = unique.filter { recommendedURLs.contains($0.id) }
        let remaining = unique.filter { !recommendedURLs.contains($0.id) }
        var sections = recommended.isEmpty ? [] : [Self(directory: nil, files: ordered(recommended))]
        sections += clustered(remaining, home: home)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            let matches = section.files.filter { $0.url.path.localizedCaseInsensitiveContains(query) }
            return matches.isEmpty ? nil : Self(directory: section.directory, files: matches)
        }
    }

    private static func clustered(_ files: [DiskUsageNode], home: URL) -> [Self] {
        let home = home.standardizedFileURL
        // Keep independent home branches separate: Documents and Library must
        // never become one "home" cluster just because they contain few files.
        let anchors = Dictionary(grouping: files) { anchor(for: $0.url, home: home) }
        var sections: [Self] = []
        for (url, files) in anchors {
            let root = LargeFileDirectoryBranch(url: url)
            for file in files { root.insert(file) }
            sections += partition(root, homeDepth: home.pathComponents.count).sections
        }
        return sections.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private static func anchor(for file: URL, home: URL) -> URL {
        let parent = file.deletingLastPathComponent()
        guard parent.path.hasPrefix(home.path + "/") else { return parent }
        return home.appendingPathComponent(parent.pathComponents[home.pathComponents.count], isDirectory: true)
    }

    private static func partition(_ branch: LargeFileDirectoryBranch, homeDepth: Int) -> LargeFileDirectoryPartition {
        let children = branch.children.values.sorted { $0.url.path < $1.url.path }
            .map { partition($0, homeDepth: homeDepth) }
        if branch.files.isEmpty, children.count == 1 { return children[0] }
        let files = branch.files + children.flatMap(\.files)
        let merged = group(files)
        var best = LargeFileDirectoryPartition(files: files, sections: [merged], cost: cost(merged, homeDepth: homeDepth))

        var separate = children.flatMap(\.sections)
        if !branch.files.isEmpty { separate.append(group(branch.files)) }
        best = preferred(best, sections: separate, homeDepth: homeDepth)

        // A child earns its own cluster only when its shared prefix saves more
        // repeated path structure than its headings add. Sparse siblings stay
        // together; no unrelated files are assigned to a child's directory.
        let depth = branch.url.pathComponents.count
        var promoted: [Self] = []
        var residual = branch.files
        for child in children {
            let contribution = child.files.reduce(0) { $0 + $1.url.pathComponents.count - depth }
            if child.cost < contribution { promoted += child.sections }
            else { residual += child.files }
        }
        if !residual.isEmpty { promoted.append(group(residual)) }
        return preferred(best, sections: promoted, homeDepth: homeDepth)
    }

    private static func preferred(_ current: LargeFileDirectoryPartition, sections: [Self], homeDepth: Int) -> LargeFileDirectoryPartition {
        guard !sections.isEmpty else { return current }
        let total = sections.reduce(0) { $0 + cost($1, homeDepth: homeDepth) }
        guard total < current.cost || (total == current.cost && sections.count < current.sections.count) else { return current }
        return LargeFileDirectoryPartition(files: current.files, sections: sections, cost: total)
    }

    /// Description length in path components: name each heading once, then the
    /// file paths relative to it. Names' character lengths do not bias grouping.
    private static func cost(_ section: Self, homeDepth: Int) -> Int {
        let depth = section.directory!.pathComponents.count
        let heading = max(0, depth - homeDepth) + 1
        return heading + section.files.reduce(0) { $0 + $1.url.pathComponents.count - depth }
    }

    private static func group(_ files: [DiskUsageNode]) -> Self {
        var components = files[0].url.deletingLastPathComponent().pathComponents
        for file in files.dropFirst() {
            let other = file.url.deletingLastPathComponent().pathComponents
            components = Array(zip(components, other).prefix { $0 == $1 }.map { $0.0 })
        }
        return Self(directory: URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true), files: ordered(files))
    }

    private static func ordered(_ files: [DiskUsageNode]) -> [DiskUsageNode] {
        files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
}

private struct LargeFileDirectoryPartition {
    let files: [DiskUsageNode]
    let sections: [LargeFileDirectorySection]
    let cost: Int
}

private final class LargeFileDirectoryBranch {
    let url: URL
    var files: [DiskUsageNode] = []
    var children: [String: LargeFileDirectoryBranch] = [:]

    init(url: URL) { self.url = url }

    func insert(_ file: DiskUsageNode) {
        var branch = self
        let components = file.url.deletingLastPathComponent().pathComponents.dropFirst(url.pathComponents.count)
        for component in components {
            if let child = branch.children[component] { branch = child }
            else {
                let child = LargeFileDirectoryBranch(url: branch.url.appendingPathComponent(component, isDirectory: true))
                branch.children[component] = child
                branch = child
            }
        }
        branch.files.append(file)
    }
}
