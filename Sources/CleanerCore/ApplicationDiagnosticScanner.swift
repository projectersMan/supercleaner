import Foundation

/// Diagnostic directories are shared by many apps. Only individual regular files
/// with validated identity evidence can become opt-in uninstall associations.
public struct ApplicationDiagnosticScanner: Sendable {
    private let maximumEntries: Int
    private let maximumFileBytes: Int
    private let maximumTotalBytes: UInt64
    private let timeout: TimeInterval
    private let includeSystemRoots: Bool

    public init(maximumEntries: Int = 5_000, maximumFileBytes: Int = 2_097_152,
                maximumTotalBytes: UInt64 = 33_554_432, timeout: TimeInterval = 5, includeSystemRoots: Bool = true) {
        self.maximumEntries = max(0, maximumEntries)
        self.maximumFileBytes = max(1, maximumFileBytes)
        self.maximumTotalBytes = maximumTotalBytes
        self.timeout = max(0, timeout)
        self.includeSystemRoots = includeSystemRoots
    }

    private struct Root {
        let url: URL
        let records: Bool
        let system: Bool
    }
    private static func roots(home: URL) -> [Root] {
        ApplicationAssociationPathRegistry.diagnosticRoots(home: home).map {
            Root(url: $0.url, records: $0.url.path.hasSuffix("/Application Support/CrashReporter"), system: $0.isSystem)
        }
    }
    static func isDiagnosticDirectory(_ url: URL, home: URL) -> Bool {
        roots(home: home).contains { root in
            url.standardizedFileURL.path == root.url.standardizedFileURL.path
                || url.standardizedFileURL.path == root.url.appendingPathComponent("Retired").standardizedFileURL.path
        }
    }

    private struct AppIdentity {
        let app: InstalledApplication
        let names: Set<String>
        let executable: String?
    }
    private struct ReportIdentity {
        var identifiers = Set<String>()
        var paths = Set<String>()
        var names = Set<String>()
        var malformed = false
    }

    public func scan(applications: [InstalledApplication], context: ScanContext) async -> ApplicationAssociationIndex {
        var output: [URL: [ApplicationAssociation]] = [:]
        var scanned: [URL] = [], unavailable: [URL] = []
        var limited = false
        var entries = 0
        var bytes: UInt64 = 0
        let deadline = Date().addingTimeInterval(timeout)
        var identities: [AppIdentity] = []
        for app in applications {
            if Task.isCancelled || Date() >= deadline { limited = true; break }
            var names = Set([app.name.lowercased(), app.id.deletingPathExtension().lastPathComponent.lowercased()])
            var executable: String?
            let info = app.id.appendingPathComponent("Contents/Info.plist")
            if await context.fileSystem.fileExists(info),
               info.resolvingSymlinksInPath().path == info.standardizedFileURL.path,
               let data = try? await context.fileSystem.readData(at: info, maximumBytes: 262_144),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               (plist["CFBundleIdentifier"] as? String) == app.bundleIdentifier,
               let value = plist["CFBundleExecutable"] as? String, !value.isEmpty,
               !value.contains("/"), !value.contains("\\"), value != ".", value != ".." {
                executable = value.lowercased(); names.insert(value.lowercased())
            }
            identities.append(AppIdentity(app: app, names: names, executable: executable))
        }
        // Ambiguous names/copies must be considered across the entire inventory.
        guard identities.count == applications.count else {
            return .init(associations: [:], coverage: .init(budgetLimitedModules: [.applications]))
        }
        var queue = Self.roots(home: context.homeDirectory).filter { includeSystemRoots || !$0.system }
        while !queue.isEmpty {
            let root = queue.removeFirst()
            guard !Task.isCancelled, Date() < deadline else { limited = true; break }
            guard await context.fileSystem.fileExists(root.url) else { continue }
            do {
                guard try await context.fileSystem.identity(at: root.url).kind == .directory,
                      root.url.resolvingSymlinksInPath().path == root.url.standardizedFileURL.path else {
                    unavailable.append(root.url); continue
                }
                let children = try await context.fileSystem.children(of: root.url)
                scanned.append(root.url)
                for file in children.sorted(by: { $0.path < $1.path }) {
                    guard (!context.enforcesEntryBudgets || entries < maximumEntries), Date() < deadline, !Task.isCancelled else { limited = true; break }
                    entries += 1
                    let identity: FileIdentity
                    do { identity = try await context.fileSystem.identity(at: file) }
                    catch { unavailable.append(file); continue }
                    if identity.kind == .directory, !root.records, file.lastPathComponent == "Retired", root.url.lastPathComponent != "Retired" {
                        queue.append(Root(url: file, records: false, system: root.system)); continue
                    }
                    guard identity.kind == .file,
                          file.resolvingSymlinksInPath().path == file.standardizedFileURL.path else { continue }
                    let ext = file.pathExtension.lowercased()
                    guard root.records ? ext == "plist" : ["ips", "crash"].contains(ext) else { continue }
                    guard identity.size <= UInt64(maximumFileBytes) else { unavailable.append(file); continue }
                    guard identity.size <= maximumTotalBytes - bytes else { limited = true; break }
                    bytes += identity.size
                    let data: Data
                    do {
                        data = try await context.fileSystem.readData(at: file, maximumBytes: maximumFileBytes)
                        guard try await context.fileSystem.identity(at: file) == identity else { unavailable.append(file); continue }
                    } catch { unavailable.append(file); continue }
                    if root.records {
                        guard let name = Self.recordName(file.lastPathComponent) else { continue }
                        let candidates = identities.filter { $0.names.contains(name) }
                        guard !candidates.isEmpty else { continue }
                        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                        let valid = plist.map { fields in
                            !fields.isEmpty && fields.allSatisfy { key, value in
                                (key == "Date" || key == "ForceQuitDate") && value is Date
                            }
                        } ?? false
                        if !valid { unavailable.append(file) }
                        for owner in candidates {
                            let verified = valid && owner.executable == name
                            output[owner.app.id, default: []].append(.init(url: file, kind: .diagnosticReport,
                                ownershipEvidence: verified ? "崩溃记录文件名、UUID 格式及应用可执行名称一致" : "诊断文件仅有名称线索，归属尚未确认",
                                containsUserData: false, isShared: false,
                                risk: verified && !owner.app.isRunning ? .review : .blocked,
                                ownershipBasis: verified ? .crashReporterRecord : .diagnosticNameOnly))
                        }
                    } else {
                        let report = Self.reportIdentity(data, extension: ext)
                        if report.malformed { unavailable.append(file) }
                        let byID = identities.filter { report.identifiers.contains($0.app.bundleIdentifier.lowercased()) }
                        let byPath = identities.filter { owner in report.paths.contains { Self.path($0, belongsTo: owner.app.id) } }
                        var candidates = Set((byID + byPath).map { $0.app.id })
                        // Filename/name evidence only fills the review list when
                        // no installed app matches a structured identity.
                        if candidates.isEmpty {
                            let fileName = Self.reportName(file.lastPathComponent)
                            candidates = Set(identities.filter { owner in
                                !owner.names.isDisjoint(with: report.names) || fileName.map(owner.names.contains) == true
                            }.map { $0.app.id })
                        }
                        for owner in identities where candidates.contains(owner.app.id) {
                            let id = owner.app.bundleIdentifier.lowercased()
                            let conflict = report.identifiers.count > 1
                                || (!report.identifiers.isEmpty && !report.identifiers.contains(id))
                                || byPath.contains { $0.app.bundleIdentifier.lowercased() != id }
                            let verified = !report.malformed && !conflict
                                && (report.identifiers == [id] || (report.identifiers.isEmpty && byPath.contains { $0.app.id == owner.app.id }))
                            output[owner.app.id, default: []].append(.init(url: file, kind: .diagnosticReport,
                                ownershipEvidence: verified ? "诊断报告内的应用标识或进程路径匹配" : "诊断文件身份缺失或冲突，归属尚未确认",
                                containsUserData: false, isShared: false,
                                risk: verified && !root.system && !owner.app.isRunning ? .review : .blocked,
                                isSystemResource: root.system,
                                ownershipBasis: verified ? .diagnosticReportIdentity : .diagnosticNameOnly))
                        }
                    }
                }
            } catch { unavailable.append(root.url) }
            if limited { break }
        }
        return .init(associations: output, coverage: .init(scannedRoots: scanned, unavailableRoots: unavailable, budgetLimitedModules: limited ? [.applications] : []))
    }

