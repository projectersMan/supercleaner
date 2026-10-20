public enum AgentEnvironmentSection: String, CaseIterable, Sendable {
    case skills
    case mcp

    public var displayTitle: String {
        switch self {
        case .skills: "Skills"
        case .mcp: "MCP"
        }
    }
}

