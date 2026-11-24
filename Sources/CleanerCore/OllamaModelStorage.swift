import CryptoKit
import Foundation

/// A model is a named manifest; its content-addressed files can have other owners.
public struct OllamaModelProof: Codable, Hashable, Sendable {
    public let blobs: [OllamaModelBlob]
}

public struct OllamaModelBlob: Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let identity: FileIdentity
    public let generation: String?
    public let referencingManifests: Set<URL>

    var candidate: CleanupCandidate {
        let stamp = LocalAIModelScanner.ItemStamp(url: url, identity: identity, generation: generation)
        return CleanupCandidate(id: id, url: url, displayName: url.lastPathComponent, category: .agentModelCache,
            bytes: identity.size, risk: .review,
            evidence: [Evidence(code: "local-ai-model-fingerprint", summary: L10n.text("模型内容已验证，执行前将重新检查"),
                details: LocalAIModelScanner.fingerprint([stamp], root: url)),
                Evidence(code: "ollama-unreferenced-blob", summary: L10n.text("仅清理不再被保留模型引用的共享文件"))],
            identity: identity, source: .localAIModels, lastAccessDate: nil, isActive: false,
            ruleID: "local-ai-model.ollama-blob", defaultSelection: false, requiresExplicitSelection: true)
    }
}

extension OllamaModelProof {
    static func executionCandidates(from selected: [CleanupCandidate]) -> [CleanupCandidate] {
        let manifests = Set(selected.filter { $0.ollamaModelProof != nil }.map(\.url))
        guard !manifests.isEmpty else { return selected }
        var operations: [CleanupCandidate] = []
        var blobs: [CleanupCandidate] = []
        var seen = Set<URL>()
        for candidate in selected {
            guard let proof = candidate.ollamaModelProof else { operations.append(candidate); continue }
            let evidence = candidate.evidence.filter { $0.code != "ollama-manifest-operation" }
                + [Evidence(code: "ollama-manifest-operation", summary: L10n.text("仅删除所选模型及其不再共享的文件"))]
            operations.append(CleanupCandidate(id: candidate.id, url: candidate.url, displayName: candidate.displayName,
                category: candidate.category, bytes: candidate.identity.size, risk: candidate.risk, evidence: evidence,
                identity: candidate.identity, source: candidate.source, lastAccessDate: candidate.lastAccessDate,
                isActive: false, ruleID: candidate.ruleID, defaultSelection: false, requiresExplicitSelection: true,
                ollamaModelProof: proof))
            for blob in proof.blobs where blob.referencingManifests.isSubset(of: manifests) && seen.insert(blob.url).inserted {
                blobs.append(blob.candidate)
            }
        }
        // A failed manifest removal leaves a live reference, so the final blob check refuses its move.
        return operations + blobs.sorted { $0.url.path < $1.url.path }
    }
}

extension CleanupCandidate {
    var ollamaStorageRoot: URL? {
        if ruleID == "local-ai-model.ollama-blob", url.deletingLastPathComponent().lastPathComponent == "blobs" {
            return url.deletingLastPathComponent().deletingLastPathComponent()
        }
        guard ruleID == "local-ai-model.ollama", ollamaModelProof != nil else { return nil }
        var root = url
        for _ in 0..<5 { root.deleteLastPathComponent() }
        guard url.path.hasPrefix(root.appendingPathComponent("manifests").path + "/") else { return nil }
        return root
    }

    func removingOllamaReferences(_ removed: CleanupPathIndex) -> CleanupCandidate {
        guard let proof = ollamaModelProof else { return self }
        let blobs = proof.blobs.map { blob in
            OllamaModelBlob(id: blob.id, url: blob.url, identity: blob.identity, generation: blob.generation,
                referencingManifests: blob.referencingManifests.filter { !removed.contains($0) })
        }
        return CleanupCandidate(id: id, url: url, displayName: displayName, category: category, bytes: bytes,
            risk: risk, evidence: evidence, identity: identity, source: source, lastAccessDate: lastAccessDate,
            isActive: isActive, ruleID: ruleID, defaultSelection: defaultSelection,
            requiresExplicitSelection: requiresExplicitSelection, cleanupApplication: cleanupApplication,
            largeFileProof: largeFileProof, ollamaModelProof: OllamaModelProof(blobs: blobs))
    }
}

