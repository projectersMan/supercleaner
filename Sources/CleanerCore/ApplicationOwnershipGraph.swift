import Foundation

/// Deliberately contains no matching text, command arguments or configuration
/// values. This is also the only reference representation exported to JSON/UI.
public struct ApplicationReferenceLocation: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case configuration, service }
    public var id: String { "\(file.path):\(line):\(kind.rawValue)" }
    public let file: URL
    public let line: Int
    public let kind: Kind
    public init(file: URL, line: Int, kind: Kind) {
        self.file = file.standardizedFileURL; self.line = max(1, line); self.kind = kind
    }
}

public struct ApplicationInstallation: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case unknown, appStore, homebrew, steam, packageInstaller }
    public let source: Source
    public let identifier: String?
    public let receipts: [URL]
    public let officialUninstaller: URL?
    public init(source: Source = .unknown, identifier: String? = nil, receipts: [URL] = [], officialUninstaller: URL? = nil) {
        self.source = source; self.identifier = identifier; self.receipts = receipts; self.officialUninstaller = officialUninstaller
    }
    public var title: String {
        switch source {
        case .unknown: return L10n.text("来源未知 / 手动安装")
        case .appStore: return "Mac App Store"
        case .homebrew: return "Homebrew Cask"
        case .steam: return "Steam"
        case .packageInstaller: return L10n.text("macOS 安装收据")
        }
    }
    public var requiresExternalUninstall: Bool { source == .homebrew || source == .steam || officialUninstaller != nil }
    public var guidance: String {
        if officialUninstaller != nil { return L10n.text("发现同签名团队的卸载应用；请先使用官方卸载器，再刷新应用清单。工具产生的修改不属于本应用的恢复记录。") }
        switch source {
        case .homebrew: return L10n.text("请使用 Homebrew 卸载此 Cask，再刷新应用清单；不执行 --zap，不替包管理器直接移动应用或关联文件。")
        case .steam: return L10n.text("请在 Steam 的管理菜单卸载此游戏，再刷新应用清单；保留游戏存档与 Steam 安装记录。")
        case .packageInstaller: return L10n.text("收据仅证明安装来源，不证明独占所有权；保留收据和系统文件，优先使用厂商卸载工具。")
        case .appStore: return L10n.text("可审查并可恢复移除应用本体；购买收据和共享容器保留，独占用户数据需单独勾选。")
        case .unknown: return L10n.text("仅审查应用本体和独占的可恢复文件；未知安装脚本不自动执行。")
        }
    }
    public var packageManagerCommand: String? {
        guard source == .homebrew, let identifier, !identifier.isEmpty,
              identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-@+._".contains($0)) }),
              !identifier.hasPrefix("-") else { return nil }
        return "brew uninstall --cask -- \(identifier)"
    }
}

public struct ApplicationOwnershipNode: Codable, Hashable, Sendable, Identifiable {
    public var id: URL { applicationURL }
    public let applicationURL: URL
    public let copies: [URL]
    public let installation: ApplicationInstallation
    public let configurationReferences: [ApplicationReferenceLocation]
    public let serviceReferences: [ApplicationReferenceLocation]?
    public let ownershipVerified: Bool?
    public var requiresExternalUninstall: Bool { installation.requiresExternalUninstall || serviceReferences?.isEmpty == false }
    public var blocksAssociationDeletion: Bool { installation.requiresExternalUninstall }
    public var guidance: String {
        if ownershipVerified == false { return L10n.text("关联范围部分受限；已确认归属且没有共享或引用的应用专属文件仍可逐项选择，其余项目继续保护。") }
        return serviceReferences?.isEmpty == false && !installation.requiresExternalUninstall
            ? L10n.text("发现启动服务或应用内后台服务定义。服务文件及仍被引用的项目继续保护；每个独占关联项会单独复核，避免连带删除。")
            : installation.guidance
    }
}

