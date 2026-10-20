import Foundation

public enum SkillCatalogSource: String, Codable, Hashable, Sendable, CaseIterable {
    case builtin
    case plugin
    case userInstalled
    case shared
    case extensionSupport
    case project
    case unknown
}

public enum SkillCatalogKind: String, Codable, Hashable, Sendable, CaseIterable {
    case workflow
    case designLibrary
    case extensionSupport
    case projectSkill
    case unknown
}

public enum SkillMetadataParseStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case manifestParsed
    case headingFallback
    case pathFallback
}

public struct SkillCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let logicalID: String
    public let provider: AgentProvider
    public let scope: AgentScope
    public let source: SkillCatalogSource
    public let kind: SkillCatalogKind
    public let skillRootURL: URL
    public let manifestURL: URL?
    public let displayName: String
    public let summary: String?
    public let tags: [String]
    public let triggers: [String]
    public let tools: [String]
    public let pluginName: String?
    public let registryName: String?
    public let pluginVersion: String?
    public let parseStatus: SkillMetadataParseStatus
    public let sourceAssetURLs: [URL]

    public init(
        id: String,
        logicalID: String,
        provider: AgentProvider,
        scope: AgentScope,
        source: SkillCatalogSource,
        kind: SkillCatalogKind,
        skillRootURL: URL,
        manifestURL: URL?,
        displayName: String,
        summary: String?,
        tags: [String],
        triggers: [String],
        tools: [String],
        pluginName: String?,
        registryName: String?,
        pluginVersion: String?,
        parseStatus: SkillMetadataParseStatus,
        sourceAssetURLs: [URL]
    ) {
        self.id = id
        self.logicalID = logicalID
        self.provider = provider
        self.scope = scope
        self.source = source
        self.kind = kind
        self.skillRootURL = skillRootURL.standardizedFileURL
        self.manifestURL = manifestURL?.standardizedFileURL
        self.displayName = displayName
        self.summary = summary
        self.tags = SkillCatalogSupport.uniqueStrings(tags)
        self.triggers = SkillCatalogSupport.uniqueStrings(triggers)
        self.tools = SkillCatalogSupport.uniqueStrings(tools)
        self.pluginName = pluginName
        self.registryName = registryName
        self.pluginVersion = pluginVersion
        self.parseStatus = parseStatus
        self.sourceAssetURLs = SkillCatalogSupport.uniqueURLs(sourceAssetURLs)
    }

    public func merged(with other: SkillCatalogEntry) -> SkillCatalogEntry {
        let preferred = SkillCatalogSupport.preferred(self, other)
        let fallback = preferred.id == id ? other : self
        return SkillCatalogEntry(
            id: preferred.id,
            logicalID: preferred.logicalID,
            provider: preferred.provider,
            scope: preferred.scope,
            source: preferred.source,
            kind: preferred.kind,
            skillRootURL: preferred.skillRootURL,
            manifestURL: preferred.manifestURL ?? fallback.manifestURL,
            displayName: preferred.displayName,
            summary: preferred.summary ?? fallback.summary,
            tags: preferred.tags + fallback.tags,
            triggers: preferred.triggers + fallback.triggers,
            tools: preferred.tools + fallback.tools,
            pluginName: preferred.pluginName ?? fallback.pluginName,
            registryName: preferred.registryName ?? fallback.registryName,
            pluginVersion: preferred.pluginVersion ?? fallback.pluginVersion,
            parseStatus: preferred.parseStatus,
            sourceAssetURLs: preferred.sourceAssetURLs + fallback.sourceAssetURLs
        )
    }

    public func matches(query: String) -> Bool {
        let normalizedQuery = SkillCatalogSupport.normalizedSearchToken(query)
        if normalizedQuery.isEmpty {
            return true
        }
        let haystacks = [
            displayName,
            summary ?? "",
            logicalID,
            provider.rawValue,
            scope.rawValue,
            source.rawValue,
            kind.rawValue,
            pluginName ?? "",
            registryName ?? "",
            pluginVersion ?? "",
            skillRootURL.path,
            manifestURL?.path ?? "",
            tags.joined(separator: " "),
            triggers.joined(separator: " "),
            tools.joined(separator: " "),
        ]
        return haystacks.contains { SkillCatalogSupport.normalizedSearchToken($0).contains(normalizedQuery) }
    }
}

public enum SkillCatalogSupport {
    static let maximumManifestBytes = 64 * 1_024
    private static let manifestNames = ["SKILL.md", "skill.md"]

