import CleanerCore
import Foundation

func runPathPolicyContracts() throws {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let policy = PathPolicy(homeDirectory: home)

    for path in ["/", "/System", "/Users", "/tmp/../System", "/tmp/a\nb"] {
        do {
            _ = try policy.validateCandidate(URL(fileURLWithPath: path))
            require(false, "protected path was accepted: \(path)")
        } catch is PathPolicyError {
            // Expected.
        }
    }

    for path in [".codex", ".claude", ".codex/auth.json", ".claude/settings.json"] {
        do {
            _ = try policy.validateCandidate(home.appendingPathComponent(path))
            require(false, "Agent root or sensitive asset was accepted: \(path)")
        } catch is PathPolicyError {
            // Expected.
        }
    }

    let cache = home.appendingPathComponent("Library/Caches/com.example/cache.db")
    let validatedCache = try policy.validateCandidate(cache)
    require(validatedCache.literal == cache.standardizedFileURL, "cache descendant should be valid")

    _ = try policy.validateCandidate(home.appendingPathComponent(".claude/.mcp.json"))
    _ = try policy.validateCandidate(home.appendingPathComponent("Projects/example/.mcp.json"))
    do {
        _ = try policy.validateCandidate(home.appendingPathComponent(".claude/auth.json"))
        require(false, "Agent credentials must remain protected")
    } catch is PathPolicyError {
        // Expected.
    }

    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let link = temporaryRoot.appendingPathComponent("looks-like-cache")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
    do {
        _ = try policy.validateCandidate(link)
        require(false, "symlink resolving into /System was accepted")
    } catch is PathPolicyError {
        // Expected.
    }

    _ = try policy.validateApplicationBundle(URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true))
    _ = try policy.validateApplicationBundle(URL(fileURLWithPath: "/Applications/Nested/Example.app", isDirectory: true))
    for invalidApp in ["/Applications/Outer.app/Contents/Inner.app", "/System/Applications/Example.app", "/Applications/Example"] {
        do {
            _ = try policy.validateApplicationBundle(URL(fileURLWithPath: invalidApp))
            require(false, "invalid application bundle boundary was accepted: \(invalidApp)")
        } catch is PathPolicyError {
            // Expected.
        }
    }
}