public struct ApplicationResourceOwnership: Codable, Hashable, Sendable, Identifiable {
    public var id: URL { resourceURL }
    public let resourceURL: URL
    public let kind: ApplicationAssociation.Kind
    public let owners: [URL]
    public let references: [ApplicationReferenceLocation]
    public let isSystemResource: Bool
    public let isShared: Bool
}

public struct ApplicationOwnershipGraph: Codable, Hashable, Sendable {
    public let applications: [ApplicationOwnershipNode]
    public let resources: [ApplicationResourceOwnership]
    public let coverage: CoverageSummary
    public func application(at url: URL) -> ApplicationOwnershipNode? {
        applications.first { $0.id.standardizedFileURL.path == url.standardizedFileURL.path }
    }
}

public protocol ApplicationInstallationInspecting: Sendable {
    func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary)
}

/// All ownership decisions are made here, once per inventory. The planner never
/// infers ownership again from a filename, and cannot silently discard other
/// surviving copies or the references discovered by this module.
public struct ApplicationOwnershipGraphBuilder: Sendable {
    private let installationInspector: any ApplicationInstallationInspecting
    private let configurationFiles: [URL]?
    private let additionalAssociationRoots: [ApplicationAssociationRoot]
    private let maximumEntries: Int
    private let includeSystemRoots: Bool
    private let userTemporaryDirectories: [URL]?

    public init(installationInspector: any ApplicationInstallationInspecting = LocalApplicationInstallationInspector(), configurationFiles: [URL]? = nil, additionalAssociationRoots: [ApplicationAssociationRoot] = [], maximumEntries: Int = 20_000, includeSystemRoots: Bool = true, userTemporaryDirectories: [URL]? = nil) {
        self.installationInspector = installationInspector; self.configurationFiles = configurationFiles
        self.additionalAssociationRoots = additionalAssociationRoots; self.maximumEntries = max(1, maximumEntries)
        self.includeSystemRoots = includeSystemRoots
        self.userTemporaryDirectories = userTemporaryDirectories
    }

