import Foundation

/// Reads only bounded package metadata and the declared Electron entry point. No
/// application code is evaluated. This recognizes a deliberately small expression
/// grammar; unfamiliar/dynamic paths are not guessed.
public struct ApplicationDataDiscovery: Sendable {
    public init() {}

    public func associations(for application: InstalledApplication, context: ScanContext) async -> [ApplicationAssociation] {
        guard !application.isSystem, !Task.isCancelled,
              await context.fileSystem.fileExists(application.bundleURL),
              (try? await context.fileSystem.identity(at: application.bundleURL))?.kind == .directory else { return [] }
        let resources = application.bundleURL.appendingPathComponent("Contents/Resources")
        do {
            let package: Data
            let source: Data
            let origin: String
            let archiveURL = resources.appendingPathComponent("app.asar")
            if await context.fileSystem.fileExists(archiveURL) {
                let archive = try BoundedAsarReader(url: archiveURL, bundle: application.bundleURL)
                package = try archive.read("package.json", maximumBytes: 262_144)
                let main = try Self.mainFile(package)
                source = try archive.read(main, maximumBytes: 16_777_216)
                origin = archiveURL.path + "/" + main
            } else {
                let root = resources.appendingPathComponent("app")
                package = try Self.readFile(root.appendingPathComponent("package.json"), within: application.bundleURL, maximumBytes: 262_144)
                let main = try Self.mainFile(package)
                let url = root.appendingPathComponent(main)
                source = try Self.readFile(url, within: application.bundleURL, maximumBytes: 16_777_216)
                origin = url.path
            }
            guard !Task.isCancelled, let text = String(data: source, encoding: .utf8) else { return [] }
            let names = Self.declaredDirectoryNames(in: text)
            // Multiple explicit targets can describe migrations or development
            // profiles. Do not promote those ambiguous declarations to ownership.
            guard names.count == 1, let name = names.first else { return [] }
            let root = context.homeDirectory.appendingPathComponent("Library/Application Support")
            let url = root.appendingPathComponent(name)
            guard await context.fileSystem.fileExists(url),
                  (try? await context.fileSystem.identity(at: url))?.kind == .directory,
                  url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
                  (try? context.pathPolicy.validateCandidate(url)) != nil else { return [] }
            return [ApplicationAssociation(url: url, kind: .applicationSupport,
                ownershipEvidence: "应用包明确声明用户数据目录", containsUserData: true,
                isShared: false, risk: application.isRunning ? .blocked : .review,
                ownershipBasis: .bundleDataDeclaration, declarationSource: origin)]
        } catch { return [] }
    }

