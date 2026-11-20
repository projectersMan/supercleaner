import CryptoKit
import Foundation

public enum LocalAIModelProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case huggingFace
    case lmStudio
    case ollama
    case pytorch
    case whisper
    case keras
    case gpt4All
}

public struct LocalAIModelRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let provider: LocalAIModelProvider
    public let candidate: CleanupCandidate

    public init(provider: LocalAIModelProvider, candidate: CleanupCandidate) {
        self.provider = provider
        self.candidate = candidate
    }
}

public struct LocalAIModelInventory: Codable, Sendable {
    public let models: [LocalAIModelRecord]
    public let coverage: CoverageSummary
    public let limitations: [ScanLimitation]
    public let scannedAt: Date
    public var candidates: [CleanupCandidate] { models.map(\.candidate) }

    public init(models: [LocalAIModelRecord], coverage: CoverageSummary, limitations: [ScanLimitation], scannedAt: Date) {
        self.models = models
        self.coverage = coverage
        self.limitations = limitations
        self.scannedAt = scannedAt
    }
}

/// Discovers only fixed, model-specific storage layouts, never tool support/configuration roots.
public struct LocalAIModelScanner: Sendable {
    public let maximumEntries: Int
    public let timeLimit: TimeInterval

    public init() {
        maximumEntries = 100_000
        timeLimit = 30
    }

    public init(maximumEntries: Int, timeLimit: TimeInterval) {
        precondition(maximumEntries > 0 && timeLimit > 0 && timeLimit.isFinite)
        self.maximumEntries = maximumEntries
        self.timeLimit = timeLimit
    }