extension LocalAIModelScanner {
    func ollamaModels(root: URL, context: ScanContext, budget: inout InspectionBudget) async throws -> [LocalAIModelRecord] {
        let graph = try await ollamaManifests(root: root, context: context, budget: &budget)
        var references: [URL: Set<URL>] = [:]
        for manifest in graph {
            for layer in manifest.document.layers + [manifest.document.config] {
                references[try ollamaBlobURL(layer.digest, root: root), default: []].insert(manifest.url)
            }
        }
        var records: [LocalAIModelRecord] = []
        for manifest in graph {
            let candidate = try await ollamaModel(at: manifest.url, root: root, context: context, budget: &budget, references: references)
            records.append(LocalAIModelRecord(provider: .ollama, candidate: candidate))
        }
        return records
    }

    func ollamaModel(at url: URL, root: URL, context: ScanContext, budget: inout InspectionBudget,
        references: [URL: Set<URL>]) async throws -> CleanupCandidate {
        let manifest = try await readOllamaManifest(url, context: context, budget: &budget)
        let prefix = root.appendingPathComponent("manifests").path + "/"
        guard url.path.hasPrefix(prefix) else { throw InspectionError.scope(url) }
        let parts = url.path.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard parts.count == 4 else { throw InspectionError.scope(url) }
        let namespace = parts[1] == "library" ? "" : parts[1] + "/"
        let registry = parts[0] == "registry.ollama.ai" ? "" : parts[0] + "/"
        let name = registry + namespace + parts[2] + ":" + parts[3]
        var blobs: [OllamaModelBlob] = []
        var stamps = [manifest.stamp]
        var seen = Set<URL>()
        var bytes = manifest.stamp.identity.size
        for layer in manifest.document.layers + [manifest.document.config] {
            let blob = try ollamaBlobURL(layer.digest, root: root)
            guard seen.insert(blob).inserted else { continue }
            try budget.consume(blob)
            let identity = try await validatedIdentity(blob, context: context)
            guard identity.kind == .file, identity.size == layer.size, await context.fileSystem.isReadable(blob) else {
                throw InspectionError.unreadable(blob)
            }
            let generation = try await context.fileSystem.itemGeneration(at: blob)
            stamps.append(ItemStamp(url: blob, identity: identity, generation: generation))
            let sum = bytes.addingReportingOverflow(identity.size)
            guard !sum.overflow else { throw FileSystemError.invalidAttributes(blob) }
            bytes = sum.partialValue
            blobs.append(OllamaModelBlob(id: UUID(), url: blob, identity: identity, generation: generation,
                referencingManifests: references[blob] ?? [url]))
        }
        try await verifyOllamaStamps(stamps, context: context, budget: &budget)
        let content = Self.fingerprint(stamps, root: root) + "|" + Self.ollamaDigest(manifest.data)
        return context.protectionPolicy.applying(to: CleanupCandidate(url: url, displayName: name,
            category: .agentModelCache, bytes: bytes, risk: .review,
            evidence: [Evidence(code: "local-ai-model-provider", summary: L10n.text("模型存储：{0}", "Ollama"), details: root.path),
                Evidence(code: "local-ai-model-manual", summary: L10n.text("本地模型缓存需明确选择，清理后可能需要重新下载")),
                Evidence(code: "ollama-shared-storage", summary: L10n.text("模型大小包含共享文件；所选清理容量按实际可删除文件去重")),
                Evidence(code: "local-ai-model-fingerprint", summary: L10n.text("模型内容已验证，执行前将重新检查"), details: content)],
            identity: manifest.stamp.identity, source: .localAIModels, lastAccessDate: nil, isActive: false,
            ruleID: "local-ai-model.ollama", defaultSelection: false, requiresExplicitSelection: true,
            ollamaModelProof: OllamaModelProof(blobs: blobs)))
    }

    func validateOllamaBlob(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        let root = try authorizedOllamaRoot(for: candidate.url, context: context)
        let name = candidate.url.lastPathComponent
        guard candidate.source == .localAIModels, candidate.category == .agentModelCache,
              candidate.risk == .review, !candidate.isActive, candidate.defaultSelection == false,
              candidate.requiresExplicitSelection == true, name.hasPrefix("sha256-"),
              try ollamaBlobURL(name.replacingOccurrences(of: "sha256-", with: "sha256:"), root: root) == candidate.url,
              candidate.bytes == candidate.identity.size else {
            throw RuleScanError.executionRefused("invalid-ollama-blob-scope")
        }
        let identity = try await validatedIdentity(candidate.url, context: context)
        let generation = try await context.fileSystem.itemGeneration(at: candidate.url)
        let stamp = ItemStamp(url: candidate.url, identity: identity, generation: generation)
        guard identity.kind == .file, identity == candidate.identity,
              candidate.evidence.first(where: { $0.code == "local-ai-model-fingerprint" })?.details
                == Self.fingerprint([stamp], root: candidate.url) else {
            throw RuleScanError.executionRefused("local-ai-model-content-changed")
        }
    }

