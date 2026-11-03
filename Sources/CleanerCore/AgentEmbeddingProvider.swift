public protocol AgentEmbeddingProvider: Sendable {
    func embed(_ texts: [String]) async throws -> [[Float]]
}
