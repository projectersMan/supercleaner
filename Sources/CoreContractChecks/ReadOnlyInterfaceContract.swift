import CleanerCore
import Foundation

func runReadOnlyInterfaceContracts() async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("readonly-contract-\(UUID().uuidString)")
    let cache = home.appendingPathComponent("Library/Caches/unknown")
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    let file = cache.appendingPathComponent("user-payload")
    let original = Data("fixture must survive preview".utf8)
    try original.write(to: file)
    let before = try manager.attributesOfItem(atPath: file.path)
    let runtime = CleanupRuntime(home: home)
    let scan = try await ReadOnlyInterface.run(ReadOnlyRequest(arguments: ["scan", "--module", "general", "--home", home.path]), runtime: runtime)
    require(scan.schemaVersion == 1 && scan.scan?.modules.map(\.module) == [.general], "read-only schema and requested module scope must be explicit")
    require(scan.scan?.candidates.contains { $0.url.resolvingSymlinksInPath().path == cache.resolvingSymlinksInPath().path && $0.defaultSelection == false } == true, "read-only scan must use production classification")
    let json = try scan.json()
    let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    require(object["schema_version"] as? Int == 1 && object["generated_at"] is String, "JSON must be versioned with ISO timestamps")
    let scanObject = object["scan"] as? [String: Any]
    require(scanObject?["scan_status"] as? String == "complete" && scanObject?["protection_available"] as? Bool == true, "JSON must expose completeness and protection status")
    let preview = try await ReadOnlyInterface.run(ReadOnlyRequest(arguments: ["preview", "--module", "general", "--home", home.path, "--path", cache.path]), runtime: runtime)
    require(preview.plan?.selectedItems.map { $0.candidate.url.resolvingSymlinksInPath().path } == [cache.resolvingSymlinksInPath().path], "preview must bind selected path to scanned candidate")
    let defaults = try await ReadOnlyInterface.run(ReadOnlyRequest(arguments: ["preview", "--module", "general", "--home", home.path]), runtime: runtime)
    require(defaults.plan?.selectedItems.isEmpty == true, "preview must not default-select unknown caches")
    let history = try await ReadOnlyInterface.run(ReadOnlyRequest(arguments: ["history", "--home", home.path]), runtime: runtime)
    require(history.receipts?.isEmpty == true, "missing history must produce an empty read-only result")
    let support = home.appendingPathComponent("Library/Application Support/SuperCleaner")
    require(!manager.fileExists(atPath: support.path), "read-only scan/preview/history must not create application state")
    let remainingPayload = try Data(contentsOf: file)
    require(remainingPayload == original, "read-only interface must leave payload unchanged")
    let after = try manager.attributesOfItem(atPath: file.path)
    require(before[.modificationDate] as? Date == after[.modificationDate] as? Date, "preview must not modify file metadata")
    _ = try await runtime.protections.protect(file)
    do {
        _ = try await ReadOnlyInterface.run(ReadOnlyRequest(arguments: ["preview", "--module", "general", "--home", home.path, "--path", cache.path]), runtime: runtime)
        require(false, "read-only preview must not bypass protection")
    } catch is PlanBuilderError {}
    for arguments in [["delete"], ["scan", "--yes"], ["history", "--path", file.path], ["scan", "--home", "relative"], ["scan", "--module", "invalid"]] {
        do { _ = try ReadOnlyRequest(arguments: arguments); require(false, "invalid or destructive argument accepted: \(arguments)") } catch is ReadOnlyInterfaceError {}
    }
    print("PASS: versioned read-only JSON, scoped scans, explicit previews, history and no file effects")
}

func runReadOnlyCommandLineContracts(binary: String) async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("cli-contract-\(UUID().uuidString)")
    try manager.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    for arguments in [["history"], ["scan", "--module", "general"], ["preview", "--module", "general"], ["projects"], ["project-preview"]] {
        let output = try await BoundedProcess.run(binary, arguments: arguments + ["--home", home.path, "--json"], timeout: 20)
        require(output.status == 0, "packaged CLI failed for \(arguments): \(String(decoding: output.stderr, as: UTF8.self))")
        let object = try JSONSerialization.jsonObject(with: output.stdout) as? [String: Any]
        require(object?["schema_version"] as? Int == 1, "packaged CLI must output valid versioned JSON")
        require(output.stderr.isEmpty, "successful packaged CLI must not mix diagnostics into output")
    }
    let rejected = try await BoundedProcess.run(binary, arguments: ["delete", "--yes"])
    require(rejected.status != 0 && rejected.stdout.isEmpty && !rejected.stderr.isEmpty, "invalid CLI command must fail on stderr without stdout")
    _ = try JSONSerialization.jsonObject(with: rejected.stderr)
    let after = try manager.contentsOfDirectory(atPath: home.path)
    require(after.isEmpty, "packaged CLI must not write persistent application state")
    let boundary = home.appendingPathComponent(".codex/a/b/c/d/e/f/g/h")
    let sentinel = boundary.appendingPathComponent("i/sentinel.txt")
    try manager.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("read-only depth fixture".utf8).write(to: sentinel)
    let environment = ProcessInfo.processInfo.environment.filter { !["CODEX_HOME", "CLAUDE_CONFIG_DIR"].contains($0.key) }
    let agentScan = try await BoundedProcess.run(binary, arguments: ["scan", "--module", "agentEnvironment", "--home", home.path],
        timeout: 20, environment: environment)
    require(agentScan.status == 0, "packaged CLI failed the deep Agent fixture")
    let object = try JSONSerialization.jsonObject(with: agentScan.stdout) as! [String: Any]
    let scan = object["scan"] as! [String: Any]
    let modules = scan["modules"] as! [[String: Any]]
    let restrictions = modules.first?["limitations"] as? [[String: Any]] ?? []
    require(scan["scan_status"] as? String == "partial" && modules.first?["state"] as? String == "limited"
            && restrictions.contains { ($0["path"] as? String)?.hasSuffix("/.codex/a/b/c/d/e/f/g/h/") == true
                || ($0["path"] as? String)?.hasSuffix("/.codex/a/b/c/d/e/f/g/h") == true },
            "packaged CLI must identify its actual depth truncation, not claim complete")
    require(!manager.fileExists(atPath: home.appendingPathComponent("Library/Application Support/SuperCleaner").path),
            "Agent completeness reporting must not persist application state")
    print("PASS: packaged CLI JSON, command errors and read-only behavior")
}