    /// Called by the common executor immediately before each physical blob move.
    func validateUnreferencedOllamaBlob(_ candidate: CleanupCandidate, context: ScanContext) async throws {
        guard candidate.ruleID == "local-ai-model.ollama-blob" else { return }
        try await validateOllamaBlob(candidate, context: context)
        let root = try authorizedOllamaRoot(for: candidate.url, context: context)
        var budget = InspectionBudget(remaining: maximumEntries, deadline: .now.advanced(by: .seconds(timeLimit)))
        for manifest in try await ollamaManifests(root: root, context: context, budget: &budget) {
            for layer in manifest.document.layers + [manifest.document.config] {
                guard try ollamaBlobURL(layer.digest, root: root) != candidate.url else {
                    throw RuleScanError.executionRefused("ollama-blob-still-referenced")
                }
            }
        }
        try await validateOllamaBlob(candidate, context: context)
    }

    private func ollamaManifests(root: URL, context: ScanContext, budget: inout InspectionBudget) async throws -> [OllamaManifestSnapshot] {
        let rootIdentity = try await validatedIdentity(root, context: context)
        let rootStamp = ItemStamp(url: root, identity: rootIdentity, generation: try await context.fileSystem.itemGeneration(at: root))
        // Unsupported named-manifest layouts must never be ignored when counting references.
        guard !(try await children(root, context: context)).contains(where: { $0.lastPathComponent.hasPrefix("manifests-") }) else {
            throw InspectionError.scope(root)
        }
        let manifests = root.appendingPathComponent("manifests")
        var pending = [(manifests, 0)]
        var stamps = [rootStamp]
        var output: [OllamaManifestSnapshot] = []
        while let (url, depth) = pending.popLast() {
            try budget.consume(url)
            let identity = try await validatedIdentity(url, context: context)
            if depth == 4 {
                guard identity.kind == .file else { throw InspectionError.scope(url) }
                let snapshot = try await readOllamaManifest(url, context: context, budget: &budget)
                output.append(snapshot)
                stamps.append(snapshot.stamp)
            } else {
                guard identity.kind == .directory else { throw InspectionError.scope(url) }
                stamps.append(ItemStamp(url: url, identity: identity, generation: try await context.fileSystem.itemGeneration(at: url)))
                for child in try await children(url, context: context) { pending.append((child, depth + 1)) }
            }
        }
        try await verifyOllamaStamps(stamps, context: context, budget: &budget)
        return output.sorted { $0.url.path < $1.url.path }
    }

    private func readOllamaManifest(_ url: URL, context: ScanContext, budget: inout InspectionBudget) async throws -> OllamaManifestSnapshot {
        try budget.consume(url)
        let identity = try await validatedIdentity(url, context: context)
        guard identity.kind == .file else { throw InspectionError.scope(url) }
        let generation = try await context.fileSystem.itemGeneration(at: url)
        let data = try await context.fileSystem.readData(at: url, maximumBytes: 1_048_576)
        let document = try JSONDecoder().decode(OllamaManifestDocument.self, from: data)
        guard document.schemaVersion == 2, document.mediaType == "application/vnd.docker.distribution.manifest.v2+json",
              !document.layers.isEmpty else { throw InspectionError.scope(url) }
        return OllamaManifestSnapshot(url: url, data: data, document: document,
            stamp: ItemStamp(url: url, identity: identity, generation: generation))
    }

    private func verifyOllamaStamps(_ stamps: [ItemStamp], context: ScanContext, budget: inout InspectionBudget) async throws {
        for stamp in stamps {
            try budget.consume(stamp.url)
            guard try await context.fileSystem.identity(at: stamp.url) == stamp.identity,
                  try await context.fileSystem.itemGeneration(at: stamp.url) == stamp.generation else {
                throw InspectionError.changed(stamp.url)
            }
        }
    }

    func ollamaBlobURL(_ digest: String, root: URL) throws -> URL {
        let hash = digest.dropFirst(7)
        guard digest.hasPrefix("sha256:"), hash.count == 64,
              hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw InspectionError.scope(root) }
        return root.appendingPathComponent("blobs/sha256-" + hash)
    }

    private static func ollamaDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct OllamaManifestDocument: Decodable {
    let schemaVersion: Int
    let mediaType: String
    let config: Layer
    let layers: [Layer]
    struct Layer: Decodable {
        let digest: String
        let size: UInt64
    }
}

private struct OllamaManifestSnapshot {
    let url: URL
    let data: Data
    let document: OllamaManifestDocument
    let stamp: LocalAIModelScanner.ItemStamp
}