    private static func mainFile(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DiscoveryError.invalidPackage }
        let main = (json["main"] as? String) ?? "index.js"
        let path = main.hasPrefix("./") ? String(main.dropFirst(2)) : main
        guard safeRelativePath(path), ["js", "cjs", "mjs"].contains(URL(fileURLWithPath: path).pathExtension) else { throw DiscoveryError.invalidPackage }
        return path
    }

    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    static func readFile(_ url: URL, within bundle: URL, maximumBytes: Int) throws -> Data {
        guard ApplicationOwnershipGraphBuilder.isWithin(url.standardizedFileURL.path, bundle.standardizedFileURL.path),
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]).fileSize,
              size <= maximumBytes, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw DiscoveryError.invalidPackage }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw DiscoveryError.invalidPackage }
        return data
    }

    static func declaredDirectoryNames(in source: String) -> Set<String> {
        // Accept app.setPath('userData', [process.env.X ||] path.join(
        // app.getPath('appData'), 'literal')), including bundler (0,path.join).
        let identifier = #"[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*"#
        let pattern = "(" + identifier + #")\.setPath\(\s*(['"`])userData\2\s*,\s*(?:process\.env\.[A-Za-z_][A-Za-z0-9_]*\s*\|\|\s*)?(?:\(\s*0\s*,\s*"# + identifier + #"\.join\s*\)|"# + identifier + #"\.join)\(\s*\1\.getPath\(\s*(['"`])appData\3\s*\)\s*,\s*(['"`])([^'"`\\$\r\n/]+)\4\s*\)\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        // Never search the entire minified program with this expression. A long
        // identifier makes an unanchored match retry all its suffixes. Find the
        // literal call first, then match one bounded receiver/expression window.
        var matches: [NSTextCheckingResult] = []
        var offset = 0
        var calls = 0
        let deadline = Date().addingTimeInterval(1)
        func receiverUnit(_ c: unichar) -> Bool {
            c == 46 || c == 36 || c == 95 || (65...90).contains(c)
                || (97...122).contains(c) || (48...57).contains(c)
        }
        while offset < ns.length {
            guard !Task.isCancelled, Date() < deadline, calls < 1_024 else { return [] }
            let call = ns.range(of: ".setPath(", range: NSRange(location: offset, length: ns.length - offset))
            guard call.location != NSNotFound else { break }
            calls += 1
            offset = NSMaxRange(call)
            var start = call.location
            while start > 0, call.location - start <= 512, receiverUnit(ns.character(at: start - 1)) { start -= 1 }
            guard start < call.location, call.location - start <= 512 else { continue }
            let window = NSRange(location: start, length: min(4_096, ns.length - start))
            if let match = regex.firstMatch(in: source, options: [.anchored], range: window) { matches.append(match) }
        }
        guard !matches.isEmpty else { return [] }
        // A lexer is needed here: minified entry points include comments, regular
        // expressions, and nested template interpolations. Matching text inside
        // any of their literal portions must never establish ownership.
        let codeOffsets = JavaScriptCodeOffsets(source: source, candidates: Set(matches.map { $0.range.location })).scan()
        var result = Set<String>()
        for match in matches where codeOffsets.contains(match.range.location) {
            let name = ns.substring(with: match.range(at: 5))
            if safeRelativePath(name), !name.hasPrefix("."), name.trimmingCharacters(in: .whitespaces) == name {
                result.insert(name)
            }
        }
        return result
    }
}

private enum DiscoveryError: Error { case invalidPackage }

private final class BoundedAsarReader {
    private let handle: FileHandle
    private let files: [String: Any]
    private let base: UInt64
    private let size: UInt64

    init(url: URL, bundle: URL) throws {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              ApplicationOwnershipGraphBuilder.isWithin(url.path, bundle.path),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw DiscoveryError.invalidPackage }
        handle = try FileHandle(forReadingFrom: url)
        do {
            size = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
            guard let prefix = try handle.read(upToCount: 16), prefix.count == 16 else { throw DiscoveryError.invalidPackage }
            func word(_ i: Int) -> UInt64 { (0..<4).reduce(0) { $0 | UInt64(prefix[i + $1]) << ($1 * 8) } }
            let headerSize = word(4), jsonSize = word(12)
            guard word(0) == 4, headerSize >= 8, headerSize <= 4_194_304,
                  jsonSize <= headerSize - 8, 8 + headerSize <= size,
                  let header = try handle.read(upToCount: Int(jsonSize)), header.count == Int(jsonSize),
                  let json = try JSONSerialization.jsonObject(with: header) as? [String: Any],
                  let tree = json["files"] as? [String: Any] else { throw DiscoveryError.invalidPackage }
            base = 8 + headerSize
            files = tree
        } catch { try? handle.close(); throw error }
    }
    deinit { try? handle.close() }

    func read(_ path: String, maximumBytes: Int) throws -> Data {
        guard ApplicationDataDiscovery.safeRelativePath(path) else { throw DiscoveryError.invalidPackage }
        var node: [String: Any] = ["files": files]
        for part in path.split(separator: "/") {
            guard let children = node["files"] as? [String: Any], let child = children[String(part)] as? [String: Any], child["link"] == nil else { throw DiscoveryError.invalidPackage }
            node = child
        }
        guard node["unpacked"] as? Bool != true,
              let offsetText = node["offset"] as? String, let offset = UInt64(offsetText),
              let length = node["size"] as? Int, length >= 0, length <= maximumBytes,
              offset <= size - base, UInt64(length) <= size - base - offset else { throw DiscoveryError.invalidPackage }
        try handle.seek(toOffset: base + offset)
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else { throw DiscoveryError.invalidPackage }
        return data
    }
}

