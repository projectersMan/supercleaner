import Foundation

/// APFS clones keep each retained model recoverable without depending on another receipt.
/// They share disk extents until a writer changes content; no model weight is read into memory.
struct OllamaModelRecovery {
    let context: ScanContext

    func prepare(_ candidate: CleanupCandidate, destination: URL) async throws {
        guard let proof = candidate.ollamaModelProof else { return }
        let directory = destination.appendingPathExtension("ollama-files")
        try await context.fileSystem.createDirectory(directory)
        guard try await LocalAIModelScanner().validatedIdentity(directory, context: context).kind == .directory else {
            throw FileSystemError.invalidAttributes(directory)
        }
        for blob in proof.blobs {
            try Task.checkCancellation()
            let snapshot = directory.appendingPathComponent(blob.url.lastPathComponent)
            if !(await context.fileSystem.fileExists(snapshot)) {
                try await context.fileSystem.cloneFile(blob.url, to: snapshot)
            }
            let identity = try await LocalAIModelScanner().validatedIdentity(snapshot, context: context)
            guard identity.kind == .file, identity.size == blob.identity.size else {
                throw FileSystemError.invalidAttributes(snapshot)
            }
        }
    }

    func restoreDependencies(_ result: OperationResult, receipt: OperationReceipt) async throws {
        let scanner = LocalAIModelScanner()
        let root = context.homeDirectory.appendingPathComponent(".ollama/models")
        if result.originalURL.deletingLastPathComponent().path == root.appendingPathComponent("blobs").path {
            let digest = result.originalURL.lastPathComponent.replacingOccurrences(of: "sha256-", with: "sha256:")
            guard try scanner.ollamaBlobURL(digest, root: root) == result.originalURL else { throw PathPolicyError.invalidSyntax }
            try await ensureDirectory(result.originalURL.deletingLastPathComponent())
            return
        }
        guard let source = result.destinationURL, directory(for: result) != nil else { return }
        try await ensureDirectory(result.originalURL.deletingLastPathComponent())
        let document = try JSONDecoder().decode(OllamaManifestDocument.self,
            from: await context.fileSystem.readData(at: source, maximumBytes: 1_048_576))
        let ownFiles = Dictionary(receipt.results.filter { $0.disposition == .quarantined }.map { ($0.originalURL, $0) },
            uniquingKeysWith: { first, _ in first })
        for layer in document.layers + [document.config] {
            let original = try scanner.ollamaBlobURL(layer.digest, root: root)
            if await context.fileSystem.fileExists(original) {
                let identity = try await scanner.validatedIdentity(original, context: context)
                guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(original) }
                continue
            }
            if let own = ownFiles[original], let archived = own.destinationURL,
               await context.fileSystem.fileExists(archived) {
                let identity = try await scanner.validatedIdentity(archived, context: context)
                guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(archived) }
                continue
            }
            let snapshot = source.appendingPathExtension("ollama-files").appendingPathComponent(original.lastPathComponent)
            let identity = try await scanner.validatedIdentity(snapshot, context: context)
            guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(snapshot) }
            try await ensureDirectory(original.deletingLastPathComponent())
            try await context.fileSystem.cloneFile(snapshot, to: original)
        }
    }

    private func ensureDirectory(_ url: URL) async throws {
        var ancestors: [URL] = []
        var current = url
        while true {
            ancestors.append(current)
            if current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        for ancestor in ancestors.reversed() {
            if !(await context.fileSystem.fileExists(ancestor)) {
                guard ancestor.path.hasPrefix(context.homeDirectory.path + "/") else {
                    throw PathPolicyError.outsideAllowedHome
                }
                try await context.fileSystem.createDirectory(ancestor)
            }
            guard try await context.fileSystem.identity(at: ancestor).kind == .directory else {
                throw PathPolicyError.invalidSyntax
            }
        }
    }

    func directory(for result: OperationResult) -> URL? {
        let prefix = context.homeDirectory.appendingPathComponent(".ollama/models/manifests").path + "/"
        guard result.originalURL.path.hasPrefix(prefix),
              result.originalURL.path.dropFirst(prefix.count).split(separator: "/").count == 4 else { return nil }
        return result.destinationURL?.appendingPathExtension("ollama-files")
    }
}
