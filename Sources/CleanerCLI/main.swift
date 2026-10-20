import CleanerCore
import Foundation

@main enum CleanerCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print(ReadOnlyRequest.usage)
            return
        }
        do {
            let request = try ReadOnlyRequest(arguments: arguments)
            let result = try await ReadOnlyInterface.run(request)
            FileHandle.standardOutput.write(try result.json())
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let message = ["error": error.localizedDescription]
            let data = (try? encoder.encode(message)) ?? Data("{\"error\":\"Command failed\"}".utf8)
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
            exit(1)
        }
    }
}