    private static func recordName(_ name: String) -> String? {
        guard name.hasSuffix(".plist") else { return nil }
        let stem = String(name.dropLast(6))
        guard let separator = stem.lastIndex(of: "_") else { return nil }
        let uuid = String(stem[stem.index(after: separator)...])
        guard uuid.count == 36, UUID(uuidString: uuid) != nil else { return nil }
        let prefix = String(stem[..<separator]).lowercased()
        return prefix.isEmpty ? nil : prefix
    }
    private static func reportName(_ name: String) -> String? {
        let pattern = #"^(.+?)[_-]\d{4}-\d{2}-\d{2}-\d{6}(?:[_-][A-Za-z0-9.-]+)?\.(?:ips|crash)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range]).lowercased()
    }
    private static func path(_ path: String, belongsTo app: URL) -> Bool {
        guard path.hasPrefix("/"), !path.contains("*"), !path.split(separator: "/").contains("..") else { return false }
        return ApplicationOwnershipGraphBuilder.isWithin(path, app.standardizedFileURL.path)
            || ApplicationOwnershipGraphBuilder.isWithin(URL(fileURLWithPath: path).resolvingSymlinksInPath().path, app.resolvingSymlinksInPath().path)
    }
    private static func reportIdentity(_ data: Data, extension ext: String) -> ReportIdentity {
        var result = ReportIdentity()
        guard let text = String(data: data, encoding: .utf8) else { result.malformed = true; return result }
        func add(_ value: Any?, to set: inout Set<String>, lowercase: Bool = true) {
            guard let value = value as? String, !value.isEmpty else { return }
            set.insert(lowercase ? value.lowercased() : value)
        }
        if ext == "ips" {
            var objects: [[String: Any]] = []
            if let whole = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                objects = [whole]
            } else if let newline = text.firstIndex(of: "\n"),
                      let header = (try? JSONSerialization.jsonObject(with: Data(text[..<newline].utf8))) as? [String: Any],
                      let body = (try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8))) as? [String: Any] {
                objects = [header, body]
            } else { result.malformed = true; return result }
            for object in objects {
                add(object["bundleID"], to: &result.identifiers)
                add((object["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"], to: &result.identifiers)
                add(object["procPath"], to: &result.paths, lowercase: false)
                add(object["app_name"], to: &result.names)
                add(object["procName"], to: &result.names)
            }
        } else {
            // Only parse the leading report header, never stack frames or loaded
            // libraries (which mention many unrelated applications).
            for line in text.components(separatedBy: .newlines).prefix(80) {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[..<colon])
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "Identifier": add(value, to: &result.identifiers)
                case "Path": add(value, to: &result.paths, lowercase: false)
                case "Process": add(value.components(separatedBy: " [").first, to: &result.names)
                default: break
                }
            }
        }
        return result
    }
}
