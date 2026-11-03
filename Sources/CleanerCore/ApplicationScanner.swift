import Foundation
import Security

public struct InstalledApplication: Identifiable, Codable, Hashable, Sendable {
    public var id: URL { bundleURL }
    public let bundleURL: URL
    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    public let isRunning: Bool
    public let isSystem: Bool
    public let teamIdentifier: String?
    public let applicationGroups: [String]?
    public let associatedBundleIdentifiers: [String]?

    public init(bundleURL: URL, bundleIdentifier: String, name: String, version: String?, isRunning: Bool, isSystem: Bool, teamIdentifier: String? = nil, applicationGroups: [String]? = nil, associatedBundleIdentifiers: [String]? = nil) {
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.isRunning = isRunning
        self.isSystem = isSystem
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }
}

public struct ApplicationBundleMetadata: Codable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let name: String
    public let version: String?
    public let teamIdentifier: String?
    public let applicationGroups: [String]?
    public let associatedBundleIdentifiers: [String]?

    public init(bundleIdentifier: String, name: String, version: String?, teamIdentifier: String? = nil, applicationGroups: [String]? = nil, associatedBundleIdentifiers: [String]? = nil) {
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }
}

public protocol ApplicationMetadataProviding: Sendable {
    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata?
}

public struct BundleApplicationMetadataProvider: ApplicationMetadataProviding {
    public init() {}

    public func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        guard let bundle = Bundle(url: bundleURL), let identifier = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        var code: SecStaticCode?
        var signing: CFDictionary?
        var team: String?
        var groups: [String]?
        if SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code,
           SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess,
           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess,
           let facts = signing as? [String: Any] {
            team = facts[kSecCodeInfoTeamIdentifier as String] as? String
            let entitlements = facts[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
            groups = (entitlements?["com.apple.security.application-groups"] as? [String])?.sorted()
        }
        return ApplicationBundleMetadata(bundleIdentifier: identifier, name: name, version: version, teamIdentifier: team, applicationGroups: groups,
            associatedBundleIdentifiers: embeddedIdentifiers(in: bundleURL, identifier: identifier, team: team))
    }

    private func embeddedIdentifiers(in bundleURL: URL, identifier: String, team: String?) -> [String] {
        let manager = FileManager.default
        var found = Set<String>(), entries = 0
        var queue: [(URL, Int)] = ["XPCServices", "PlugIns", "Helpers", "Applications", "Library/LoginItems", "Library/LaunchServices"].map {
            (bundleURL.appendingPathComponent("Contents/" + $0), 0)
        }
        while !queue.isEmpty, entries < 512 {
            let (root, depth) = queue.removeFirst()
            guard root.resolvingSymlinksInPath().path == root.standardizedFileURL.path,
                  let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                entries += 1
                guard entries <= 512, let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true,
                      child.resolvingSymlinksInPath().path == child.standardizedFileURL.path else { continue }
                if ["app", "xpc", "appex", "bundle"].contains(child.pathExtension.lowercased()),
                   let bundle = Bundle(url: child), let childID = bundle.bundleIdentifier, childID != identifier {
                    var sameTeam = false
                    if let team {
                        var code: SecStaticCode?, info: CFDictionary?
                        if SecStaticCodeCreateWithPath(child as CFURL, [], &code) == errSecSuccess, let code,
                           SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess,
                           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                           let facts = info as? [String: Any] { sameTeam = facts[kSecCodeInfoTeamIdentifier as String] as? String == team }
                    }
                    if childID.hasPrefix(identifier + ".") || sameTeam { found.insert(childID) }
                }
                if depth < 5, child.pathExtension.lowercased() != "framework" { queue.append((child, depth + 1)) }
            }
        }
        return found.sorted()
    }
}

public struct ApplicationInventory: Codable, Hashable, Sendable {
    public let applications: [InstalledApplication]
    public let coverage: CoverageSummary
    public let scannedAt: Date

    public init(applications: [InstalledApplication], coverage: CoverageSummary, scannedAt: Date) {
        self.applications = applications
        self.coverage = coverage
        self.scannedAt = scannedAt
    }
}