    public func build(applications: [InstalledApplication], associations: [URL: [ApplicationAssociation]], coverage: CoverageSummary, context: ScanContext, resourceURL: URL? = nil) async -> ApplicationAssociationIndex {
        var output = associations
        var scanned = coverage.scannedRoots
        var unavailable = coverage.unavailableRoots
        var budgetLimited = coverage.budgetLimitedModules.contains(.applications)
        var referencesComplete = true
        var remaining = maximumEntries
        let deadline = Date().addingTimeInterval(20)
        let appByURL = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        var services: [(url: URL, references: [String], owners: [URL])] = []
        let diagnosticDirectories = Set(ApplicationAssociationPathRegistry.diagnosticRoots(home: context.homeDirectory).flatMap {
            [$0.url.path, $0.url.appendingPathComponent("Retired").path]
        })
        let associationRoots = ApplicationAssociationPathRegistry.roots(home: context.homeDirectory, userTemporaryDirectories: userTemporaryDirectories)
            .filter { (includeSystemRoots || !$0.isSystem) && $0.matching != .diagnostic } + additionalAssociationRoots
        let sharedRootPaths = Set(associationRoots.map { $0.url.path })
        // Modern SMAppService definitions live inside the app, not necessarily
        // /Library/LaunchDaemons. Presence is a potential registration, never a
        // claim that it is running. We cannot safely unregister another app.
        for app in applications {
            for leaf in ["LoginItems", "LaunchAgents", "LaunchDaemons", "LaunchServices"] {
                guard remaining > 0, Date() < deadline, !Task.isCancelled else { budgetLimited = true; break }
                remaining -= 1
                let root = app.bundleURL.appendingPathComponent("Contents/Library/" + leaf)
                guard await context.fileSystem.fileExists(root) else { continue }
                do {
                    guard try await context.fileSystem.identity(at: root).kind == .directory,
                          Self.isWithin(root.resolvingSymlinksInPath().path, app.bundleURL.resolvingSymlinksInPath().path) else { throw FileSystemError.unreadableContent(root) }
                    let children = try await context.fileSystem.children(of: root)
                    scanned.append(root)
                    for child in children.sorted(by: { $0.path < $1.path }) where !child.lastPathComponent.hasPrefix(".") {
                        guard remaining > 0, Date() < deadline, !Task.isCancelled else { budgetLimited = true; break }
                        remaining -= 1
                        if leaf == "LoginItems", child.pathExtension.lowercased() != "app" { continue }
                        if (leaf == "LaunchAgents" || leaf == "LaunchDaemons"), child.pathExtension.lowercased() != "plist" { continue }
                        services.append((child, [app.bundleURL.path], [app.id]))
                    }
                } catch {
                    unavailable.append(root); referencesComplete = false
                    // Unverifiable definitions cannot make body deletion safe.
                    services.append((root, [app.bundleURL.path], [app.id]))
                }
            }
            if budgetLimited { break }
        }
        for spec in associationRoots {
            if Task.isCancelled { budgetLimited = true; break }
            if let resourceURL, spec.kind != .launchAgent && spec.kind != .launchDaemon,
               !Self.isWithin(resourceURL.standardizedFileURL.path, spec.url.path) { continue }
            guard await context.fileSystem.fileExists(spec.url) else { continue }
            guard let rootIdentity = try? await context.fileSystem.identity(at: spec.url), rootIdentity.kind == .directory,
                  spec.url.resolvingSymlinksInPath().standardizedFileURL.path == spec.url.path,
                  await context.fileSystem.isReadable(spec.url), let children = try? await context.fileSystem.children(of: spec.url) else {
                unavailable.append(spec.url)
                if spec.kind == .launchAgent || spec.kind == .launchDaemon { referencesComplete = false }
                continue
            }
            scanned.append(spec.url)
            var resourcesToMatch = children.sorted(by: { $0.path < $1.path })
            for vendor in children where spec.isVendorDirectory(vendor, for: applications) {
                // Never select the vendor parent, including unreadable parents.
                resourcesToMatch.removeAll { $0.standardizedFileURL.path == vendor.standardizedFileURL.path }
                if let resourceURL, !Self.isWithin(resourceURL.standardizedFileURL.path, vendor.standardizedFileURL.path) { continue }
                guard remaining > 0, Date() < deadline, !Task.isCancelled else { budgetLimited = true; break }
                remaining -= 1
                guard let identity = try? await context.fileSystem.identity(at: vendor), identity.kind == .directory,
                      vendor.resolvingSymlinksInPath().path == vendor.standardizedFileURL.path else { continue }
                do {
                    let nested = try await context.fileSystem.children(of: vendor)
                    scanned.append(vendor)
                    resourcesToMatch += nested.sorted(by: { $0.path < $1.path })
                } catch { unavailable.append(vendor) }
                // A vendor directory is shared infrastructure even when only one
                // of its products is currently installed. Match products below it.
                resourcesToMatch.removeAll { $0.standardizedFileURL.path == vendor.standardizedFileURL.path }
            }
            for child in resourcesToMatch {
                // Final execution needs one resource's ownership. Keep scanning
                // all service definitions: another service can reference it.
                if let resourceURL, spec.kind != .launchAgent && spec.kind != .launchDaemon,
                   child.standardizedFileURL.path != resourceURL.standardizedFileURL.path { continue }
                guard remaining > 0, Date() < deadline, !Task.isCancelled else { budgetLimited = true; break }
                remaining -= 1
                if diagnosticDirectories.contains(child.standardizedFileURL.path) { continue }
                if sharedRootPaths.contains(child.standardizedFileURL.path) { continue }
                var owners = applications.filter { application in
                    child.standardizedFileURL.path != application.id.standardizedFileURL.path
                        && spec.ownership(of: child, application: application) != nil
                }.map(\.id)
                if spec.kind == .launchAgent || spec.kind == .launchDaemon {
                    do {
                        let data = try await context.fileSystem.readData(at: child, maximumBytes: 1_048_576)
                        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw FileSystemError.unreadableContent(child) }
                        // Interpret only explicit executable/path arguments. Never
                        // execute a plist, shell expression, label or script.
                        let rawPaths = ([plist["Program"] as? String].compactMap { $0 } + (plist["ProgramArguments"] as? [String] ?? []))
                            .filter { $0.hasPrefix("/") && !$0.contains("\n") }
                        let paths = Array(Set(rawPaths.flatMap { path in
                            let url = URL(fileURLWithPath: path)
                            return [url.standardizedFileURL.path, url.resolvingSymlinksInPath().standardizedFileURL.path]
                        }))
                        owners += applications.filter { app in paths.contains { Self.isWithin($0, app.bundleURL.path) } }.map(\.id)
                        services.append((child, paths, Array(Set(owners))))
                    } catch { unavailable.append(child); referencesComplete = false }
                }
                for owner in Set(owners) {
                    guard appByURL[owner] != nil else { continue }
                    let app = appByURL[owner]!
                    let basis = spec.ownership(of: child, application: app)
                    let servicePathMatch = (spec.kind == .launchAgent || spec.kind == .launchDaemon)
                        && services.contains { $0.url.standardizedFileURL == child.standardizedFileURL
                            && $0.references.contains { Self.isWithin($0, app.bundleURL.path) } }
                    let ownershipBasis: ApplicationAssociation.OwnershipBasis = servicePathMatch ? .serviceDefinition : (basis ?? .displayName)
                    let hasStrongOwnership = ownershipBasis != .displayName && ownershipBasis != .compatibilityHint
                    let reviewableOwnership = hasStrongOwnership || (spec.kind == .applicationSupport && basis == .displayName)
                    let evidence = ownershipBasis == .applicationGroup ? "应用组标识匹配"
                        : ownershipBasis == .bundleIdentifier ? "完整 Bundle ID 边界匹配"
                        : servicePathMatch ? "明确服务路径匹配"
                        : ownershipBasis == .compatibilityHint ? "兼容规则发现的关联线索，尚未确认独占归属" : "名称仅与应用显示名精确匹配"
                    let risk: RiskLevel = spec.isSystem || spec.removalPolicy == .referenceOnly
                        || ownershipBasis == .compatibilityHint || spec.kind == .sharedContainer || (spec.containsUserData && !reviewableOwnership)
                        ? .blocked : (spec.kind == .cache && ownershipBasis == .bundleIdentifier ? .safe : .review)
                    output[owner, default: []].append(ApplicationAssociation(
                        url: child, kind: spec.kind,
                        ownershipEvidence: evidence,
                        containsUserData: spec.containsUserData, isShared: spec.kind == .sharedContainer,
                        risk: risk, isSystemResource: spec.isSystem,
                        ownershipBasis: ownershipBasis, removalPolicy: ownershipBasis == .compatibilityHint ? .referenceOnly : spec.removalPolicy
                    ))
                }
            }
        }

