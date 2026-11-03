import Foundation
import GemmaEmbed

@main
struct AgentInferenceMain {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw CocoaError(.fileReadInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "A model path is required."])
        }
        let model = try await EmbeddingModel.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
        let options = EmbedOptions(task: .similarity, dimensions: 768, normalise: true)
        while let line = readLine() {
            let texts = try JSONDecoder().decode([String].self, from: Data(line.utf8))
            let embeddings = try await model.embed(texts, options: options)
            guard !embeddings.contains(where: \.truncated) else {
                throw CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedDescriptionKey: "The model truncated an input."])
            }
            var response = Data("SUPERCLEANER_EMBEDDING:".utf8)
            response.append(try JSONEncoder().encode(embeddings.map(\.vector)))
            response.append(10)
            try FileHandle.standardOutput.write(contentsOf: response)
        }
    }
}
