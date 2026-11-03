import CleanerCore
import CryptoKit
import Foundation

public actor AgentEmbeddingModelManager {
    public enum State: Sendable, Equatable { case unsupported, notInstalled, downloading, ready, failed(String) }
    public static var isSupportedPlatform: Bool {
        #if arch(arm64)
        if #available(macOS 14, *) { return true }
        #endif
        return false
    }
    public static let modelSizeBytes = 309_855_456
    public static let hasBundledModel = Bundle.module.url(forResource: "embeddinggemma-2-Q8_0", withExtension: "gguf", subdirectory: "Models") != nil
    private static let modelSHA256 = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"
    private static let modelURL = URL(string: "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/main/embeddinggemma-2-Q8_0.gguf")!
    private let modelFileURL: URL
    private let bundledModelURL: URL?
    private var loadedEmbedder: GemmaTextEmbedder?
    private var currentState: State

    public init(applicationSupportURL: URL) {
        let localModelURL = applicationSupportURL.appendingPathComponent("Models/embeddinggemma-2-Q8_0.gguf")
        let bundledModelURL = Bundle.module.url(forResource: "embeddinggemma-2-Q8_0", withExtension: "gguf", subdirectory: "Models")
        modelFileURL = localModelURL
        self.bundledModelURL = bundledModelURL
        currentState = !Self.isSupportedPlatform ? .unsupported
            : FileManager.default.fileExists(atPath: localModelURL.path) || bundledModelURL != nil ? .ready : .notInstalled
    }

    public func state() -> State { currentState }
    public func localModelURL() -> URL { modelFileURL }
    public func canRemoveLocalModel() -> Bool { FileManager.default.fileExists(atPath: modelFileURL.path) }

    public func loadProvider() async throws -> GemmaTextEmbedder {
        guard Self.isSupportedPlatform else { throw AgentOverlapError.unsupportedPlatform }
        if let loadedEmbedder { return loadedEmbedder }
        let modelURL = FileManager.default.fileExists(atPath: modelFileURL.path) ? modelFileURL : bundledModelURL
        guard let modelURL else { throw CocoaError(.fileNoSuchFile) }
        guard let executableURL = Bundle.main.url(forAuxiliaryExecutable: "AgentInference") else { throw AgentOverlapError.inferenceWorkerUnavailable }
        let embedder = GemmaTextEmbedder(modelURL: modelURL, executableURL: executableURL)
        loadedEmbedder = embedder
        currentState = .ready
        return embedder
    }

    public func downloadModel(progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        guard Self.isSupportedPlatform else { throw AgentOverlapError.unsupportedPlatform }
        guard currentState != .downloading else { throw CocoaError(.fileWriteFileExists) }
        currentState = .downloading
        defer {
            if currentState == .downloading {
                currentState = Task.isCancelled ? .notInstalled : .failed("Model download did not complete")
            }
        }
        let request = URLRequest(url: Self.modelURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 600)
        let progressDelegate = ModelDownloadProgressDelegate(progress: progress)
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: progressDelegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == Self.modelSizeBytes, digest == Self.modelSHA256 else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: modelFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: modelFileURL, options: .atomic)
        currentState = .ready
    }

    public func removeModel() async throws {
        await loadedEmbedder?.shutdown()
        loadedEmbedder = nil
        if FileManager.default.fileExists(atPath: modelFileURL.path) { try FileManager.default.removeItem(at: modelFileURL) }
        currentState = !Self.isSupportedPlatform ? .unsupported : bundledModelURL == nil ? .notInstalled : .ready
    }
}

private final class ModelDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void

    init(progress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(AgentEmbeddingModelManager.modelSizeBytes)
        progress(totalBytesWritten, expectedBytes)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
