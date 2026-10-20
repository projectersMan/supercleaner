import Foundation
import Security

/// Read-only installation evidence. No brew/pkgutil/Steam/uninstaller commands
/// are executed. A receipt can identify an installer but never grants deletion.
public struct LocalApplicationInstallationInspector: ApplicationInstallationInspecting {
    private let caskRoots: [URL]
    private let receiptRoots: [URL]
    private let steamRoots: [URL]?
    private let maximumEntries: Int
    private let timeout: TimeInterval
    public init(caskRoots: [URL] = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"), URL(fileURLWithPath: "/usr/local/Caskroom")], receiptRoots: [URL] = [URL(fileURLWithPath: "/var/db/receipts"), URL(fileURLWithPath: "/Library/Receipts")], steamRoots: [URL]? = nil, maximumEntries: Int = 10_000, timeout: TimeInterval = 15) {
        self.caskRoots = caskRoots; self.receiptRoots = receiptRoots; self.steamRoots = steamRoots
        self.maximumEntries = max(1, maximumEntries); self.timeout = max(0.05, timeout)
    }

    public func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary) {
        var result: [URL: ApplicationInstallation] = [:]
        var scanned: [URL] = []
        var unavailable: [URL] = []
        var remaining = maximumEntries
        var limited = false
        let deadline = Date().addingTimeInterval(timeout)
        var directoryEntries: [URL: [URL]] = [:]
        func hasBudget() -> Bool { !Task.isCancelled && remaining > 0 && Date() < deadline }

        for root in caskRoots {
            guard await context.fileSystem.fileExists(root) else { continue }
            var queue: [(URL, Int)] = [(root, 0)]
            while !queue.isEmpty {
                guard hasBudget() else { limited = true; break }
                let (directory, depth) = queue.removeLast()
                guard let children = try? await context.fileSystem.children(of: directory) else { unavailable.append(directory); continue }
                scanned.append(directory)
                for child in children {
                    guard hasBudget() else { limited = true; break }
                    remaining -= 1
                    guard let identity = try? await context.fileSystem.identity(at: child) else { unavailable.append(child); continue }
                    if identity.kind == .directory, depth < 6, child.pathExtension.lowercased() != "app" {
                        queue.append((child, depth + 1)); continue
                    }
                    guard identity.kind == .file, child.pathExtension.lowercased() == "json", child.path.contains("/.metadata/") else { continue }
                    do {
                        let data = try await context.fileSystem.readData(at: child, maximumBytes: 2_097_152)
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["token"] as? String,
                              let artifacts = json["artifacts"] as? [[String: Any]] else { continue }
                        for artifact in artifacts {
                            guard let app = artifact["app"] as? [Any], let source = app.first as? String else { continue }
                            let options = app.dropFirst().compactMap { $0 as? [String: Any] }.first
                            let name = (options?["target"] as? String) ?? URL(fileURLWithPath: source).lastPathComponent
                            let target = name.hasPrefix("/") ? URL(fileURLWithPath: name) : nil
                            for application in applications {
                                let standardParents = ["/Applications", context.homeDirectory.appendingPathComponent("Applications").path]
                                let isManagedPath = target.map { $0.standardizedFileURL.path == application.id.standardizedFileURL.path }
                                    ?? (standardParents.contains(application.id.deletingLastPathComponent().path) && application.id.lastPathComponent == name)
                                let physical = application.id.resolvingSymlinksInPath().path
                                if isManagedPath || ApplicationOwnershipGraphBuilder.isWithin(physical, root.appendingPathComponent(token).path) {
                                    result[application.id] = .init(source: .homebrew, identifier: token, receipts: [child])
                                }
                            }
                        }
                    } catch { unavailable.append(child) }
                }
            }
        }

        // BOM directory paths are authoritative associations with a receipt;
        // matching only the package identifier or display name is not sufficient.
        for root in receiptRoots {
            guard await context.fileSystem.fileExists(root) else { continue }
            guard let children = try? await context.fileSystem.children(of: root) else { unavailable.append(root); continue }
            scanned.append(root)
            for receipt in children.sorted(by: { $0.path < $1.path }) where receipt.pathExtension.lowercased() == "plist" {
                guard hasBudget() else { limited = true; break }
                remaining -= 1
                do {
                    let data = try await context.fileSystem.readData(at: receipt, maximumBytes: 1_048_576)
                    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          let identifier = plist["PackageIdentifier"] as? String else { continue }
                    let bom = receipt.deletingPathExtension().appendingPathExtension("bom")
                    guard await context.fileSystem.fileExists(bom) else { continue }
                    guard (try await context.fileSystem.identity(at: bom)).kind == .file else { unavailable.append(bom); continue }
                    let output = try await BoundedProcess.run("/usr/bin/lsbom", arguments: ["-s", "-d", bom.path], timeout: min(2, max(0.05, deadline.timeIntervalSinceNow)), maximumOutputBytes: 2_097_152)
                    guard output.status == 0, let paths = String(data: output.stdout, encoding: .utf8) else { unavailable.append(bom); continue }
                    let prefix = plist["InstallPrefixPath"] as? String ?? "/"
                    let base = URL(fileURLWithPath: prefix.hasPrefix("/") ? prefix : "/" + prefix)
                    for path in paths.split(separator: "\n") where path.lowercased().hasSuffix(".app") {
                        guard !path.split(separator: "/").contains("..") else { continue }
                        let url = base.appendingPathComponent(String(path)).standardizedFileURL
                        for app in applications where app.id.standardizedFileURL.path == url.path {
                            if result[app.id]?.source == .homebrew { continue }
                            let prior = result[app.id]?.receipts ?? []
                            result[app.id] = .init(source: .packageInstaller, identifier: identifier, receipts: prior + [receipt, bom])
                        }
                    }
                } catch { unavailable.append(receipt) }
            }
        }

        let steam = steamRoots ?? [context.homeDirectory.appendingPathComponent("Library/Application Support/Steam/steamapps")]
        var expandedSteam = steam
        for root in steam {
            let libraries = root.appendingPathComponent("libraryfolders.vdf")
            if await context.fileSystem.fileExists(libraries) {
                do {
                    let text = try await context.fileSystem.readText(at: libraries, maximumBytes: 1_048_576)
                    expandedSteam += Self.vdfValues(key: "path", text: text).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("steamapps") }
                    scanned.append(libraries)
                } catch { unavailable.append(libraries) }
            }
        }
        for root in Set(expandedSteam) {
            guard await context.fileSystem.fileExists(root) else { continue }
            guard let children = try? await context.fileSystem.children(of: root) else { unavailable.append(root); continue }
            scanned.append(root)
            for manifest in children where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension.lowercased() == "acf" {
                guard hasBudget() else { limited = true; break }
                remaining -= 1
                do {
                    let text = try await context.fileSystem.readText(at: manifest, maximumBytes: 1_048_576)
                    guard let directory = Self.vdfValues(key: "installdir", text: text).first, !directory.contains("/"), directory != ".", directory != ".." else { continue }
                    let common = root.appendingPathComponent("common/" + directory)
                    for app in applications where ApplicationOwnershipGraphBuilder.isWithin(app.id.path, common.path) {
                        result[app.id] = .init(source: .steam, identifier: Self.vdfValues(key: "appid", text: text).first, receipts: [manifest])
                    }
                } catch { unavailable.append(manifest) }
            }
        }

        let metadata = BundleApplicationMetadataProvider()
        for app in applications {
            guard hasBudget() else { limited = true; break }
            remaining -= 1
            var installation = result[app.id] ?? .init()
            let receipt = app.id.appendingPathComponent("Contents/_MASReceipt/receipt")
            if installation.source == .unknown, await context.fileSystem.fileExists(receipt) {
                installation = .init(source: .appStore, receipts: [receipt])
            }
            // Only app-bundle uninstallers with a verified matching team are
            // offered. Shell scripts and names alone never gain launch authority.
            var candidates: [URL] = []
            for root in [app.id.appendingPathComponent("Contents/Resources"), app.id.deletingLastPathComponent()] {
                let children: [URL]
                if let cached = directoryEntries[root] { children = cached }
                else { children = (try? await context.fileSystem.children(of: root)) ?? []; directoryEntries[root] = children }
                if children.count > 2_000 { limited = true }
                candidates += children.prefix(2_000).filter { $0.pathExtension.lowercased() == "app" && $0.lastPathComponent.lowercased().contains("uninstall") }
            }
            let uninstaller = app.teamIdentifier.flatMap { team in
                candidates.first { candidate in
                    guard ApplicationOwnershipGraphBuilder.isWithin(candidate.path, app.id.path)
                        || candidate.lastPathComponent.localizedCaseInsensitiveContains(app.name) else { return false }
                    guard candidate != app.id, let facts = metadata.metadata(for: candidate), facts.teamIdentifier == team else { return false }
                    // A sibling tool must name the product; a generic vendor-wide
                    // tool is not attributed to every application from that team.
                    return ApplicationOwnershipGraphBuilder.isWithin(candidate.path, app.id.path)
                        || candidate.lastPathComponent.localizedCaseInsensitiveContains(app.name)
                }
            }
            result[app.id] = .init(source: installation.source, identifier: installation.identifier, receipts: installation.receipts, officialUninstaller: uninstaller)
        }
        if limited {
            // Unknown is explicitly unknown, never a claim that no manager or
            // official uninstaller exists. Callers display coverage limitations.
            unavailable.append(contentsOf: applications.filter { result[$0.id] == nil }.map(\.id))
        }
        return (result, CoverageSummary(scannedRoots: Array(Set(scanned)).sorted { $0.path < $1.path }, unavailableRoots: Array(Set(unavailable)).sorted { $0.path < $1.path }, budgetLimitedModules: limited ? [.applications] : []))
    }

    static func steamApplicationRoots(context: ScanContext) async -> (roots: [URL], unavailable: [URL]) {
        let steam = context.homeDirectory.appendingPathComponent("Library/Application Support/Steam/steamapps")
        let config = steam.appendingPathComponent("libraryfolders.vdf")
        var roots = [steam.appendingPathComponent("common")]
        guard await context.fileSystem.fileExists(config) else { return (roots, []) }
        do {
            let text = try await context.fileSystem.readText(at: config, maximumBytes: 1_048_576)
            roots += vdfValues(key: "path", text: text).prefix(64).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("steamapps/common") }
            return (Array(Set(roots)), [])
        } catch { return (roots, [config]) }
    }

    private static func vdfValues(key: String, text: String) -> [String] {
        let pattern = "\\\"" + NSRegularExpression.escapedPattern(for: key) + "\\\"\\s+\\\"([^\\\"\\r\\n]+)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).replacingOccurrences(of: "\\\\", with: "\\") }
        }
    }
}

public enum OfficialApplicationUninstaller {
    public static func validate(_ url: URL, for application: InstalledApplication) throws {
        let provider = BundleApplicationMetadataProvider()
        guard let actual = provider.metadata(for: application.id), let team = actual.teamIdentifier,
              let uninstaller = provider.metadata(for: url), uninstaller.teamIdentifier == team,
              url.pathExtension.lowercased() == "app" else { throw ApplicationExecutionRejection.ownershipChanged }
        for target in [application.id, url] {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(target as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { throw ApplicationExecutionRejection.ownershipChanged }
        }
    }
}