    public static func makeEntry(
        provider: AgentProvider,
        scope: AgentScope,
        discoveredURL: URL,
        fileSystem: any FileSystemAccess
    ) async -> SkillCatalogEntry? {
        guard let location = await canonicalLocation(for: discoveredURL, fileSystem: fileSystem) else {
            return nil
        }
        let metadata = await readMetadata(
            rootURL: location.rootURL,
            manifestURL: location.manifestURL,
            fileSystem: fileSystem
        )
        let sourceInfo = inferSourceInfo(rootURL: location.rootURL)
        let displayName = metadata.displayName.isEmpty ? location.rootURL.lastPathComponent : metadata.displayName
        let logicalID = normalizedSearchToken(metadata.logicalID.isEmpty ? displayName : metadata.logicalID)
        return SkillCatalogEntry(
            id: location.rootURL.standardizedFileURL.path,
            logicalID: logicalID,
            provider: provider,
            scope: scope,
            source: sourceInfo.source,
            kind: sourceInfo.kind,
            skillRootURL: location.rootURL,
            manifestURL: location.manifestURL,
            displayName: displayName,
            summary: metadata.summary,
            tags: metadata.tags,
            triggers: metadata.triggers,
            tools: metadata.tools,
            pluginName: sourceInfo.pluginName,
            registryName: sourceInfo.registryName,
            pluginVersion: sourceInfo.pluginVersion,
            parseStatus: metadata.parseStatus,
            sourceAssetURLs: [discoveredURL.standardizedFileURL]
        )
    }