public struct ApplicationAssociation: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case cache
        case applicationSupport
        case preference
        case savedState
        case launchAgent
        case container
        case sharedContainer
        case log
        case webData
        case launchDaemon
        case privilegedHelper
        case diagnosticReport
        case applicationScripts, cookies, plugin, installationReceipt, temporary, searchIndex
    }

    public enum RemovalPolicy: String, Codable, Hashable, Sendable { case recoverable, referenceOnly }
    public let removalPolicy: RemovalPolicy?

    public enum OwnershipBasis: String, Codable, Hashable, Sendable {
        case bundleDataDeclaration, diagnosticReportIdentity, crashReporterRecord, diagnosticNameOnly
        case bundleIdentifier, applicationGroup, displayName, serviceDefinition, compatibilityHint
    }
    public let ownershipBasis: OwnershipBasis?
    public let declarationSource: String?
    public var id: URL { url }
    public let url: URL
    public let kind: Kind
    public let ownershipEvidence: String
    public let containsUserData: Bool
    public let isShared: Bool
    public let risk: RiskLevel
    public let ownerBundleURLs: [URL]?
    public let references: [ApplicationReferenceLocation]?
    public let isSystemResource: Bool?

    /// Ownership matching still consumes canonical evidence. Translate only its display copy,
    /// so changing language or wording cannot change deletion eligibility.
    public var localizedOwnershipEvidence: String {
        let separator = L10n.language == .english ? "; " : "；"
        return ownershipEvidence.components(separatedBy: "；").map { L10n.text($0) }.joined(separator: separator)
    }

    public init(url: URL, kind: Kind, ownershipEvidence: String, containsUserData: Bool, isShared: Bool, risk: RiskLevel, ownerBundleURLs: [URL]? = nil, references: [ApplicationReferenceLocation]? = nil, isSystemResource: Bool = false, ownershipBasis: OwnershipBasis? = nil, declarationSource: String? = nil, removalPolicy: RemovalPolicy? = nil) {
        self.removalPolicy = removalPolicy
        self.ownershipBasis = ownershipBasis
        self.declarationSource = declarationSource
        self.url = url
        self.kind = kind
        self.ownershipEvidence = ownershipEvidence
        self.containsUserData = containsUserData
        self.isShared = isShared
        self.risk = risk
        self.ownerBundleURLs = ownerBundleURLs
        self.references = references
        self.isSystemResource = isSystemResource
    }
}

public struct ApplicationAssociationIndex: Codable, Hashable, Sendable {
    public let associations: [URL: [ApplicationAssociation]]
    public let coverage: CoverageSummary
    public let ownershipGraph: ApplicationOwnershipGraph?

    public init(
        associations: [URL: [ApplicationAssociation]],
        coverage: CoverageSummary,
        ownershipGraph: ApplicationOwnershipGraph? = nil
    ) {
        self.associations = associations
        self.coverage = coverage
        self.ownershipGraph = ownershipGraph
    }
}

public struct UninstallItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public let containsUserData: Bool
    public let isShared: Bool

    public init(candidate: CleanupCandidate, containsUserData: Bool, isShared: Bool) {
        self.candidate = candidate
        self.containsUserData = containsUserData
        self.isShared = isShared
    }
}

public struct UninstallPlan: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let application: InstalledApplication
    public let items: [UninstallItem]

    public init(id: UUID = UUID(), application: InstalledApplication, items: [UninstallItem]) {
        self.id = id
        self.application = application
        self.items = items
    }

    public var selectableItemIDs: Set<UUID> {
        Set(items.lazy.filter { item in
            item.candidate.risk.isSelectable && !item.candidate.isActive && !item.isShared
        }.map(\.id))
    }
}

public struct ApplicationScanner: Sendable {
    private let metadataProvider: any ApplicationMetadataProviding
    private let ownershipBuilder: ApplicationOwnershipGraphBuilder
    private let applicationRoots: [URL]?
    private let diagnosticScanner: ApplicationDiagnosticScanner

