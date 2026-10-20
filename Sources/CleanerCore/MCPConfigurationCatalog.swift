import Foundation

public enum MCPTransportKind: String, Codable, Hashable, Sendable, CaseIterable {
    case stdio
    case http
    case sse
    case webSocket
    case sdk
    case unknown
}

public enum MCPConfigurationParseStatus: String, Codable, Hashable, Sendable {
    case parsed
    case noServers
    case unreadable
    case malformed
}

public struct MCPServerSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { [projectPath ?? "", name].joined(separator: "|") }
    public let name: String
    public let transport: MCPTransportKind
    public let projectPath: String?

    public init(name: String, transport: MCPTransportKind, projectPath: String? = nil) {
        self.name = name
        self.transport = transport
        self.projectPath = projectPath
    }
}

public struct MCPConfigurationRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { fileURL.path }
    public let provider: AgentProvider
    public let scope: AgentScope
    public let fileURL: URL
    public let sourceLabel: String
    public let parseStatus: MCPConfigurationParseStatus
    public let servers: [MCPServerSummary]

    public init(
        provider: AgentProvider,
        scope: AgentScope,
        fileURL: URL,
        sourceLabel: String,
        parseStatus: MCPConfigurationParseStatus,
        servers: [MCPServerSummary]
    ) {
        self.provider = provider
        self.scope = scope
        self.fileURL = fileURL.standardizedFileURL
        self.sourceLabel = sourceLabel
        self.parseStatus = parseStatus
        self.servers = servers
    }
}

public enum MCPConfigurationCatalogSupport {
    private static let maximumConfigurationBytes = 512 * 1_024

    public static func makeRecord(
        provider: AgentProvider,
        scope: AgentScope,
        url: URL,
        homeDirectory: URL,
        fileSystem: any FileSystemAccess
    ) async -> MCPConfigurationRecord? {
        guard isSupportedConfiguration(url: url) else { return nil }
        let rule = AgentResourcePathRegistry.matchingRule(for: url, homeDirectory: homeDirectory)
        let sourceLabel = rule?.sourceLabel ?? inferredSourceLabel(url: url, provider: provider)
        let text: String
        do {
            text = try await fileSystem.readText(at: url, maximumBytes: maximumConfigurationBytes)
        } catch {
            return MCPConfigurationRecord(
                provider: provider,
                scope: scope,
                fileURL: url,
                sourceLabel: sourceLabel,
                parseStatus: .unreadable,
                servers: []
            )
        }
        let result = url.pathExtension.lowercased() == "toml"
            ? parseTOML(text)
            : parseJSON(text)
        return MCPConfigurationRecord(
            provider: provider,
            scope: scope,
            fileURL: url,
            sourceLabel: sourceLabel,
            parseStatus: result.status,
            servers: result.servers
        )
    }

    public static func isSupportedConfiguration(url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if [".mcp.json", "mcp.json", "managed-mcp.json", "claude_desktop_config.json", ".claude.json"].contains(name) {
            return true
        }
        return name == "config.toml" && url.pathComponents.map { $0.lowercased() }.contains(".codex")
    }

    private static func parseTOML(_ text: String) -> (status: MCPConfigurationParseStatus, servers: [MCPServerSummary]) {
        var transports: [String: MCPTransportKind] = [:]
        var currentServer: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[mcp_servers."), line.hasSuffix("]") {
                let body = String(line.dropFirst("[mcp_servers.".count).dropLast())
                let name = body.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
                currentServer = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let currentServer, !currentServer.isEmpty, transports[currentServer] == nil {
                    transports[currentServer] = .unknown
                }
                continue
            }
            guard let currentServer else { continue }
            if line.hasPrefix("command") { transports[currentServer] = .stdio }
            else if line.hasPrefix("url") { transports[currentServer] = .http }
        }
        let servers = transports.keys.sorted().map { MCPServerSummary(name: $0, transport: transports[$0] ?? .unknown) }
        return (servers.isEmpty ? .noServers : .parsed, servers)
    }

    private static func parseJSON(_ text: String) -> (status: MCPConfigurationParseStatus, servers: [MCPServerSummary]) {
        guard let data = text.data(using: .utf8) else { return (.malformed, []) }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { return (.malformed, []) }
        guard let root = object as? [String: Any] else { return (.malformed, []) }
        var summaries: [MCPServerSummary] = []
        appendServers(from: root["mcpServers"], projectPath: nil, to: &summaries)
        appendManagedServers(from: root["managedMcpServers"], to: &summaries)
        if let projects = root["projects"] as? [String: Any] {
            for projectPath in projects.keys.sorted() {
                guard let project = projects[projectPath] as? [String: Any] else { continue }
                appendServers(from: project["mcpServers"], projectPath: projectPath, to: &summaries)
            }
        }
        var seen = Set<String>()
        summaries = summaries.filter { seen.insert([tryString($0.projectPath), $0.name].joined(separator: "|" )).inserted }
        return (summaries.isEmpty ? .noServers : .parsed, summaries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private static func appendServers(from value: Any?, projectPath: String?, to summaries: inout [MCPServerSummary]) {
        guard let servers = value as? [String: Any] else { return }
        for name in servers.keys.sorted() {
            let definition = servers[name] as? [String: Any] ?? [:]
            summaries.append(MCPServerSummary(name: name, transport: transport(from: definition), projectPath: projectPath))
        }
    }

    private static func appendManagedServers(from value: Any?, to summaries: inout [MCPServerSummary]) {
        if let servers = value as? [String: Any] {
            appendServers(from: servers, projectPath: nil, to: &summaries)
            return
        }
        guard let servers = value as? [[String: Any]] else { return }
        for server in servers {
            guard let name = server["name"] as? String, !name.isEmpty else { continue }
            summaries.append(MCPServerSummary(name: name, transport: transport(from: server)))
        }
    }

    private static func transport(from definition: [String: Any]) -> MCPTransportKind {
        if let type = (definition["type"] as? String)?.lowercased() {
            switch type {
            case "stdio": return .stdio
            case "http", "streamable-http": return .http
            case "sse": return .sse
            case "ws", "websocket": return .webSocket
            case "sdk": return .sdk
            default: break
            }
        }
        if definition["command"] != nil { return .stdio }
        if definition["url"] != nil { return .http }
        return .unknown
    }

    private static func inferredSourceLabel(url: URL, provider: AgentProvider) -> String {
        if url.path.contains("/plugins/") { return "\(provider.rawValue) plugin MCP configuration" }
        return "\(provider.rawValue) MCP configuration"
    }

    private static func tryString(_ value: String?) -> String { value ?? "" }
}
