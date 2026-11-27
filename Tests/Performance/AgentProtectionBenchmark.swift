import CleanerCore
import CryptoKit
import Foundation

/// Runs the production scanner read-only. Use the same home and timestamp for
/// both binaries; snapshots compare every field except newly generated UUIDs
/// and the ordering of sets. Snapshot serialization is outside the timed region.
/// Usage: benchmark <home> <output-directory> <context-unix-time> <repeats>
@main struct AgentProtectionBenchmark {
    static func main() async throws {
        guard CommandLine.arguments.count == 5,
              let timestamp = Double(CommandLine.arguments[3]),
              let repeats = Int(CommandLine.arguments[4]), repeats > 0 else {
            fatalError("Usage: benchmark <home> <output-directory> <context-unix-time> <repeats>")
        }
        let home = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scanner = AgentWorkspaceScanner(directorySnapshot: AgentDirectorySnapshot())
        let context = ScanContext(homeDirectory: home, now: Date(timeIntervalSince1970: timestamp), enforcesEntryBudgets: false)
        for pass in 0..<repeats {
            let timing = CapabilityTiming()
            let start = ContinuousClock.now
            let inventory = try await scanner.scanAssetInventory(context: context) { _ in
                await timing.set(Self.seconds(since: start))
            }
            let elapsed = seconds(since: start)
            let snapshot = output.appendingPathComponent("pass-\(pass).jsonl")
            try writeSnapshot(inventory, to: snapshot)
            let result: [String: Any] = [
                "pass": pass, "seconds": elapsed, "capability_seconds": await timing.seconds,
                "assets": inventory.assets.count, "skills": inventory.skills.count,
                "mcp": inventory.mcpConfigurations.count, "complete": inventory.isComplete,
                "snapshot": snapshot.path,
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self)); fflush(stdout)
        }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }

    private static func writeSnapshot(_ inventory: AgentAssetInventory, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        func record<T: Encodable>(_ kind: String, _ key: String, _ value: T) throws {
            var object = try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
            if kind == "asset", var asset = object as? [String: Any], var candidate = asset["candidate"] as? [String: Any] {
                candidate.removeValue(forKey: "id")
                asset["candidate"] = candidate
                object = asset
            }
            if kind == "skill", var skill = object as? [String: Any], let sources = skill["sourceAssetURLs"] as? [String] {
                skill["sourceAssetURLs"] = sources.sorted()
                object = skill
            }
            let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
            let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
            var line = try JSONSerialization.data(withJSONObject: ["kind": kind, "key": key, "sha256": digest], options: [.sortedKeys])
            line.append(10)
            try handle.write(contentsOf: line)
        }
        for asset in inventory.assets { try record("asset", asset.candidate.url.path, asset) }
        for skill in inventory.skills { try record("skill", skill.id, skill) }
        for configuration in inventory.mcpConfigurations { try record("mcp", configuration.id, configuration) }
        for provider in AgentProvider.allCases {
            if let coverage = inventory.providerCoverage[provider] { try record("provider", provider.rawValue, coverage) }
        }
        let coverage = [
            "scannedRoots": inventory.coverage.scannedRoots.map(\.absoluteString).sorted(),
            "unavailableRoots": inventory.coverage.unavailableRoots.map(\.absoluteString).sorted(),
            "budgetLimitedModules": inventory.coverage.budgetLimitedModules.map(\.rawValue).sorted(),
        ]
        try record("coverage", "coverage", coverage)
        try record("limitations", "limitations", inventory.limitations)
        try record("flags", "flags", ["complete": inventory.isComplete, "capabilitiesOnly": inventory.capabilitiesOnly, "reachedBudget": inventory.reachedBudget])
        try record("duplicates", "duplicates", inventory.skillDuplicatesCollapsedCount)
    }
}

private actor CapabilityTiming {
    var seconds = 0.0
    func set(_ value: Double) { seconds = value }
}