    public static func preferred(_ lhs: SkillCatalogEntry, _ rhs: SkillCatalogEntry) -> SkillCatalogEntry {
        let lhsScore = parseScore(lhs.parseStatus)
        let rhsScore = parseScore(rhs.parseStatus)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        if lhs.manifestURL != nil, rhs.manifestURL == nil {
            return lhs
        }
        if rhs.manifestURL != nil, lhs.manifestURL == nil {
            return rhs
        }
        let lhsSourceCount = lhs.sourceAssetURLs.count
        let rhsSourceCount = rhs.sourceAssetURLs.count
        if lhsSourceCount != rhsSourceCount {
            return lhsSourceCount > rhsSourceCount ? lhs : rhs
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending ? lhs : rhs
    }

    public static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedSearchToken($0)).inserted }
    }

    public static func uniqueURLs(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values
            .map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func normalizedSearchToken(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseScore(_ value: SkillMetadataParseStatus) -> Int {
        switch value {
        case .manifestParsed:
            return 3
        case .headingFallback:
            return 2
        case .pathFallback:
            return 1
        }
    }

    private static func canonicalLocation(
        for discoveredURL: URL,
        fileSystem: any FileSystemAccess
    ) async -> SkillCatalogLocation? {
        let standardizedURL = discoveredURL.standardizedFileURL
        let lowerComponents = standardizedURL.pathComponents.map { $0.lowercased() }
        if let rootURL = rootURL(from: standardizedURL, lowerComponents: lowerComponents) {
            let manifestURL = await locateManifestURL(rootURL: rootURL, discoveredURL: standardizedURL, fileSystem: fileSystem)
            return SkillCatalogLocation(rootURL: rootURL, manifestURL: manifestURL)
        }
        return nil
    }

    private static func rootURL(
        from discoveredURL: URL,
        lowerComponents: [String]
    ) -> URL? {
        if lowerComponents.isEmpty {
            return nil
        }
        if let index = lowerComponents.lastIndex(of: "skills"), index + 1 < discoveredURL.pathComponents.count {
            return url(from: discoveredURL, componentIndex: index + 1)
        }
        if let index = lowerComponents.lastIndex(of: "design_libraries"), index + 1 < discoveredURL.pathComponents.count {
            return url(from: discoveredURL, componentIndex: index + 1)
        }
        if discoveredURL.lastPathComponent.lowercased() == "skill.md" {
            return discoveredURL.deletingLastPathComponent()
        }
        return nil
    }

    private static func url(from url: URL, componentIndex: Int) -> URL {
        var result = URL(fileURLWithPath: "/", isDirectory: true)
        let components = url.standardizedFileURL.pathComponents
        for currentIndex in 1...componentIndex {
            result.appendPathComponent(
                components[currentIndex],
                isDirectory: true
            )
        }
        return result.standardizedFileURL
    }

    private static func locateManifestURL(
        rootURL: URL,
        discoveredURL: URL,
        fileSystem: any FileSystemAccess
    ) async -> URL? {
        if discoveredURL.lastPathComponent.lowercased() == "skill.md" {
            return discoveredURL.standardizedFileURL
        }
        let candidates = manifestNames.map { rootURL.appendingPathComponent($0) }
        for candidate in candidates {
            if await fileSystem.fileExists(candidate) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    private static func readMetadata(
        rootURL: URL,
        manifestURL: URL?,
        fileSystem: any FileSystemAccess
    ) async -> SkillCatalogMetadata {
        guard let manifestURL else {
            return SkillCatalogMetadata(
                displayName: rootURL.lastPathComponent,
                logicalID: rootURL.lastPathComponent,
                summary: nil,
                tags: [],
                triggers: [],
                tools: [],
                parseStatus: .pathFallback
            )
        }
        do {
            let rawText = try await fileSystem.readText(at: manifestURL, maximumBytes: maximumManifestBytes)
            let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = parseManifestText(trimmedText)
            return SkillCatalogMetadata(
                displayName: parsed.displayName.isEmpty ? rootURL.lastPathComponent : parsed.displayName,
                logicalID: parsed.logicalID.isEmpty ? rootURL.lastPathComponent : parsed.logicalID,
                summary: parsed.summary,
                tags: parsed.tags,
                triggers: parsed.triggers,
                tools: parsed.tools,
                parseStatus: parsed.parseStatus
            )
        } catch {
            return SkillCatalogMetadata(
                displayName: rootURL.lastPathComponent,
                logicalID: rootURL.lastPathComponent,
                summary: nil,
                tags: [],
                triggers: [],
                tools: [],
                parseStatus: .pathFallback
            )
        }
    }

    private static func parseManifestText(_ text: String) -> SkillCatalogMetadata {
        let frontMatter = parseFrontMatter(text)
        let body = frontMatter.body
        let heading = firstHeading(body)
        let paragraph = firstParagraph(body)
        let tags = frontMatter.tags + extractList(sectionTitles: ["标签", "tags"], from: body)
        let triggers = frontMatter.triggers + extractList(sectionTitles: ["快捷指令说明", "triggers", "trigger"], from: body)
        let tools = frontMatter.tools + extractList(sectionTitles: ["tools", "tool", "工具"], from: body)
        let summary = preferredSummary(frontMatter.summary, paragraph)
        let explicitName = preferredName(frontMatter.name, heading)
        let logicalID = explicitName.isEmpty ? heading : explicitName
        let parseStatus: SkillMetadataParseStatus = frontMatter.usedFrontMatter
            ? .manifestParsed
            : heading.isEmpty ? .pathFallback : .headingFallback
        return SkillCatalogMetadata(
            displayName: explicitName,
            logicalID: logicalID,
            summary: summary,
            tags: tags,
            triggers: triggers,
            tools: tools,
            parseStatus: parseStatus
        )
    }

    private static func parseFrontMatter(_ text: String) -> ParsedFrontMatter {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first == "---" else {
            return ParsedFrontMatter(body: text)
        }
        var frontMatterLines: [String] = []
        var index = 1
        while index < lines.count, lines[index] != "---" {
            frontMatterLines.append(lines[index])
            index += 1
        }
        guard index < lines.count else {
            return ParsedFrontMatter(body: text)
        }
        let body = lines.suffix(from: index + 1).joined(separator: "\n")
        let parsed = parseFrontMatterLines(frontMatterLines)
        return ParsedFrontMatter(
            body: body,
            name: parsed.name,
            summary: parsed.summary,
            tags: parsed.tags,
            triggers: parsed.triggers,
            tools: parsed.tools,
            usedFrontMatter: true
        )
    }

    private static func parseFrontMatterLines(_ lines: [String]) -> ParsedFrontMatter {
        var name = ""
        var summary: String?
        var tags: [String] = []
        var triggers: [String] = []
        var tools: [String] = []
        var activeArrayKey = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- "), !activeArrayKey.isEmpty {
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                updateArrayValue(key: activeArrayKey, value: value, tags: &tags, triggers: &triggers, tools: &tools)
                continue
            }
            activeArrayKey = ""
            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                continue
            }
            let rawKey = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rawValue == "[" || rawValue.isEmpty {
                activeArrayKey = rawKey
                continue
            }
            if rawKey == "name" || rawKey == "title" {
                name = unquote(rawValue)
                continue
            }
            if rawKey == "description" || rawKey == "summary" {
                summary = unquote(rawValue)
                continue
            }
            let values = parseArrayLiteral(rawValue)
            if !values.isEmpty {
                for value in values {
                    updateArrayValue(key: rawKey, value: value, tags: &tags, triggers: &triggers, tools: &tools)
                }
            }
        }
        return ParsedFrontMatter(
            body: "",
            name: name,
            summary: summary,
            tags: tags,
            triggers: triggers,
            tools: tools,
            usedFrontMatter: true
        )
    }

    private static func updateArrayValue(
        key: String,
        value: String,
        tags: inout [String],
        triggers: inout [String],
        tools: inout [String]
    ) {
        let cleaned = unquote(value)
        if cleaned.isEmpty {
            return
        }
        switch key {
        case "tag", "tags", "keyword", "keywords":
            tags.append(cleaned)
        case "trigger", "triggers", "shortcut", "shortcuts":
            triggers.append(cleaned)
        case "tool", "tools":
            tools.append(cleaned)
        default:
            break
        }
    }

    private static func parseArrayLiteral(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else {
            return []
        }
        let inner = String(trimmed.dropFirst().dropLast())
        if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return inner.split(separator: ",").map {
            unquote(String($0).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func firstHeading(_ body: String) -> String {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func firstParagraph(_ body: String) -> String? {
        let lines = body.components(separatedBy: .newlines)
        var paragraphLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !paragraphLines.isEmpty {
                    break
                }
                continue
            }
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix("```") {
                if !paragraphLines.isEmpty {
                    break
                }
                continue
            }
            paragraphLines.append(trimmed)
        }
        let paragraph = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return paragraph.isEmpty ? nil : paragraph
    }

    private static func extractList(sectionTitles: [String], from body: String) -> [String] {
        let lines = body.components(separatedBy: .newlines)
        var results: [String] = []
        var collecting = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = trimmed.lowercased()
            if sectionTitles.contains(where: { normalizedTitle.contains($0.lowercased()) && trimmed.hasPrefix("#") }) {
                collecting = true
                continue
            }
            if collecting, trimmed.hasPrefix("#") {
                break
            }
            if collecting, trimmed.hasPrefix("- ") {
                results.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return results
    }

    private static func preferredName(_ explicit: String, _ fallback: String) -> String {
        if !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preferredSummary(_ explicit: String?, _ fallback: String?) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func inferSourceInfo(rootURL: URL) -> SkillSourceInfo {
        let lowerComponents = rootURL.pathComponents.map { $0.lowercased() }
        if lowerComponents.contains("design_libraries") {
            return SkillSourceInfo(source: .builtin, kind: .designLibrary)
        }
        if let pluginsIndex = lowerComponents.lastIndex(of: "plugins"),
           pluginsIndex + 3 < rootURL.pathComponents.count {
            return SkillSourceInfo(
                source: .plugin,
                kind: .workflow,
                pluginName: rootURL.pathComponents[pluginsIndex + 2],
                registryName: rootURL.pathComponents[pluginsIndex + 1],
                pluginVersion: rootURL.pathComponents[pluginsIndex + 3]
            )
        }
        if lowerComponents.contains("builtin") || lowerComponents.contains("builtin_skills") {
            return SkillSourceInfo(source: .builtin, kind: .workflow)
        }
        if lowerComponents.contains("extensions") {
            return SkillSourceInfo(source: .extensionSupport, kind: .extensionSupport)
        }
        if lowerComponents.contains(".agents") {
            let kind: SkillCatalogKind = lowerComponents.contains(".claude") || lowerComponents.contains(".cursor")
                ? .projectSkill
                : .workflow
            return SkillSourceInfo(source: .shared, kind: kind)
        }
        if lowerComponents.contains(".claude") || lowerComponents.contains(".cursor") || lowerComponents.contains(".trae-cn") {
            return SkillSourceInfo(source: .userInstalled, kind: .workflow)
        }
        if lowerComponents.contains(".config"), lowerComponents.contains("kilo") {
            return SkillSourceInfo(source: .userInstalled, kind: .workflow)
        }
        return SkillSourceInfo(source: .unknown, kind: .unknown)
    }

    private static func unquote(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SkillCatalogLocation {
    let rootURL: URL
    let manifestURL: URL?
}

private struct SkillCatalogMetadata {
    let displayName: String
    let logicalID: String
    let summary: String?
    let tags: [String]
    let triggers: [String]
    let tools: [String]
    let parseStatus: SkillMetadataParseStatus
}

private struct SkillSourceInfo {
    let source: SkillCatalogSource
    let kind: SkillCatalogKind
    let pluginName: String?
    let registryName: String?
    let pluginVersion: String?

    init(
        source: SkillCatalogSource,
        kind: SkillCatalogKind,
        pluginName: String? = nil,
        registryName: String? = nil,
        pluginVersion: String? = nil
    ) {
        self.source = source
        self.kind = kind
        self.pluginName = pluginName
        self.registryName = registryName
        self.pluginVersion = pluginVersion
    }
}

private struct ParsedFrontMatter {
    let body: String
    let name: String
    let summary: String?
    let tags: [String]
    let triggers: [String]
    let tools: [String]
    let usedFrontMatter: Bool

    init(
        body: String,
        name: String = "",
        summary: String? = nil,
        tags: [String] = [],
        triggers: [String] = [],
        tools: [String] = [],
        usedFrontMatter: Bool = false
    ) {
        self.body = body
        self.name = name
        self.summary = summary
        self.tags = tags
        self.triggers = triggers
        self.tools = tools
        self.usedFrontMatter = usedFrontMatter
    }
}
