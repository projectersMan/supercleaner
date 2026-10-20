import Foundation

public struct AgentCatalogGroup: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let icon: String
    public let sortOrder: Int
    public let isInferred: Bool

    public init(
        id: String,
        title: String,
        icon: String,
        sortOrder: Int,
        isInferred: Bool
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.sortOrder = sortOrder
        self.isInferred = isInferred
    }
}

public enum AgentCatalogRegistry {
    public static let shared = AgentCatalogRegistryStore()
}

public struct AgentCatalogRegistryStore: Sendable {
    public init() {}

    public func group(for skill: SkillCatalogEntry) -> AgentCatalogGroup {
        let inferred = inferGroup(for: skill)
        return AgentCatalogGroup(
            id: inferred.id,
            title: inferred.title,
            icon: inferred.icon,
            sortOrder: inferred.sortOrder,
            isInferred: true
        )
    }

    private func inferGroup(for skill: SkillCatalogEntry) -> AgentCatalogGroup {
        let candidates = inferredNameCandidates(for: skill)
        let rawName = candidates.first(where: { !$0.isEmpty }) ?? skill.provider.rawValue
        let normalizedTitle = prettyTitle(rawName)
        let normalizedID = normalizedTitle
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return AgentCatalogGroup(
            id: normalizedID.isEmpty ? "other" : normalizedID,
            title: normalizedTitle.isEmpty ? L10n.text("其他") : normalizedTitle,
            icon: inferredIcon(for: normalizedTitle),
            sortOrder: 10_000,
            isInferred: true
        )
    }

    private func inferredNameCandidates(for skill: SkillCatalogEntry) -> [String] {
        let path = skill.skillRootURL.standardizedFileURL.pathComponents
        let lowerComponents = path.map { $0.lowercased() }
        var results: [String] = []
        if let hiddenRoot = path.first(where: { $0.hasPrefix(".") && $0.count > 1 }) {
            results.append(hiddenRoot.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        if let supportIndex = lowerComponents.lastIndex(of: "application support"), supportIndex + 1 < path.count {
            results.append(path[supportIndex + 1])
        }
        if let pluginsIndex = lowerComponents.lastIndex(of: "plugins"), pluginsIndex > 0 {
            results.append(path[pluginsIndex - 1])
        }
        if let skillsIndex = lowerComponents.lastIndex(of: "skills"), skillsIndex > 0 {
            results.append(path[skillsIndex - 1])
        }
        if let librariesIndex = lowerComponents.lastIndex(of: "design_libraries"), librariesIndex > 0 {
            results.append(path[librariesIndex - 1])
        }
        results.append(skill.provider.rawValue)
        return results.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func prettyTitle(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !stripped.isEmpty else { return "" }
        return stripped
            .split(separator: " ")
            .map { segment in
                let text = String(segment)
                if text.uppercased() == text {
                    return text
                }
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    private func inferredIcon(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("global") || lower.contains("shared") {
            return "globe"
        }
        if lower.contains("git") {
            return "arrow.triangle.branch"
        }
        if lower.contains("mcp") {
            return "point.3.connected.trianglepath.dotted"
        }
        return "tray.full"
    }
}
