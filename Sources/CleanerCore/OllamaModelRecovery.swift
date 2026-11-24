import Foundation

/// APFS clones keep each retained model recoverable without depending on another receipt.
/// They share disk extents until a writer changes content; no model weight is read into memory.
struct OllamaModelRecovery {
    let context: ScanContext
    let planDirectory: URL

    func prepare(_ candidate: CleanupCandidate, destination: URL) async throws {
        guard let proof = candidate.ollamaModelProof else { return }
        try validateArchiveURL(destination, candidateID: candidate.id, original: candidate.url)
        guard try await validatedArchiveIdentity(planDirectory).kind == .directory else {
            throw FileSystemError.invalidAttributes(planDirectory)
        }
        let directory = destination.appendingPathExtension("ollama-files")
        try await context.fileSystem.createDirectory(directory)
        guard try await validatedArchiveIdentity(directory).kind == .directory else {
            throw FileSystemError.invalidAttributes(directory)
        }
        for blob in proof.blobs {
            try Task.checkCancellation()
            let snapshot = directory.appendingPathComponent(blob.url.lastPathComponent)
            if !(await context.fileSystem.fileExists(snapshot)) {
                try await context.fileSystem.cloneFile(blob.url, to: snapshot)
            }
            let identity = try await validatedArchiveIdentity(snapshot)
            guard identity.kind == .file, identity.size == blob.identity.size else {
                throw FileSystemError.invalidAttributes(snapshot)
            }
        }
    }

    func restoreDependencies(_ result: OperationResult, receipt: OperationReceipt) async throws {
        let scanner = LocalAIModelScanner()
        let root = try storageRoot(for: result)
        let recoveryContext = ScanContext(homeDirectory: context.homeDirectory, fileSystem: context.fileSystem,
            protectionPolicy: context.protectionPolicy,
            modelRoots: [.init(provider: .ollama, url: root)])
        if result.originalURL.deletingLastPathComponent().path == root.appendingPathComponent("blobs").path {
            let digest = result.originalURL.lastPathComponent.replacingOccurrences(of: "sha256-", with: "sha256:")
            guard try scanner.ollamaBlobURL(digest, root: root) == result.originalURL else { throw PathPolicyError.invalidSyntax }
            try await ensureDirectory(result.originalURL.deletingLastPathComponent(), within: root)
            return
        }
        guard let source = result.destinationURL, try directory(for: result) != nil else { return }
        try await ensureDirectory(result.originalURL.deletingLastPathComponent(), within: root)
        let document = try JSONDecoder().decode(OllamaManifestDocument.self,
            from: await context.fileSystem.readData(at: source, maximumBytes: 1_048_576))
        let ownFiles = Dictionary(receipt.results.filter { $0.disposition == .quarantined }.map { ($0.originalURL, $0) },
            uniquingKeysWith: { first, _ in first })
        for layer in document.layers + [document.config] {
            let original = try scanner.ollamaBlobURL(layer.digest, root: root)
            if await context.fileSystem.fileExists(original) {
                let identity = try await scanner.validatedIdentity(original, context: recoveryContext)
                guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(original) }
                continue
            }
            if let own = ownFiles[original], let archived = own.destinationURL,
               await context.fileSystem.fileExists(archived) {
                try validateArchiveURL(archived, candidateID: own.candidateID, original: own.originalURL)
                let identity = try await validatedArchiveIdentity(archived)
                guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(archived) }
                continue
            }
            let snapshot = source.appendingPathExtension("ollama-files").appendingPathComponent(original.lastPathComponent)
            let identity = try await validatedArchiveIdentity(snapshot)
            guard identity.kind == .file, identity.size == layer.size else { throw FileSystemError.invalidAttributes(snapshot) }
            try await ensureDirectory(original.deletingLastPathComponent(), within: root)
            try await context.fileSystem.cloneFile(snapshot, to: original)
        }
    }

    private func ensureDirectory(_ url: URL, within root: URL) async throws {
        var ancestors: [URL] = []
        var current = url
        while true {
            ancestors.append(current)
            if current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        for ancestor in ancestors.reversed() {
            if !(await context.fileSystem.fileExists(ancestor)) {
                guard ancestor.path == root.path || ancestor.path.hasPrefix(root.path + "/") else {
                    throw PathPolicyError.outsideAllowedHome
                }
                _ = try context.pathPolicy.validateCandidate(ancestor)
                try context.protectionPolicy.validate(ancestor)
                try await context.fileSystem.createDirectory(ancestor)
            }
            guard try await context.fileSystem.identity(at: ancestor).kind == .directory else {
                throw PathPolicyError.invalidSyntax
            }
        }
    }

    func directory(for result: OperationResult) throws -> URL? {
        let prefix = try storageRoot(for: result).appendingPathComponent("manifests").path + "/"
        guard result.originalURL.path.hasPrefix(prefix),
              result.originalURL.path.dropFirst(prefix.count).split(separator: "/").count == 4 else { return nil }
        guard let destination = result.destinationURL else { return nil }
        try validateArchiveURL(destination, candidateID: result.candidateID, original: result.originalURL)
        return destination.appendingPathExtension("ollama-files")
    }

    private func storageRoot(for result: OperationResult) throws -> URL {
        let root = result.modelStorageRoot ?? context.homeDirectory.appendingPathComponent(".ollama/models")
        try ModelStorageRoot.validate(root, home: context.homeDirectory)
        return root
    }

    private func validateArchiveURL(_ url: URL, candidateID: UUID, original: URL) throws {
        let expected = planDirectory.appendingPathComponent(candidateID.uuidString + "-" + original.lastPathComponent)
        guard url.isFileURL, !url.pathComponents.contains(".."), url.standardizedFileURL == expected.standardizedFileURL else {
            throw PathPolicyError.invalidSyntax
        }
    }

    /// Internal recovery content is protected from normal cleanup. Validate its
    /// exact transaction boundary and every ancestor instead of weakening that policy.
    func validatedArchiveIdentity(_ url: URL) async throws -> FileIdentity {
        try Task.checkCancellation()
        let root = planDirectory.standardizedFileURL
        let clean = url.standardizedFileURL
        guard url.isFileURL, !url.pathComponents.contains(".."),
              (clean == root || clean.path.hasPrefix(root.path + "/")),
              root.path.hasPrefix(context.homeDirectory.path + "/"),
              UUID(uuidString: root.lastPathComponent) != nil,
              !url.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw PathPolicyError.invalidSyntax
        }
        var ancestor = clean.deletingLastPathComponent()
        while true {
            guard try await context.fileSystem.identity(at: ancestor).kind == .directory else {
                throw PathPolicyError.invalidSyntax
            }
            if ancestor.path == "/" { break }
            ancestor = ancestor.deletingLastPathComponent()
        }
        let identity = try await context.fileSystem.identity(at: clean)
        guard identity.kind == .file || identity.kind == .directory else { throw PathPolicyError.invalidSyntax }
        return identity
    }
}