        // Group by the literal resource path first, then union all owners and
        // copies of each Bundle ID. One surviving copy is enough to protect it.
        var resourceAssociations: [URL: [(owner: URL, association: ApplicationAssociation)]] = [:]
        for (owner, values) in output {
            for value in values { resourceAssociations[URL(fileURLWithPath: value.url.standardizedFileURL.path), default: []].append((owner, value)) }
        }
        let files = configurationFiles ?? Self.defaultConfigurationFiles(home: context.homeDirectory)
        let referenceApplications = resourceURL == nil ? applications : applications.filter { app in
            associations[app.id]?.contains { $0.url.standardizedFileURL.path == resourceURL?.standardizedFileURL.path } == true
                || output[app.id]?.contains { $0.url.standardizedFileURL.path == resourceURL?.standardizedFileURL.path } == true
        }
        if let resourceURL {
            resourceAssociations = resourceAssociations.filter { $0.key.standardizedFileURL.path == resourceURL.standardizedFileURL.path }
        }
        var appReferences: [URL: [ApplicationReferenceLocation]] = [:]
        var resourceReferences: [URL: [ApplicationReferenceLocation]] = [:]
        for file in Set(files).sorted(by: { $0.path < $1.path }) {
            if Task.isCancelled { budgetLimited = true; break }
            guard await context.fileSystem.fileExists(file) else { continue }
            guard remaining > 0, Date() < deadline else { budgetLimited = true; break }
            remaining -= 1
            do {
                let text = try await context.fileSystem.readText(at: file, maximumBytes: 1_048_576)
                scanned.append(file)
                for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    guard remaining > 0, Date() < deadline, !Task.isCancelled else { budgetLimited = true; break }
                    remaining -= 1
                    let location = ApplicationReferenceLocation(file: file, line: offset + 1, kind: .configuration)
                    for app in referenceApplications where Self.containsReference(String(line), to: app.bundleURL.path)
                        || Self.containsReference(String(line), to: app.bundleIdentifier) {
                        appReferences[app.id, default: []].append(location)
                    }
                    for resource in resourceAssociations.keys where Self.containsReference(String(line), to: resource.path) {
                        resourceReferences[resource, default: []].append(location)
                    }
                }
            } catch { unavailable.append(file); referencesComplete = false }
        }

        var resources: [ApplicationResourceOwnership] = []
        output = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, []) })
        for (url, matches) in resourceAssociations {
            guard let first = matches.first else { continue }
            var owners = Set(matches.map(\.owner))
            let ownerIDs = Set(owners.compactMap { appByURL[$0]?.bundleIdentifier.lowercased() })
            owners.formUnion(applications.filter { ownerIDs.contains($0.bundleIdentifier.lowercased()) }.map(\.id))
            var refs = resourceReferences[url, default: []]
            for service in services where service.url.standardizedFileURL != url && service.references.contains(where: { Self.isWithin($0, url.path) }) {
                refs.append(ApplicationReferenceLocation(file: service.url, line: 1, kind: .service))
                owners.formUnion(service.owners)
            }
            // A declared app group with only one installed owner is app data,
            // not shared data for uninstall purposes. Keep it reviewable; block
            // only when another installed app still owns the resource.
            let shared = owners.count > 1 || matches.contains { ($0.association.ownerBundleURLs?.count ?? 0) > 1 }
            let system = matches.contains { $0.association.isSystemResource == true }
            refs = Array(Set(refs)).sorted { $0.id < $1.id }
            let sortedOwners = owners.sorted { $0.path < $1.path }
            resources.append(ApplicationResourceOwnership(resourceURL: url, kind: first.association.kind, owners: sortedOwners, references: refs, isSystemResource: system, isShared: shared))
            for owner in owners {
                let association = matches.first {
                    $0.owner == owner && ($0.association.ownershipBasis == .bundleDataDeclaration || $0.association.ownershipEvidence.contains("完整 Bundle ID 边界"))
                }?.association ?? matches.first { $0.owner == owner }?.association ?? first.association
                let blocked = shared || system || !refs.isEmpty || appByURL[owner]?.isRunning == true
                    || matches.contains { $0.association.removalPolicy == .referenceOnly }
                output[owner, default: []].append(ApplicationAssociation(
                    url: url, kind: association.kind,
                    ownershipEvidence: association.ownershipEvidence + (shared ? "；其他应用 / 副本仍拥有此资源" : "") + (!refs.isEmpty ? "；仍有配置或服务引用" : ""),
                    containsUserData: association.containsUserData, isShared: shared,
                    // Ownership was established from an exact Bundle ID/name
                    // match before reaching this aggregation. User data remains
                    // opt-in, but a textual wording mismatch must not lock it.
                    risk: blocked ? .blocked : (association.containsUserData
                        ? (association.ownershipBasis == .bundleDataDeclaration || association.ownershipBasis == .bundleIdentifier
                            || association.ownershipBasis == .applicationGroup || association.ownershipEvidence.contains("完整 Bundle ID 边界")
                            || association.ownershipEvidence.contains("应用组标识")
                            || (association.kind == .applicationSupport && (association.ownershipBasis == .displayName || association.ownershipEvidence.contains("显示名精确匹配"))) ? .review : .blocked)
                        : association.risk),
                    ownerBundleURLs: sortedOwners, references: refs, isSystemResource: system,
                    ownershipBasis: association.ownershipBasis, declarationSource: association.declarationSource,
                    removalPolicy: matches.contains { $0.association.removalPolicy == .referenceOnly } ? .referenceOnly : association.removalPolicy
                ))
            }
        }
        let installationApplications = resourceURL == nil ? applications : applications.filter { output[$0.id]?.isEmpty == false }
        let installations = await installationInspector.installations(for: installationApplications, context: context)
        scanned += installations.coverage.scannedRoots
        unavailable += installations.coverage.unavailableRoots
        let graphCoverage = CoverageSummary(scannedRoots: Array(Set(scanned)).sorted { $0.path < $1.path }, unavailableRoots: Array(Set(unavailable)).sorted { $0.path < $1.path }, budgetLimitedModules: budgetLimited || !installations.coverage.budgetLimitedModules.isEmpty ? [.applications] : [])
        let nodes = applications.map { app in
            ApplicationOwnershipNode(applicationURL: app.id, copies: applications.filter { $0.bundleIdentifier.caseInsensitiveCompare(app.bundleIdentifier) == .orderedSame && $0.id != app.id }.map(\.id).sorted { $0.path < $1.path }, installation: installations.values[app.id] ?? .init(), configurationReferences: Array(Set(appReferences[app.id, default: []])).sorted { $0.id < $1.id }, serviceReferences: services.filter { $0.owners.contains(app.id) }.map { ApplicationReferenceLocation(file: $0.url, line: 1, kind: .service) }.sorted { $0.id < $1.id }, ownershipVerified: !budgetLimited && referencesComplete && graphCoverage.budgetLimitedModules.isEmpty && installations.coverage.unavailableRoots.isEmpty && installations.coverage.budgetLimitedModules.isEmpty)
        }
        let graph = ApplicationOwnershipGraph(applications: nodes, resources: resources.sorted { $0.id.path < $1.id.path }, coverage: graphCoverage)
        return ApplicationAssociationIndex(associations: output.mapValues { $0.sorted { $0.url.path < $1.url.path } }, coverage: graphCoverage, ownershipGraph: graph)
    }

    static func defaultConfigurationFiles(home: URL) -> [URL] {
        let shell = [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".profile", ".config/fish/config.fish"]
        let rules = AgentResourcePathRegistry.rules.filter { $0.kind == .mcpConfiguration && $0.base != .project }
        return shell.map { home.appendingPathComponent($0) } + rules.map { $0.base == .home ? home.appendingPathComponent($0.path) : URL(fileURLWithPath: $0.path) }
    }

    static func isWithin(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func containsReference(_ line: String, to value: String) -> Bool {
        guard !value.isEmpty, line.contains(value) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: value)
        // An identifier prefix or a similarly named application is not a match.
        let pattern = "(?<![A-Za-z0-9_./-])" + escaped + (value.hasPrefix("/") ? "(?=$|[/\\s\\\"'\\],;:)])" : "(?![A-Za-z0-9_.-])")
        return line.range(of: pattern, options: .regularExpression) != nil
    }
}