    public init(metadataProvider: any ApplicationMetadataProviding = BundleApplicationMetadataProvider(), ownershipBuilder: ApplicationOwnershipGraphBuilder = ApplicationOwnershipGraphBuilder(), applicationRoots: [URL]? = nil, diagnosticScanner: ApplicationDiagnosticScanner = ApplicationDiagnosticScanner()) {
        self.metadataProvider = metadataProvider
        self.ownershipBuilder = ownershipBuilder
        self.applicationRoots = applicationRoots
        self.diagnosticScanner = diagnosticScanner
    }

    public func installedApplications(
        context: ScanContext,
        runningBundleIdentifiers: Set<String> = [],
        maximumDepth: Int? = nil,
        maximumEntries: Int? = nil,
        additionalRoots: [URL] = []
    ) async -> ApplicationInventory {
        var roots = (applicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            context.homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]) + additionalRoots
        // Only local mounted volumes, and only their Applications directories or
        // root-level app bundles. Never recurse through a whole backup/network disk.
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if applicationRoots == nil, let mounted = try? await context.fileSystem.children(of: volumes) {
            for volume in mounted.prefix(context.enforcesEntryBudgets ? 64 : mounted.count) where !volume.lastPathComponent.hasPrefix(".") {
                guard let values = try? volume.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsReadOnlyKey]),
                      values.volumeIsLocal == true else { continue }
                roots.append(volume.appendingPathComponent("Applications", isDirectory: true))
                if let entries = try? await context.fileSystem.children(of: volume) {
                    roots += entries.filter { $0.pathExtension.lowercased() == "app" }
                }
            }
        }
        var applications: [InstalledApplication] = []
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        if applicationRoots == nil {
            let steam = await LocalApplicationInstallationInspector.steamApplicationRoots(context: context)
            roots += steam.roots
            unavailableRoots += steam.unavailable
        }
        var seenPaths = Set<String>()
        let normalizedMaximumDepth = maximumDepth.map { max(0, $0) }
        var remainingEntries = context.enforcesEntryBudgets ? maximumEntries.map { max(0, $0) } : nil
        var reachedLimit = false

        rootLoop: for root in roots {
            if Task.isCancelled { break }
            let standardizedRoot = root.standardizedFileURL
            guard await context.fileSystem.fileExists(standardizedRoot) else { continue }
            guard await context.fileSystem.isReadable(standardizedRoot) else {
                unavailableRoots.append(standardizedRoot)
                continue
            }
            guard seenPaths.insert(standardizedRoot.path).inserted else { continue }
            scannedRoots.append(standardizedRoot)
            var queue: [(url: URL, depth: Int)] = [(standardizedRoot, 0)]
            if standardizedRoot.pathExtension.lowercased() == "app" {
                queue = [(standardizedRoot.deletingLastPathComponent(), 0)]
            }
            var nextQueueIndex = 0

            while nextQueueIndex < queue.count {
                if Task.isCancelled { break rootLoop }
                if let remainingEntries, remainingEntries == 0 {
                    reachedLimit = true
                    break
                }
                let current = queue[nextQueueIndex]
                nextQueueIndex += 1
                let children: [URL]
                do {
                    children = try await context.fileSystem.children(of: current.url)
                } catch {
                    unavailableRoots.append(current.url)
                    continue
                }

                for child in children {
                    if standardizedRoot.pathExtension.lowercased() == "app", child.standardizedFileURL != standardizedRoot { continue }
                    if let entriesLeft = remainingEntries {
                        guard entriesLeft > 0 else {
                            reachedLimit = true
                            break
                        }
                        remainingEntries = entriesLeft - 1
                    }
                    let url = child.standardizedFileURL
                    guard seenPaths.insert(url.path).inserted else { continue }

                    if url.pathExtension.lowercased() == "app" {
                        guard let metadata = metadataProvider.metadata(for: url) else { continue }
                        applications.append(InstalledApplication(
                            bundleURL: url,
                            bundleIdentifier: metadata.bundleIdentifier,
                            name: metadata.name,
                            version: metadata.version,
                            isRunning: runningBundleIdentifiers.union(context.runningBundleIdentifiers).contains(metadata.bundleIdentifier),
                            isSystem: url.path.hasPrefix("/System/Applications/"),
                            teamIdentifier: metadata.teamIdentifier,
                            applicationGroups: metadata.applicationGroups,
                            associatedBundleIdentifiers: metadata.associatedBundleIdentifiers
                        ))
                        continue
                    }

                    guard let identity = try? await context.fileSystem.identity(at: url),
                          identity.kind == .directory,
                          identity.kind != .symbolicLink,
                          await context.fileSystem.isReadable(url)
                    else { continue }
                    if let normalizedMaximumDepth, current.depth >= normalizedMaximumDepth {
                        reachedLimit = true
                        continue
                    }
                    queue.append((url, current.depth + 1))
                }

                if reachedLimit, remainingEntries == 0 { break }
            }
            if reachedLimit, remainingEntries == 0 { break }
        }

        var uniqueByPath: [String: InstalledApplication] = [:]
        for application in applications {
            uniqueByPath[application.bundleURL.standardizedFileURL.path] = application
        }
        let sorted = uniqueByPath.values.sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame
                ? $0.bundleURL.path.localizedStandardCompare($1.bundleURL.path) == .orderedAscending
                : nameOrder == .orderedAscending
        }
        return ApplicationInventory(
            applications: sorted,
            coverage: CoverageSummary(
                scannedRoots: scannedRoots,
                unavailableRoots: unavailableRoots,
                budgetLimitedModules: reachedLimit ? [.applications] : []
            ),
            scannedAt: context.now
        )
    }

    public func associations(for application: InstalledApplication, context: ScanContext) async throws -> [ApplicationAssociation] {
        let inventory = await installedApplications(context: context, maximumDepth: 12, maximumEntries: 30_000)
        let applications = inventory.applications + (inventory.applications.contains { $0.id.path == application.id.path } ? [] : [application])
        let index = await associationIndex(for: applications, context: context)
        return index.associations.first { $0.key.path == application.id.path }?.value ?? []
    }

    public func associationIndex(
        for applications: [InstalledApplication],
        context: ScanContext,
        resourceURL: URL? = nil
    ) async -> ApplicationAssociationIndex {
        var output = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, [ApplicationAssociation]()) })
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        var limited = false
        let declarationDeadline = Date().addingTimeInterval(15)
        var declarations: [URL: [ApplicationAssociation]] = [:]
        var declarationsComplete = true
        let needsDeclarations = resourceURL == nil || resourceURL?.deletingLastPathComponent().standardizedFileURL.path
            == context.homeDirectory.appendingPathComponent("Library/Application Support").standardizedFileURL.path
        for application in needsDeclarations ? applications : [] {
            if Task.isCancelled || Date() >= declarationDeadline {
                limited = true; declarationsComplete = false; break
            }
            declarations[application.id] = await ApplicationDataDiscovery().associations(for: application, context: context)
        }
        // A truncated identity pass could miss another owner of a custom root.
        // Do not grant new deletion rights from that partial declaration set.
        if declarationsComplete {
            for (owner, values) in declarations { output[owner, default: []] += values }
        }
        // A declaration does not grant ownership of a shared search boundary.
        let sharedRootPaths = Set(ApplicationAssociationPathRegistry.roots(home: context.homeDirectory).map { $0.url.path })
        output = output.mapValues { $0.filter { !sharedRootPaths.contains($0.url.standardizedFileURL.path)
            && !ApplicationDiagnosticScanner.isDiagnosticDirectory($0.url, home: context.homeDirectory) } }
        let diagnostics = await diagnosticScanner.scan(applications: applications, context: context)
        for (owner, values) in diagnostics.associations { output[owner, default: []] += values }
        if let resourceURL {
            output = output.mapValues { $0.filter { $0.url.standardizedFileURL.path == resourceURL.standardizedFileURL.path } }
        }
        scannedRoots += diagnostics.coverage.scannedRoots
        unavailableRoots += diagnostics.coverage.unavailableRoots
        limited = limited || !diagnostics.coverage.budgetLimitedModules.isEmpty
        return await ownershipBuilder.build(
            applications: applications, associations: output,
            coverage: CoverageSummary(scannedRoots: scannedRoots, unavailableRoots: unavailableRoots, budgetLimitedModules: limited ? [.applications] : []), context: context,
            resourceURL: resourceURL
        )
    }


}

