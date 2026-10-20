import Foundation

public struct DiskUsageSelectionState: Codable, Hashable, Sendable {
    public private(set) var selectedFileURLs: Set<URL>

    public init(selectedFileURLs: Set<URL> = []) {
        self.selectedFileURLs = Set(selectedFileURLs.map(\.standardizedFileURL))
    }

    public init(candidates: [CleanupCandidate], selectedIDs: Set<UUID>) {
        selectedFileURLs = Set(
            candidates
                .filter { selectedIDs.contains($0.id) }
                .map { $0.url.standardizedFileURL }
        )
    }

    public func selectedCandidateIDs(in candidates: [CleanupCandidate]) -> Set<UUID> {
        Set(candidates.filter { selectedFileURLs.contains($0.url.standardizedFileURL) }.map(\.id))
    }

    public mutating func toggle(_ node: DiskUsageNode) {
        guard node.kind == .file, node.isReadable else { return }
        let url = node.url.standardizedFileURL
        if selectedFileURLs.remove(url) == nil { selectedFileURLs.insert(url) }
    }
}