    public func scan(context: ScanContext) async throws -> LocalAIModelInventory {
        var budget = InspectionBudget(remaining: maximumEntries, deadline: .now.advanced(by: .seconds(timeLimit)))
        var models: [LocalAIModelRecord] = []
        var scannedRoots: [URL] = []
        var limitations: [ScanLimitation] = []
        for storage in Self.storages {
            try Task.checkCancellation()
            let root = context.homeDirectory.appendingPathComponent(storage.relativePath).standardizedFileURL
            var rootVerified = false
            do {
                _ = try await validatedIdentity(root, context: context)
                rootVerified = true
                scannedRoots.append(root)
                if storage.provider == .ollama {
                    models.append(contentsOf: try await ollamaModels(root: root, context: context, budget: &budget))
                    continue
                }
                let targets = try await targets(in: root, storage: storage, context: context, budget: &budget, limitations: &limitations)
                for target in targets {
                    try Task.checkCancellation()
                    do {
                        let result = try await inspect(target, root: root, storage: storage, context: context, budget: &budget)
                        models.append(LocalAIModelRecord(provider: storage.provider, candidate: result.candidate))
                        limitations.append(contentsOf: result.limitations)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        limitations.append(limitation(error, path: target))
                    }
                    if budget.exhausted { break }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch FileSystemError.missing where !rootVerified {
                // An absent configured cache is expected; all other read failures remain visible.
                continue
            } catch {
                limitations.append(limitation(error, path: root))
            }
            if budget.exhausted { break }
        }
        let uniqueLimitations = Array(Set(limitations)).sorted { $0.id < $1.id }
        let unavailable = uniqueLimitations.filter { $0.reason != .budget }.compactMap(\.path)
        return LocalAIModelInventory(
            models: models.sorted { $0.candidate.url.path < $1.candidate.url.path },
            coverage: CoverageSummary(scannedRoots: scannedRoots, unavailableRoots: unavailable,
                budgetLimitedModules: uniqueLimitations.contains { $0.reason == .budget } ? [.localAIModels] : []),
            limitations: uniqueLimitations,
            scannedAt: context.now
        )
    }

    public func validateForExecution(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        try Task.checkCancellation()
        if candidate.ruleID == "local-ai-model.ollama-blob" {
            try await validateOllamaBlob(candidate, context: context)
            return
        }
        guard candidate.source == .localAIModels, candidate.category == .agentModelCache,
              candidate.risk == .review, !candidate.isActive,
              candidate.defaultSelection == false, candidate.requiresExplicitSelection == true,
              let storage = Self.storages.first(where: { $0.contains(candidate.url, home: context.homeDirectory) }),
              candidate.ruleID == "local-ai-model.\(storage.provider.rawValue)" else {
            throw RuleScanError.executionRefused("invalid-local-ai-model-scope")
        }
        let root = context.homeDirectory.appendingPathComponent(storage.relativePath).standardizedFileURL
        let identity = try await validatedIdentity(candidate.url, context: context)
        guard identity == candidate.identity else { throw RuleScanError.executionRefused("local-ai-model-identity-changed") }
        var budget = InspectionBudget(remaining: maximumEntries, deadline: .now.advanced(by: .seconds(timeLimit)))
        if storage.provider == .ollama {
            let current = try await ollamaModel(at: candidate.url, root: root, context: context, budget: &budget, references: [:])
            let expanded = candidate.evidence.contains { $0.code == "ollama-manifest-operation" }
            guard candidate.ollamaModelProof != nil,
                  candidate.bytes == (expanded ? current.identity.size : current.bytes),
                  candidate.evidence.first(where: { $0.code == "local-ai-model-fingerprint" })?.details
                    == current.evidence.first(where: { $0.code == "local-ai-model-fingerprint" })?.details else {
                throw RuleScanError.executionRefused("local-ai-model-content-changed")
            }
            return
        }
        let current = try await inspect(candidate.url, root: root, storage: storage, context: context, budget: &budget)
        let expectedFingerprint = candidate.evidence.first { $0.code == "local-ai-model-fingerprint" }?.details
        let currentFingerprint = current.candidate.evidence.first { $0.code == "local-ai-model-fingerprint" }?.details
        guard current.candidate.risk == .review, current.limitations.isEmpty,
              current.candidate.identity == candidate.identity, current.candidate.bytes == candidate.bytes,
              let expectedFingerprint, expectedFingerprint == currentFingerprint else {
            throw RuleScanError.executionRefused("local-ai-model-content-changed")
        }
    }

    private func targets(
        in root: URL, storage: Storage, context: ScanContext, budget: inout InspectionBudget,
        limitations: inout [ScanLimitation]
    ) async throws -> [URL] {
        var targets: [URL] = []
        for child in try await children(root, context: context) {
            try Task.checkCancellation()
            try budget.consume(child)
            do {
                let identity = try await validatedIdentity(child, context: context)
                if storage.layout == .publisherModel {
                    guard identity.kind == .directory else { continue }
                    for model in try await children(child, context: context) {
                        try budget.consume(model)
                        do {
                            let modelIdentity = try await validatedIdentity(model, context: context)
                            if modelIdentity.kind == .directory { targets.append(model) }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            limitations.append(limitation(error, path: model))
                        }
                    }
                } else if storage.accepts(child, kind: identity.kind) {
                    targets.append(child)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                limitations.append(limitation(error, path: child))
            }
        }
        return targets
    }

    private func inspect(
        _ url: URL, root: URL, storage: Storage, context: ScanContext, budget: inout InspectionBudget
    ) async throws -> Inspection {
        let identity = try await validatedIdentity(url, context: context)
        guard storage.contains(url, home: context.homeDirectory), storage.accepts(url, kind: identity.kind) else {
            throw InspectionError.scope(url)
        }
        var evidence = [
            Evidence(code: "local-ai-model-provider", summary: L10n.text("模型存储：{0}", storage.provider.rawValue), details: root.path),
            Evidence(code: "local-ai-model-manual", summary: L10n.text("本地模型缓存需明确选择，清理后可能需要重新下载")),
        ]
        var limitations: [ScanLimitation] = []
        var bytes: UInt64 = 0
        var stamps: [ItemStamp] = []
        var pending = [(url, identity)]
        var hasModelFile = storage.layout == .huggingFace || storage.isDataset
        var checking = url
        var blocked = false
        do {
            try await validateLayout(url, storage: storage, context: context)
            while let (item, expectedIdentity) = pending.popLast() {
                checking = item
                try Task.checkCancellation()
                try budget.consume(item)
                let current = try await validatedIdentity(item, context: context, allowLink: item != url)
                guard current == expectedIdentity else { throw InspectionError.changed(item) }
                let generation = try await context.fileSystem.itemGeneration(at: item)
                stamps.append(ItemStamp(url: item, identity: current, generation: generation))
                if Self.isSensitive(item) { throw InspectionError.sensitive(item) }
                switch current.kind {
                case .directory:
                    for child in try await children(item, context: context) {
                        checking = child
                        try Task.checkCancellation()
                        try budget.consume(child)
                        let childIdentity = try await context.fileSystem.identity(at: child)
                        pending.append((child, childIdentity))
                    }
                case .file:
                    guard await context.fileSystem.isReadable(item) else { throw InspectionError.unreadable(item) }
                    let (sum, overflow) = bytes.addingReportingOverflow(current.size)
                    guard !overflow else { throw FileSystemError.invalidAttributes(item) }
                    bytes = sum
                    hasModelFile = hasModelFile || Storage.modelExtensions.contains(item.pathExtension.lowercased())
                case .symbolicLink:
                    // Repository snapshots refer to blobs; moving the repository carries links without following them.
                    continue
                case .other:
                    throw InspectionError.scope(item)
                }
            }
            guard hasModelFile else { throw InspectionError.scope(url) }
            for stamp in stamps {
                checking = stamp.url
                try Task.checkCancellation()
                try budget.consume(stamp.url)
                guard try await context.fileSystem.identity(at: stamp.url) == stamp.identity,
                      try await context.fileSystem.itemGeneration(at: stamp.url) == stamp.generation else {
                    throw InspectionError.changed(stamp.url)
                }
            }
            evidence.append(Evidence(code: "local-ai-model-fingerprint", summary: L10n.text("模型内容已验证，执行前将重新检查"),
                details: Self.fingerprint(stamps, root: url)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            blocked = true
            let failure = limitation(error, path: checking)
            limitations.append(failure)
            evidence.append(Evidence(code: failure.reason == .budget ? "local-ai-model-budget" : "local-ai-model-unverified",
                summary: failure.title, details: failure.path?.path))
        }
        let candidate = CleanupCandidate(url: url, displayName: url.lastPathComponent, category: .agentModelCache,
            bytes: bytes, risk: blocked ? .blocked : .review, evidence: evidence, identity: identity, source: .localAIModels,
            lastAccessDate: nil, isActive: false, ruleID: "local-ai-model.\(storage.provider.rawValue)",
            defaultSelection: false, requiresExplicitSelection: true)
        return Inspection(candidate: candidate, limitations: limitations)
    }

    private func validateLayout(_ url: URL, storage: Storage, context: ScanContext) async throws {
        guard storage.layout == .huggingFace else { return }
        let markers = ["blobs", "snapshots"]
        var found = false
        for child in try await children(url, context: context) where markers.contains(child.lastPathComponent) {
            guard try await validatedIdentity(child, context: context).kind == .directory else { throw InspectionError.scope(child) }
            found = true
        }
        guard found else { throw InspectionError.scope(url) }
    }

    func children(_ directory: URL, context: ScanContext) async throws -> [URL] {
        guard await context.fileSystem.isReadable(directory) else { throw InspectionError.unreadable(directory) }
        let children = try await context.fileSystem.children(of: directory)
        guard children.allSatisfy({ $0.isFileURL && $0.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path
            && !$0.pathComponents.contains("..") }) else { throw InspectionError.scope(directory) }
        return children.sorted { $0.path < $1.path }
    }

    func validatedIdentity(_ url: URL, context: ScanContext, allowLink: Bool = false) async throws -> FileIdentity {
        try Task.checkCancellation()
        let clean = url.standardizedFileURL
        let home = context.homeDirectory.standardizedFileURL
        guard url.isFileURL, !url.pathComponents.contains(".."), clean.path.hasPrefix(home.path + "/"),
              !url.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw InspectionError.scope(url) }
        var ancestors: [URL] = []
        var current = clean.deletingLastPathComponent()
        while true {
            ancestors.append(current)
            if current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        for ancestor in ancestors.reversed() {
            try Task.checkCancellation()
            guard try await context.fileSystem.identity(at: ancestor).kind == .directory else { throw InspectionError.scope(ancestor) }
        }
        let identity = try await context.fileSystem.identity(at: clean)
        guard identity.kind != .symbolicLink || allowLink else { throw InspectionError.scope(clean) }
        // Policies inspect literal and physical paths only after all ancestors are proven non-links.
        _ = try context.pathPolicy.validateCandidate(clean)
        try context.protectionPolicy.validate(clean)
        return identity
    }

    private func limitation(_ error: Error, path: URL) -> ScanLimitation {
        let reason: ScanFailure.Reason?
        let title: String
        let affected: URL
        switch error {
        case let InspectionError.budget(url):
            reason = .budget; title = L10n.text("达到模型扫描预算，保持保护"); affected = url
        case let InspectionError.scope(url):
            reason = nil; title = L10n.text("模型范围或路径无法验证，保持保护"); affected = url
        case let InspectionError.sensitive(url):
            reason = nil; title = L10n.text("模型目录含凭据，保持保护"); affected = url
        case let InspectionError.changed(url), let FileSystemError.missing(url):
            reason = .changed; title = L10n.text("位置已发生变化"); affected = url
        case let InspectionError.unreadable(url):
            reason = .access; title = L10n.text("模型内容未完整验证，保持保护"); affected = url
        default:
            let failure = error as NSError
            let denied = (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
                || (failure.domain == NSPOSIXErrorDomain && [POSIXErrorCode.EACCES.rawValue, POSIXErrorCode.EPERM.rawValue].contains(Int32(failure.code)))
            reason = denied ? .access : nil
            title = L10n.text("模型内容未完整验证，保持保护")
            affected = path
        }
        return ScanLimitation(title: title, path: affected,
            impact: L10n.text("模型检查范围不完整；受影响的模型不会清理"),
            recovery: L10n.text("检查模型目录权限和内容后重新扫描"), reason: reason)
    }

    private static func isSensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return ["token", "tokens", "auth.json", "credentials.json", "credentials", "settings.json", "keras.json", "id_rsa", "id_ed25519", ".git", ".ssh", ".env"].contains(name)
            || name.hasPrefix(".env.") || ["pem", "key", "p12", "pfx"].contains(url.pathExtension.lowercased())
    }

    static func fingerprint(_ stamps: [ItemStamp], root: URL) -> String {
        let lines = stamps.sorted { $0.url.path < $1.url.path }.map { stamp in
            let identity = stamp.identity
            return "\(stamp.url.path.dropFirst(root.path.count))|\(identity.device)|\(identity.inode)|\(identity.size)|\(identity.modificationTime)|\(identity.kind.rawValue)|\(stamp.generation ?? "")"
        }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Inspection { let candidate: CleanupCandidate; let limitations: [ScanLimitation] }
    struct ItemStamp { let url: URL; let identity: FileIdentity; let generation: String? }
    struct InspectionBudget {
        var remaining: Int
        let deadline: ContinuousClock.Instant
        var exhausted: Bool { remaining <= 0 || ContinuousClock.now >= deadline }
        mutating func consume(_ path: URL) throws {
            guard !exhausted else { throw InspectionError.budget(path) }
            remaining -= 1
        }
    }
    enum InspectionError: Error {
        case budget(URL), scope(URL), sensitive(URL), changed(URL), unreadable(URL)
    }
    private enum Layout { case huggingFace, publisherModel, ollama, files, children }
    private struct Storage {
        let provider: LocalAIModelProvider
        let relativePath: String
        let layout: Layout
        let isDataset: Bool
        static let modelExtensions: Set<String> = ["gguf", "ggml", "bin", "safetensors", "pt", "pth", "ckpt", "onnx", "h5", "hdf5", "keras"]

        func contains(_ url: URL, home: URL) -> Bool {
            let root = home.appendingPathComponent(relativePath).standardizedFileURL
            let path = url.standardizedFileURL.path
            if layout == .ollama {
                let prefix = root.appendingPathComponent("manifests").path + "/"
                return path.hasPrefix(prefix) && path.dropFirst(prefix.count).split(separator: "/").count == 4
            }
            guard path.hasPrefix(root.path + "/") else { return false }
            let parts = path.dropFirst(root.path.count + 1).split(separator: "/")
            return parts.count == (layout == .publisherModel ? 2 : 1) && accepts(url, kind: layout == .files ? .file : .directory)
        }

        func accepts(_ url: URL, kind: FileIdentity.Kind) -> Bool {
            if layout == .ollama { return kind == .file }
            if layout == .publisherModel { return kind == .directory }
            if layout == .huggingFace {
                let name = url.lastPathComponent
                return kind == .directory && ((name.hasPrefix("models--") && name.count > 8) || (name.hasPrefix("datasets--") && name.count > 10))
            }
            if kind == .directory { return layout == .children }
            guard kind == .file else { return false }
            let ext = url.pathExtension.lowercased()
            if isDataset { return ["npz", "npy", "zip", "gz", "tar", "bz2", "xz", "h5", "hdf5"].contains(ext) }
            if provider == .gpt4All {
                let name = url.lastPathComponent.lowercased()
                return ["gguf", "ggml"].contains(ext) || (ext == "bin" && (name.hasPrefix("ggml-") || name.hasPrefix("gpt4all-")))
            }
            if provider == .whisper { return ext == "pt" }
            if provider == .keras { return ["h5", "hdf5", "keras"].contains(ext) }
            return Self.modelExtensions.contains(ext)
        }
    }

    private static let storages: [Storage] = [
        Storage(provider: .huggingFace, relativePath: ".cache/huggingface/hub", layout: .huggingFace, isDataset: false),
        Storage(provider: .lmStudio, relativePath: ".lmstudio/models", layout: .publisherModel, isDataset: false),
        Storage(provider: .lmStudio, relativePath: ".cache/lm-studio/models", layout: .publisherModel, isDataset: false),
        Storage(provider: .ollama, relativePath: ".ollama/models", layout: .ollama, isDataset: false),
        Storage(provider: .pytorch, relativePath: ".cache/torch/hub/checkpoints", layout: .files, isDataset: false),
        Storage(provider: .whisper, relativePath: ".cache/whisper", layout: .files, isDataset: false),
        Storage(provider: .keras, relativePath: ".keras/models", layout: .children, isDataset: false),
        Storage(provider: .keras, relativePath: ".keras/datasets", layout: .children, isDataset: true),
        Storage(provider: .gpt4All, relativePath: "Library/Application Support/nomic.ai/GPT4All", layout: .files, isDataset: false),
        Storage(provider: .gpt4All, relativePath: ".cache/gpt4all", layout: .files, isDataset: false),
    ]
}