public struct UninstallPlanner: Sendable {
    private let scanner: ApplicationScanner
    public init(scanner: ApplicationScanner = ApplicationScanner()) { self.scanner = scanner }

    public func planUninstall(_ application: InstalledApplication, context: ScanContext) async throws -> UninstallPlan {
        var inventory = await scanner.installedApplications(context: context, runningBundleIdentifiers: context.runningBundleIdentifiers, maximumDepth: 12, maximumEntries: 30_000)
        if !inventory.applications.contains(where: { $0.id.path == application.id.path }) {
            inventory = ApplicationInventory(applications: inventory.applications + [application], coverage: inventory.coverage, scannedAt: inventory.scannedAt)
        }
        let index = await scanner.associationIndex(for: inventory.applications, context: context)
        let associations = index.associations.first { $0.key.path == application.id.path }?.value ?? []
        let current = inventory.applications.first { $0.id.path == application.id.path } ?? application
        return try await buildPlan(
            current,
            associations: associations,
            context: context,
            ownership: index.ownershipGraph?.application(at: application.id)
        ).plan
    }

    public func buildPlan(
        _ application: InstalledApplication,
        associations: [ApplicationAssociation],
        context: ScanContext,
        maximumSizeEntries: Int? = nil,
        ownership: ApplicationOwnershipNode? = nil
    ) async throws -> UninstallPlanBuildResult {
        var items: [UninstallItem] = []
        var remainingSizeEntries = context.enforcesEntryBudgets ? maximumSizeEntries.map { max(0, $0) } : nil
        var reachedSizeBudget = false
        var limitations: [ScanLimitation] = []
        let bundleIdentity = try await context.fileSystem.identity(at: application.bundleURL)
        let bundleBytes = try await measuredBytes(
            at: application.bundleURL,
            identity: bundleIdentity,
            remainingBudget: &remainingSizeEntries,
            reachedBudget: &reachedSizeBudget,
            limitations: &limitations,
            context: context
        )
        // The bundle is the app the user asked to uninstall. Unknown ownership,
        // package receipts, and service references restrict associated files,
        // but must not make a valid, stopped app bundle impossible to remove.
        let bundleRisk: RiskLevel = application.isRunning || application.isSystem
            || bundleIdentity.kind != .directory || application.id.path.hasPrefix("/Volumes/") ? .blocked : .review
        let bundleEvidence = application.isRunning
            ? Evidence(code: "running-app", summary: L10n.text("应用仍在运行，必须先退出"))
            : Evidence(code: "app-bundle", summary: ownership?.requiresExternalUninstall == true
                ? L10n.text("仅移除应用本体；安装来源记录和关联内容可能保留，可从恢复记录找回应用本体")
                : L10n.text("应用本体将删除，可从恢复记录找回"))
        items.append(UninstallItem(candidate: context.protectionPolicy.applying(to: CleanupCandidate(
            url: application.bundleURL,
            displayName: application.name,
            category: .application,
            bytes: bundleBytes,
            risk: bundleRisk,
            evidence: [bundleEvidence, Evidence(code: "owner-bundle", summary: application.bundleURL.path),
                       Evidence(code: "owner-bundle-id", summary: application.bundleIdentifier), Evidence(code: "owner-name", summary: application.name)]
                + (ownership?.requiresExternalUninstall == true ? [Evidence(code: "external-uninstall", summary: ownership?.guidance ?? L10n.text("请通过安装来源卸载"))] : [])
                + (limitations.isEmpty && !reachedSizeBudget ? [] : [
                Evidence(code: "size-estimate", summary: L10n.text("部分应用文件无法统计，显示大小为已读取部分；应用本体仍可手动卸载")),
            ]),
            identity: bundleIdentity,
            source: .application,
            lastAccessDate: Date(timeIntervalSince1970: Double(bundleIdentity.modificationTime)),
            isActive: application.isRunning
        )), containsUserData: false, isShared: false))

        for association in associations {
            try Task.checkCancellation()
            let identity: FileIdentity
            do {
                identity = try await context.fileSystem.identity(at: association.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                limitations.append(measurementLimitation(at: association.url, error: error))
                continue
            }
            let isProtected = association.isShared || association.risk == .blocked || identity.kind == .symbolicLink
                || association.removalPolicy == .referenceOnly
                || ownership?.blocksAssociationDeletion == true
            let previousLimitationCount = limitations.count
            let bytes: UInt64
            if isProtected {
                // Blocked entries cannot be deleted by this plan; do not inspect them.
                bytes = 0
            } else {
                bytes = try await measuredBytes(
                    at: association.url,
                    identity: identity,
                    remainingBudget: &remainingSizeEntries,
                    reachedBudget: &reachedSizeBudget,
                    limitations: &limitations,
                    context: context
                )
            }
            let incomplete = limitations.count > previousLimitationCount || reachedSizeBudget
            let category: CleanupCategory = association.kind == .cache ? .cache : association.kind == .diagnosticReport ? .log : .applicationSupport
            let protectionReason: String = association.isShared ? L10n.text("这是多个应用共用的内容")
                : association.isSystemResource == true ? L10n.text("这是系统目录内容")
                : association.references?.isEmpty == false ? L10n.text("仍有配置或服务引用此项目")
                : association.removalPolicy == .referenceOnly && association.kind != .launchAgent && association.kind != .launchDaemon ? L10n.text("此项目用于关联核对；安装记录或已注册组件需通过原安装来源移除")
                : association.kind == .launchAgent || association.kind == .launchDaemon ? L10n.text("这是应用启动服务定义；需先停止并注销服务，再移除此文件。仅删除 plist 不会停止已加载的服务。")
                : ownership?.blocksAssociationDeletion == true ? (ownership?.guidance ?? L10n.text("应用归属或安装来源尚未验证"))
                : identity.kind == .symbolicLink ? L10n.text("这是符号链接，目标路径未纳入卸载计划")
                : L10n.text("归属证据不足或扫描未完整，暂时不能安全删除")
            let candidate = context.protectionPolicy.applying(to: CleanupCandidate(
                url: association.url,
                displayName: association.url.lastPathComponent,
                category: category,
                bytes: bytes,
                risk: isProtected ? .blocked : incomplete ? .review : association.risk,
                evidence: [
                    Evidence(code: "ownership", summary: association.localizedOwnershipEvidence),
                    Evidence(code: "owner-bundle", summary: application.bundleURL.path),
                    Evidence(code: "owner-bundle-id", summary: application.bundleIdentifier),
                    Evidence(code: "owner-name", summary: application.name),
                    Evidence(code: association.containsUserData ? "user-data" : "recoverable", summary: association.containsUserData ? L10n.text("可能包含用户创建的数据；仅在归属独占时可选删除") : L10n.text("可恢复的应用关联文件")),
                ] + (association.removalPolicy == .referenceOnly ? [Evidence(code: "association-reference-only", summary: L10n.text("此项目用于关联核对；安装记录或已注册组件需通过原安装来源移除"))] : [])
                + (association.kind == .diagnosticReport ? [Evidence(code: "diagnostic-file", summary: association.localizedOwnershipEvidence)] : [])
                + (association.declarationSource.map { [Evidence(code: "data-declaration-source", summary: $0)] } ?? [])
                + (association.kind == .sharedContainer ? [Evidence(code: "app-group-data", summary: L10n.text("应用声明的应用组目录；当前清单未发现其他所有者，需单独确认删除。"))] : [])
                + (association.kind == .launchAgent || association.kind == .launchDaemon ? [Evidence(code: "service-definition", summary: L10n.text("需先停止并注销此启动服务，再移除此文件。仅删除 plist 不会停止已加载的服务。 "))] : [])
                + (association.references ?? []).map { reference in
                    Evidence(code: "reference-location", summary: "\(reference.file.path):\(reference.line)")
                } + (ownership?.blocksAssociationDeletion == true ? [Evidence(code: "external-uninstall", summary: ownership?.guidance ?? L10n.text("请通过原安装来源卸载"))] : [])
                + (isProtected ? [
                    Evidence(code: "protection-reason", summary: protectionReason),
                    Evidence(code: "size-not-measured", summary: L10n.text("因安全规则无法访问内容，未统计大小")),
                ] : incomplete ? [
                    Evidence(code: "size-estimate", summary: L10n.text("部分内容无法访问，大小为已统计部分；你仍可单独选择此项，删除后可从恢复记录找回。")),
                ] : []),
                identity: identity,
                source: .application,
                lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                isActive: false
            ))
            let containsUserData = association.containsUserData
                || association.kind == .launchAgent || association.kind == .launchDaemon
            items.append(UninstallItem(candidate: candidate, containsUserData: containsUserData, isShared: association.isShared))
        }
        return UninstallPlanBuildResult(
            plan: UninstallPlan(application: application, items: items),
            reachedSizeBudget: reachedSizeBudget,
            limitations: limitations
        )
    }

    private func measuredBytes(
        at url: URL,
        identity: FileIdentity,
        remainingBudget: inout Int?,
        reachedBudget: inout Bool,
        limitations: inout [ScanLimitation],
        context: ScanContext
    ) async throws -> UInt64 {
        return try await iterativeSize(
            of: url,
            identity: identity,
            remainingBudget: &remainingBudget,
            reachedBudget: &reachedBudget,
            limitations: &limitations,
            context: context
        )
    }

    private func iterativeSize(
        of url: URL,
        identity: FileIdentity,
        remainingBudget: inout Int?,
        reachedBudget: inout Bool,
        limitations: inout [ScanLimitation],
        context: ScanContext
    ) async throws -> UInt64 {
        var pending: [(url: URL, identity: FileIdentity)] = [(url.standardizedFileURL, identity)]
        var seenPaths = Set<String>()
        var total: UInt64 = 0
        while let current = pending.popLast() {
            try Task.checkCancellation()
            guard seenPaths.insert(current.url.path).inserted else { continue }

            if let entriesLeft = remainingBudget {
                guard entriesLeft > 0 else {
                    reachedBudget = true
                    break
                }
                remainingBudget = entriesLeft - 1
            }

            guard current.identity.kind == .directory else {
                total = total.addingWithoutOverflow(current.identity.size)
                continue
            }

            let children: [URL]
            do {
                children = try await context.fileSystem.children(of: current.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                limitations.append(measurementLimitation(at: current.url, error: error))
                continue
            }
            for child in children.reversed() {
                try Task.checkCancellation()
                let standardizedChild = child.standardizedFileURL
                guard !seenPaths.contains(standardizedChild.path) else { continue }
                do {
                    let childIdentity = try await context.fileSystem.identity(at: standardizedChild)
                    pending.append((standardizedChild, childIdentity))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    limitations.append(measurementLimitation(at: standardizedChild, error: error))
                }
            }
        }
        if reachedBudget {
            // The partial total is intentionally retained so diagnostic callers can
            // inspect progress while the coverage state clearly reports truncation.
            return total
        }
        return total
    }

    private func measurementLimitation(at url: URL, error: Error) -> ScanLimitation {
        ScanLimitation(
            title: ApplicationAnalysisErrorDescription.describe(error),
            path: url,
            impact: L10n.text("该位置未完整统计；受影响的关联项不会加入卸载计划，应用本体仍可单独卸载。"),
            recovery: L10n.text("可检查该位置权限后刷新应用；无需修改受保护文件的权限。")
        )
    }
}

private extension UInt64 {
    func addingWithoutOverflow(_ other: UInt64) -> UInt64 {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}

public struct UninstallPlanBuildResult: Sendable {
    public let plan: UninstallPlan
    public let reachedSizeBudget: Bool
    public let limitations: [ScanLimitation]

    public init(plan: UninstallPlan, reachedSizeBudget: Bool, limitations: [ScanLimitation] = []) {
        self.plan = plan
        self.reachedSizeBudget = reachedSizeBudget
        self.limitations = limitations
    }
}
