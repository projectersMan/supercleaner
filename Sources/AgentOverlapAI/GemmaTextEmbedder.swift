import CleanerCore
import Darwin
import Foundation
public actor GemmaTextEmbedder: AgentEmbeddingProvider {
    public static let modelVersion = "embeddinggemma-2-Q8_0-v1"
    private let modelURL: URL
    private let executableURL: URL
    private var worker: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var tail: Task<[[Float]], Error>?

    public init(modelURL: URL, executableURL: URL) {
        self.modelURL = modelURL
        self.executableURL = executableURL
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        let previous = tail
        let task = Task {
            // The previous caller owns its result; waiting only serializes the pipe.
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await exchange(texts)
        }
        tail = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func shutdown() {
        tail?.cancel()
        if worker?.isRunning == true { worker?.terminate() }
    }

    private func exchange(_ texts: [String]) async throws -> [[Float]] {
        if worker?.isRunning != true {
            let process = Process()
            let requests = Pipe()
            let responses = Pipe()
            guard fcntl(requests.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            process.executableURL = executableURL
            process.arguments = [modelURL.path]
            process.standardInput = requests
            process.standardOutput = responses
            try process.run()
            worker = process
            input = requests.fileHandleForWriting
            output = responses.fileHandleForReading
        }
        guard let worker, let input, let output else { throw AgentOverlapError.inferenceWorkerUnavailable }
        var completed = false
        defer {
            if !completed {
                if worker.isRunning { worker.terminate() }
                self.worker = nil
                self.input = nil
                self.output = nil
            }
        }
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            var request = try JSONEncoder().encode(texts)
            request.append(10)
            try input.write(contentsOf: request)
            for try await line in output.bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("SUPERCLEANER_EMBEDDING:") else { throw AgentOverlapError.invalidEmbeddingOutput }
                return try JSONDecoder().decode([[Float]].self, from: Data(line.dropFirst("SUPERCLEANER_EMBEDDING:".count).utf8))
            }
            try Task.checkCancellation()
            throw AgentOverlapError.inferenceWorkerUnavailable
        } onCancel: {
            if worker.isRunning { worker.terminate() }
        }
        completed = true
        return response
    }
}
