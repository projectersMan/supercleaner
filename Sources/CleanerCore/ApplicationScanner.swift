import Foundation
import Security

private enum ApplicationOwnershipMatch: Equatable {
    case bundleIdentifierBoundary
    case displayName
}

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

    public init(bundleURL: URL, bundleIdentifier: String, name: String, version: String?, isRunning: Bool, isSystem: Bool, teamIdentifier: String? = nil, applicationGroups: [String]? = nil) {
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

    public init(bundleIdentifier: String, name: String, version: String?, teamIdentifier: String? = nil, applicationGroups: [String]? = nil) {
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
        return ApplicationBundleMetadata(bundleIdentifier: identifier, name: name, version: version, teamIdentifier: team, applicationGroups: groups)
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
    }

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

    public init(url: URL, kind: Kind, ownershipEvidence: String, containsUserData: Bool, isShared: Bool, risk: RiskLevel, ownerBundleURLs: [URL]? = nil, references: [ApplicationReferenceLocation]? = nil, isSystemResource: Bool = false) {
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

    public init(metadataProvider: any ApplicationMetadataProviding = BundleApplicationMetadataProvider(), ownershipBuilder: ApplicationOwnershipGraphBuilder = ApplicationOwnershipGraphBuilder(), applicationRoots: [URL]? = nil) {
        self.metadataProvider = metadataProvider
        self.ownershipBuilder = ownershipBuilder
        self.applicationRoots = applicationRoots
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
            for volume in mounted.prefix(64) where !volume.lastPathComponent.hasPrefix(".") {
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
        var remainingEntries = maximumEntries.map { max(0, $0) }
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
                            applicationGroups: metadata.applicationGroups
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
        context: ScanContext
    ) async -> ApplicationAssociationIndex {
        struct RootSpec: Sendable {
            let relativePath: String
            let kind: ApplicationAssociation.Kind
            let containsUserData: Bool
            let isShared: Bool
        }
        let specs = [
            RootSpec(relativePath: "Library/Caches", kind: .cache, containsUserData: false, isShared: false),
            RootSpec(relativePath: "Library/Application Support", kind: .applicationSupport, containsUserData: true, isShared: false),
            RootSpec(relativePath: "Library/Preferences", kind: .preference, containsUserData: false, isShared: false),
            RootSpec(relativePath: "Library/Saved Application State", kind: .savedState, containsUserData: false, isShared: false),
            RootSpec(relativePath: "Library/Containers", kind: .container, containsUserData: true, isShared: false),
        ]

        var output = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, [ApplicationAssociation]()) })
        var scannedRoots: [URL] = []
        var unavailableRoots: [URL] = []
        var remaining = 20_000
        var limited = false
        let deadline = Date().addingTimeInterval(20)
        for spec in specs {
            if Task.isCancelled { limited = true; break }
            let root = context.homeDirectory.appendingPathComponent(spec.relativePath, isDirectory: true)
            guard await context.fileSystem.fileExists(root) else { continue }
            guard await context.fileSystem.isReadable(root) else {
                unavailableRoots.append(root)
                continue
            }
            let children: [URL]
            do {
                children = try await context.fileSystem.children(of: root)
                scannedRoots.append(root)
            } catch {
                unavailableRoots.append(root)
                continue
            }
            for url in children {
                guard remaining > 0, Date() < deadline, !Task.isCancelled else { limited = true; break }
                remaining -= 1
                for application in applications {
                    guard let ownershipMatch = ownershipMatch(
                        url: url,
                        application: application,
                        shared: spec.isShared
                    ) else { continue }
                    let risk: RiskLevel
                    if application.isRunning || spec.isShared {
                        risk = .blocked
                    } else if spec.kind == .cache, ownershipMatch == .bundleIdentifierBoundary {
                        risk = .safe
                    } else {
                        risk = .review
                    }
                    output[application.id, default: []].append(ApplicationAssociation(
                        url: url,
                        kind: spec.kind,
                        ownershipEvidence: ownershipEvidence(for: ownershipMatch),
                        containsUserData: spec.containsUserData,
                        isShared: spec.isShared,
                        risk: risk
                    ))
                }
            }
        }
        return await ownershipBuilder.build(
            applications: applications, associations: output,
            coverage: CoverageSummary(scannedRoots: scannedRoots, unavailableRoots: unavailableRoots, budgetLimitedModules: limited ? [.applications] : []), context: context
        )
    }

    private func ownershipMatch(
        url: URL,
        application: InstalledApplication,
        shared: Bool
    ) -> ApplicationOwnershipMatch? {
        var stem = url.lastPathComponent.lowercased()
        for suffix in [".savedstate", ".plist"] where stem.hasSuffix(suffix) {
            stem.removeLast(suffix.count)
        }
        let bundleID = application.bundleIdentifier.lowercased()
        let appName = application.name.lowercased()
        if stem == bundleID || stem.hasPrefix(bundleID + ".") {
            return .bundleIdentifierBoundary
        }
        if shared {
            let groupID = "group." + bundleID
            if stem == groupID || stem.hasPrefix(groupID + ".") {
                return .bundleIdentifierBoundary
            }
        }
        return stem == appName ? .displayName : nil
    }

    private func ownershipEvidence(for match: ApplicationOwnershipMatch) -> String {
        switch match {
        case .bundleIdentifierBoundary:
            return "名称与完整 Bundle ID 边界匹配"
        case .displayName:
            return "名称仅与应用显示名精确匹配"
        }
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
        var remainingSizeEntries = maximumSizeEntries.map { max(0, $0) }
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
            ? Evidence(code: "running-app", summary: "应用仍在运行，必须先退出")
            : Evidence(code: "app-bundle", summary: ownership?.requiresExternalUninstall == true
                ? "仅移除应用本体；安装来源记录和关联内容可能保留，可从恢复记录找回应用本体"
                : "应用本体将删除，可从恢复记录找回")
        items.append(UninstallItem(candidate: context.protectionPolicy.applying(to: CleanupCandidate(
            url: application.bundleURL,
            displayName: application.name,
            category: .application,
            bytes: bundleBytes,
            risk: bundleRisk,
            evidence: [bundleEvidence, Evidence(code: "owner-bundle", summary: application.bundleURL.path),
                       Evidence(code: "owner-bundle-id", summary: application.bundleIdentifier), Evidence(code: "owner-name", summary: application.name)]
                + (ownership?.requiresExternalUninstall == true ? [Evidence(code: "external-uninstall", summary: ownership?.guidance ?? "请通过安装来源卸载")] : [])
                + (limitations.isEmpty && !reachedSizeBudget ? [] : [
                Evidence(code: "size-estimate", summary: "部分应用文件无法统计，显示大小为已读取部分；应用本体仍可手动卸载"),
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
            let category: CleanupCategory = association.kind == .cache ? .cache : .applicationSupport
            let protectionReason: String = association.isShared ? "这是多个应用共用的内容"
                : association.isSystemResource == true ? "这是系统目录内容"
                : association.references?.isEmpty == false ? "仍有配置或服务引用此项目"
                : association.kind == .launchAgent || association.kind == .launchDaemon ? "这是应用启动服务定义；需先停止并注销服务，再移除此文件。仅删除 plist 不会停止已加载的服务。"
                : ownership?.blocksAssociationDeletion == true ? (ownership?.guidance ?? "应用归属或安装来源尚未验证")
                : identity.kind == .symbolicLink ? "这是符号链接，目标路径未纳入卸载计划"
                : "归属证据不足或扫描未完整，暂时不能安全删除"
            let candidate = context.protectionPolicy.applying(to: CleanupCandidate(
                url: association.url,
                displayName: association.url.lastPathComponent,
                category: category,
                bytes: bytes,
                risk: isProtected ? .blocked : incomplete ? .review : association.risk,
                evidence: [
                    Evidence(code: "ownership", summary: association.ownershipEvidence),
                    Evidence(code: "owner-bundle", summary: application.bundleURL.path),
                    Evidence(code: "owner-bundle-id", summary: application.bundleIdentifier),
                    Evidence(code: "owner-name", summary: application.name),
                    Evidence(code: association.containsUserData ? "user-data" : "recoverable", summary: association.containsUserData ? "可能包含用户创建的数据；仅在归属独占时可选删除" : "可恢复的应用关联文件"),
                ] + (association.kind == .sharedContainer ? [Evidence(code: "app-group-data", summary: "应用声明的应用组目录；当前清单未发现其他所有者，需单独确认删除。")] : [])
                + (association.kind == .launchAgent || association.kind == .launchDaemon ? [Evidence(code: "service-definition", summary: "需先停止并注销此启动服务，再移除此文件。仅删除 plist 不会停止已加载的服务。 ")] : [])
                + (association.references ?? []).map { reference in
                    Evidence(code: "reference-location", summary: "\(reference.file.path):\(reference.line)")
                } + (ownership?.blocksAssociationDeletion == true ? [Evidence(code: "external-uninstall", summary: ownership?.guidance ?? "请通过原安装来源卸载")] : [])
                + (isProtected ? [
                    Evidence(code: "protection-reason", summary: protectionReason),
                    Evidence(code: "size-not-measured", summary: "因安全规则无法访问内容，未统计大小"),
                ] : incomplete ? [
                    Evidence(code: "size-estimate", summary: "部分内容无法访问，大小为已统计部分；你仍可单独选择此项，删除后可从恢复记录找回。"),
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
            impact: "该位置未完整统计；受影响的关联项不会加入卸载计划，应用本体仍可单独卸载。",
            recovery: "可检查该位置权限后刷新应用；无需修改受保护文件的权限。"
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
