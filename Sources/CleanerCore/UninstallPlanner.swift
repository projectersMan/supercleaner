import Foundation

public struct UninstallPlanner: Sendable {
    private let scanner: ApplicationScanner
    public init(scanner: ApplicationScanner = ApplicationScanner()) { self.scanner = scanner }

    public func planUninstall(_ application: InstalledApplication, context: ScanContext) async throws -> UninstallPlan {
        var inventory = await scanner.installedApplications(context: context, runningBundleIdentifiers: context.runningBundleIdentifiers, maximumEntries: 30_000)
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
                + (ownership?.installation.source == .packageInstaller ? (ownership?.installation.receipts ?? [])
                    .filter { $0.pathExtension == "plist" && ["/var/db/receipts", "/private/var/db/receipts"].contains($0.deletingLastPathComponent().path) }
                    .map { Evidence(code: "package-receipt-id", summary: $0.deletingPathExtension().lastPathComponent) } : [])
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
            // Installation metadata is handled by pkgutil after a successful uninstall.
            if association.kind == .installationReceipt { continue }
            let identity: FileIdentity
            do {
                identity = try await context.fileSystem.identity(at: association.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                limitations.append(measurementLimitation(at: association.url, error: error))
                continue
            }
            let isInputMethodCache = association.kind == .cache
                && InputMethodProtection.contains(application.bundleURL, home: context.homeDirectory)
            let isProtected = isInputMethodCache || association.isShared || association.risk == .blocked || identity.kind == .symbolicLink
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
            let protectionReason: String = isInputMethodCache ? L10n.text("输入法运行缓存受保护；卸载应用时保留，避免影响系统输入服务。")
                : association.isShared ? L10n.text("这是多个应用共用的内容")
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