/// Lexical context only, never JavaScript evaluation. Unsupported/malformed
/// literals stop the scan instead of treating their contents as executable code.
private final class JavaScriptCodeOffsets {
    let units: [UInt16]
    let candidates: Set<Int>
    var found = Set<Int>()
    let maximumOffset: Int
    var i = 0
    init(source: String, candidates: Set<Int>) {
        units = Array(source.utf16); self.candidates = candidates
        maximumOffset = candidates.max() ?? -1
    }
    func scan() -> Set<Int> { code(templateExpression: false, depth: 0); return found }
    func identifier(_ c: UInt16) -> Bool { c >= 128 || c == 36 || c == 95 || (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) }
    func quoted(_ quote: UInt16) {
        i += 1
        while i < units.count {
            if units[i] == 92 { i += 2; continue }
            if units[i] == quote { i += 1; return }
            if units[i] == 10 || units[i] == 13 { i = units.count; return }
            i += 1
        }
    }
    func template(depth: Int) {
        guard depth < 64 else { i = units.count; return }
        i += 1
        while i < units.count {
            if units[i] == 92 { i += 2; continue }
            if units[i] == 96 { i += 1; return }
            if units[i] == 36 && i + 1 < units.count && units[i + 1] == 123 {
                i += 2; code(templateExpression: true, depth: depth + 1)
            } else { i += 1 }
        }
    }
    func code(templateExpression: Bool, depth: Int) {
        var braces = 0
        var regexAllowed = true
        var controlParen = false
        var parentheses: [Bool] = []
        while i < units.count && i <= maximumOffset {
            if Task.isCancelled { i = units.count; return }
            if candidates.contains(i) { found.insert(i) }
            let c = units[i]
            if c <= 32 { i += 1; continue }
            if c == 34 || c == 39 { quoted(c); regexAllowed = false; continue }
            if c == 96 { template(depth: depth); regexAllowed = false; continue }
            if c == 47 && i + 1 < units.count {
                let next = units[i + 1]
                if next == 47 { while i < units.count && units[i] != 10 { i += 1 }; continue }
                if next == 42 {
                    i += 2
                    while i + 1 < units.count && !(units[i] == 42 && units[i + 1] == 47) { i += 1 }
                    i += 2; continue
                }
                if regexAllowed {
                    i += 1
                    var characterClass = false
                    while i < units.count {
                        if units[i] == 92 { i += 2; continue }
                        if units[i] == 10 || units[i] == 13 { i = units.count; return }
                        if units[i] == 91 { characterClass = true }
                        if units[i] == 93 { characterClass = false }
                        if units[i] == 47 && !characterClass { i += 1; break }
                        i += 1
                    }
                    while i < units.count && identifier(units[i]) { i += 1 }
                    regexAllowed = false; continue
                }
                i += next == 61 ? 2 : 1; regexAllowed = true; continue
            }
            if identifier(c) {
                let start = i
                while i < units.count && identifier(units[i]) { i += 1 }
                let word = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
                controlParen = ["if", "while", "for", "with", "switch", "catch"].contains(word)
                regexAllowed = ["return", "throw", "case", "delete", "void", "typeof", "new", "in", "of", "instanceof", "yield", "await", "else", "do"].contains(word)
                continue
            }
            switch c {
            case 40: parentheses.append(controlParen); controlParen = false; regexAllowed = true
            case 41: regexAllowed = parentheses.popLast() ?? false
            case 123: braces += 1; regexAllowed = true
            case 125:
                if templateExpression && braces == 0 { i += 1; return }
                braces = max(0, braces - 1); regexAllowed = true
            case 93: regexAllowed = false
            case 46: regexAllowed = false
            case 43, 45:
                if i + 1 < units.count && units[i + 1] == c { i += 1; regexAllowed = false }
                else { regexAllowed = true }
            default: regexAllowed = true
            }
            i += 1
        }
    }
}
