import Foundation

public struct RuleUpdateService: Sendable {
    private let store: RuleStore
    private let configuration: ReleaseConfiguration
    private let transport: any UpdateTransport
    public init(store: RuleStore, configuration: ReleaseConfiguration, transport: any UpdateTransport = HTTPSUpdateTransport()) {
        self.store = store; self.configuration = configuration; self.transport = transport
    }
    public func update(progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }) async throws -> RulePack {
        try configuration.validate()
        guard let url = configuration.ruleUpdateURL, configuration.rulePublicKey?.count == 32 else { throw ReleaseConfigurationError.missing }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuperCleanerRuleUpdate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("signed-rules.json")
        let policy = UpdateDownloadPolicy(allowedHosts: configuration.allowedHosts, maximumBytes: 1_500_000)
        let result = try await transport.download(from: url, to: destination, policy: policy, progress: progress)
        try policy.validate(result.sourceURL)
        guard result.fileURL.standardizedFileURL.path == destination.standardizedFileURL.path, result.byteCount <= policy.maximumBytes else { throw UpdateDownloadError.responseRejected }
        try Task.checkCancellation()
        return try await importUpdate(at: result.fileURL)
    }
    public func importUpdate(at url: URL) async throws -> RulePack {
        try configuration.validate()
        guard configuration.rulePublicKey?.count == 32 else { throw ReleaseConfigurationError.missing }
        let data = try UpdateFileContent.read(url, maximumBytes: 1_500_000)
        guard let update = try? JSONDecoder().decode(SignedRuleUpdate.self, from: data) else { throw RuleStoreError.invalidSchema }
        try Task.checkCancellation()
        try await store.install(update: update)
        return try await store.currentPack()
    }
    public func rollback() async throws -> RulePack {
        try Task.checkCancellation()
        try await store.rollback()
        return try await store.currentPack()
    }
}
