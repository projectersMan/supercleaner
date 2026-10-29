import Foundation

public struct SystemCleanupApplicationGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let candidates: [CleanupCandidate]
    public var bytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }
    public var kinds: [String] { Set(candidates.map { Self.kind(for: $0) }).sorted() }

    public static func kind(for candidate: CleanupCandidate) -> String { candidate.cleanupApplication?.kind ?? L10n.text("其它清理项") }

    public static func groups(_ candidates: [CleanupCandidate]) -> [Self] {
        Dictionary(grouping: candidates) { $0.cleanupApplication?.bundleIdentifier ?? "system-and-unassigned" }
            .map { id, items in
                Self(id: id, title: items.first?.cleanupApplication?.name ?? L10n.text("系统与其它应用"),
                     candidates: items.sorted { $0.bytes > $1.bytes })
            }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
    }
}
