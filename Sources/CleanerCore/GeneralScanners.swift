import Foundation

private enum GeneralScanSupport {
    static let safeAge: TimeInterval = 30 * 86_400

    struct ContentInspection: Sendable {
        var bytes: UInt64
        var newestModificationTime: Int64
        var isFullyReadable: Bool
        var containsUnsupportedEntry: Bool
    }

    static func candidates(
        roots: [URL],
        category: CleanupCategory,
        source: CandidateSource,
        context: ScanContext,
        defaultSelection: Bool? = nil,
        include: @Sendable (URL, FileIdentity) -> Bool = { _, _ in true },
        evidence additionalEvidence: @Sendable (URL, FileIdentity) -> [Evidence] = { _, _ in [] },
        risk: @Sendable (URL, FileIdentity, ContentInspection, ScanContext) -> RiskLevel
    ) async throws -> [CleanupCandidate] {
        var output: [CleanupCandidate] = []
        for root in roots {
            try Task.checkCancellation()
            guard await context.fileSystem.fileExists(root) else { continue }
            for url in try await context.fileSystem.children(of: root) {
                try Task.checkCancellation()
                let identity = try await context.fileSystem.identity(at: url)
                guard include(url, identity) else { continue }
                let readable = await context.fileSystem.isReadable(url)
                let inspection = readable && identity.kind == .directory
                    ? try await inspectContent(of: url, identity: identity, context: context)
                    : ContentInspection(
                        bytes: identity.size,
                        newestModificationTime: identity.modificationTime,
                        isFullyReadable: readable,
                        containsUnsupportedEntry: identity.kind == .symbolicLink || identity.kind == .other
                    )
                let active = context.isActive(url)
                let candidateRisk: RiskLevel
                var evidence = additionalEvidence(url, identity)

                do {
                    _ = try context.pathPolicy.validateCandidate(url)
                    candidateRisk = readable ? risk(url, identity, inspection, context) : .blocked
                } catch {
                    candidateRisk = .blocked
                    evidence.append(Evidence(code: "protected-path", summary: L10n.text("路径受到安全策略保护")))
                }

                if active {
                    evidence.append(Evidence(code: "active", summary: L10n.text("当前有任务或进程正在使用")))
                }
                if !readable {
                    evidence.append(Evidence(code: "unreadable", summary: L10n.text("当前权限不足，无法验证内容")))
                }
                if identity.kind == .directory && !inspection.isFullyReadable {
                    evidence.append(Evidence(code: "incomplete-directory-inspection", summary: L10n.text("目录内存在无法验证的内容")))
                }
                if identity.kind == .directory && inspection.containsUnsupportedEntry {
                    evidence.append(Evidence(code: "unsupported-directory-entry", summary: L10n.text("目录内包含链接或未知类型，未自动推荐")))
                }
                let age = max(0, context.now.timeIntervalSince1970 - Double(inspection.newestModificationTime))
                evidence.append(Evidence(code: "last-modified", summary: ageSummary(age)))

                output.append(CleanupCandidate(
                    url: url,
                    displayName: url.lastPathComponent,
                    category: category,
                    bytes: inspection.bytes,
                    risk: candidateRisk,
                    evidence: evidence,
                    identity: identity,
                    source: source,
                    lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
                    isActive: active,
                    defaultSelection: defaultSelection
                ))
            }
        }
        return output
    }

    private static func inspectContent(
        of directory: URL,
        identity: FileIdentity,
        context: ScanContext
    ) async throws -> ContentInspection {
        var pendingDirectories = [directory]
        var visitedPaths = Set([directory.standardizedFileURL.path])
        var inspection = ContentInspection(
            bytes: 0,
            newestModificationTime: identity.modificationTime,
            isFullyReadable: true,
            containsUnsupportedEntry: false
        )

        while let currentDirectory = pendingDirectories.popLast() {
            try Task.checkCancellation()
            let children: [URL]
            do {
                children = try await context.fileSystem.children(of: currentDirectory)
            } catch {
                inspection.isFullyReadable = false
                continue
            }
            for child in children {
                try Task.checkCancellation()
                let standardizedPath = child.standardizedFileURL.path
                guard visitedPaths.insert(standardizedPath).inserted else { continue }

                guard let childIdentity = try? await context.fileSystem.identity(at: child) else {
                    inspection.isFullyReadable = false
                    continue
                }
                inspection.newestModificationTime = max(inspection.newestModificationTime, childIdentity.modificationTime)
                let childReadable = await context.fileSystem.isReadable(child)
                if !childReadable { inspection.isFullyReadable = false }

                switch childIdentity.kind {
                case .directory:
                    if childReadable { pendingDirectories.append(child) }
                case .symbolicLink:
                    inspection.containsUnsupportedEntry = true
                case .other:
                    inspection.containsUnsupportedEntry = true
                    add(childIdentity.size, to: &inspection.bytes)
                case .file:
                    add(childIdentity.size, to: &inspection.bytes)
                }
            }
        }
        return inspection
    }

    private static func add(_ bytes: UInt64, to total: inout UInt64) {
        let (sum, overflowed) = total.addingReportingOverflow(bytes)
        total = overflowed ? .max : sum
    }

    static func ageBasedRisk(
        _ url: URL,
        identity: FileIdentity,
        inspection: ContentInspection,
        context: ScanContext,
        allowSafeDirectory: Bool = false
    ) -> RiskLevel {
        if context.isActive(url) || identity.kind == .symbolicLink || identity.kind == .other { return .blocked }
        if identity.kind == .directory {
            guard allowSafeDirectory,
                  inspection.isFullyReadable,
                  !inspection.containsUnsupportedEntry else { return .review }
        }
        let age = context.now.timeIntervalSince1970 - Double(inspection.newestModificationTime)
        return age >= safeAge ? .safe : .review
    }

    static func ageSummary(_ seconds: TimeInterval) -> String {
        let days = max(0, Int(seconds / 86_400))
        return days == 0 ? L10n.text("今天修改") : L10n.text("{0} 天前修改", String(describing: days))
    }
}

public struct UserCacheScanner: Scanner {
    public let id = "general.user-caches"
    public let category = CleanupCategory.cache
    public init() {}

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        try await GeneralScanSupport.candidates(
            roots: [context.homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)],
            category: category,
            source: .general,
            context: context,
            risk: { url, identity, inspection, context in
                GeneralScanSupport.ageBasedRisk(
                    url,
                    identity: identity,
                    inspection: inspection,
                    context: context,
                    allowSafeDirectory: true
                )
            }
        )
    }
}

public struct LogScanner: Scanner {
    public let id = "general.logs"
    public let category = CleanupCategory.log
    public init() {}

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let roots = [
            "Library/Logs",
            "Library/DiagnosticReports",
            "Library/Application Support/CrashReporter",
        ].map { context.homeDirectory.appendingPathComponent($0, isDirectory: true) }
        let diagnosticRootPaths = Set(roots.dropFirst().map { $0.standardizedFileURL.path })
        let candidates = try await GeneralScanSupport.candidates(
            roots: roots,
            category: category,
            source: .general,
            context: context,
            evidence: { url, _ in
                let path = url.standardizedFileURL.path
                guard diagnosticRootPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
                    return []
                }
                return [Evidence(
                    code: "diagnostic-report",
                    summary: L10n.text("macOS 或应用生成的诊断记录"),
                    details: L10n.text("来自用户诊断目录；仍按最近修改时间和活动状态判断，执行前可逐项检查。")
                )]
            },
            risk: { url, identity, inspection, context in
                GeneralScanSupport.ageBasedRisk(url, identity: identity, inspection: inspection, context: context)
            }
        )

        var seenPaths: Set<String> = []
        return candidates.filter { candidate in
            seenPaths.insert(candidate.url.standardizedFileURL.path).inserted
        }
    }
}

public struct InstallerScanner: Scanner {
    public let id = "general.installers"
    public let category = CleanupCategory.installerArtifact
    public let maximumDepth: Int
    public let maximumEntries: Int
    public let timeLimit: TimeInterval
    public let additionalRoots: [URL]
    public init(maximumDepth: Int = 6, maximumEntries: Int = 25_000, timeLimit: TimeInterval = 20, additionalRoots: [URL] = []) {
        self.maximumDepth = max(1, maximumDepth)
        self.maximumEntries = max(1, maximumEntries)
        self.timeLimit = max(0.01, timeLimit)
        self.additionalRoots = additionalRoots
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        try await InstallerDiscovery(
            maximumDepth: maximumDepth, maximumEntries: maximumEntries,
            timeLimit: timeLimit, additionalRoots: additionalRoots
        ).scan(context: context)
    }
}

public struct IncompleteDownloadScanner: Scanner {
    public let id = "general.incomplete-downloads"
    public let category = CleanupCategory.temporaryFile
    private let extensions: Set<String> = ["download", "crdownload", "part"]
    public init() {}

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let candidates = try await GeneralScanSupport.candidates(
            roots: [context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)],
            category: category,
            source: .general,
            context: context,
            defaultSelection: false,
            include: { url, identity in
                identity.kind == .file && extensions.contains(url.pathExtension.lowercased())
            },
            evidence: { url, _ in [
                Evidence(
                    code: "incomplete-download",
                    summary: L10n.text("下载工具留下的未完成文件"),
                    details: L10n.text("通过 .{0} 扩展名识别；确认不再续传后可清理。", String(describing: url.pathExtension.lowercased()))
                ),
            ] },
            risk: { url, identity, _, context in
                context.isActive(url) || identity.kind == .symbolicLink ? .blocked : .review
            }
        )

        var seenPaths: Set<String> = []
        return candidates.filter { candidate in
            seenPaths.insert(candidate.url.standardizedFileURL.path).inserted
        }
    }
}

public struct DeveloperArtifactScanner: Scanner {
    public let id = "general.developer-artifacts"
    public let category = CleanupCategory.developerCache
    public init() {}

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let rebuildableRootPaths = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Caches/Homebrew",
            ".cache/uv",
            "Library/Caches/pip",
            ".gradle/caches",
            ".gradle/daemon",
            ".gradle/notifications",
            ".gradle/workers",
            ".npm/_cacache",
            ".npm/_npx",
            ".npm/_logs",
            ".npm/_prebuilds",
            ".yarn/cache",
            "Library/Caches/Yarn",
            ".bun/install/cache",
            ".cache/typescript",
            ".cache/electron",
            ".cache/node-gyp",
            ".node-gyp",
            ".turbo/cache",
            ".vite/cache",
            ".cache/vite",
            ".cache/webpack",
            ".parcel-cache",
            ".cache/eslint",
            ".cache/prettier",
            ".cache/swift-package-manager",
            "Library/Caches/org.swift.swiftpm",
            ".cache/bazel",
            ".cache/zig",
            ".cache/pre-commit",
            ".bundle/cache",
        ]
        let reviewOnlyRootPaths = [
            "Library/Developer/Xcode/Archives",
            "Library/Developer/CoreSimulator/Caches",
            "Library/Developer/XCTestDevices",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/Xcode/macOS DeviceSupport",
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/Xcode/tvOS DeviceSupport",
        ]
        let protectedSystemReviewRoots = [
            URL(fileURLWithPath: "/Library/Developer/Xcode/DocumentationCache", isDirectory: true).standardizedFileURL,
        ]
        let roots = ((rebuildableRootPaths + reviewOnlyRootPaths)
            .map { context.homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
            + protectedSystemReviewRoots)
            .reduce(into: [URL]()) { result, url in
                guard !result.contains(where: { $0.path == url.path }) else { return }
                result.append(url)
            }
        let reviewOnlyRoots = Set(
            reviewOnlyRootPaths.map {
                context.homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path
            }
            + protectedSystemReviewRoots.map(\.path)
        )
        let candidates = try await GeneralScanSupport.candidates(
            roots: roots,
            category: category,
            source: .general,
            context: context,
            evidence: { url, _ in
                let isReviewOnly = reviewOnlyRoots.contains { root in
                    url.standardizedFileURL.path.hasPrefix(root + "/")
                }
                return [Evidence(
                    code: isReviewOnly ? "developer-state-review" : "developer-cache",
                    summary: isReviewOnly
                        ? L10n.text("开发环境内容需逐项确认")
                        : L10n.text("开发工具生成的可重建缓存")
                )]
            },
            risk: { url, identity, inspection, context in
                if context.isActive(url) || identity.kind == .symbolicLink || identity.kind == .other {
                    return .blocked
                }
                if reviewOnlyRoots.contains(where: { url.standardizedFileURL.path.hasPrefix($0 + "/") }) {
                    return .review
                }
                return GeneralScanSupport.ageBasedRisk(
                    url,
                    identity: identity,
                    inspection: inspection,
                    context: context,
                    allowSafeDirectory: true
                )
            }
        )

        var seenPaths: Set<String> = []
        return candidates.filter { candidate in
            seenPaths.insert(candidate.url.standardizedFileURL.path).inserted
        }
    }
}

public struct LargeFileScanner: Scanner {
    public let id = "general.large-files"
    public let category = CleanupCategory.largeFile
    public let minimumBytes: UInt64
    public let maximumDepth: Int?
    public let maximumEntries: Int?

    public init(
        minimumBytes: UInt64 = 100_000_000,
        maximumDepth: Int? = nil,
        maximumEntries: Int? = nil
    ) {
        self.minimumBytes = minimumBytes
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
    }

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let tree = try await DiskUsageScanner(
            minimumFileBytes: minimumBytes,
            maximumDepth: maximumDepth,
            maximumEntries: maximumEntries
        ).scan(context: context)
        return try await candidates(from: tree, context: context)
    }

    public func candidates(from tree: DiskUsageTree, context: ScanContext) async throws -> [CleanupCandidate] {
        var output: [CleanupCandidate] = []
        for node in tree.largeFiles where node.ownBytes >= minimumBytes {
            try Task.checkCancellation()
            let identity: FileIdentity
            if let capturedIdentity = node.identity {
                identity = capturedIdentity
            } else if let currentIdentity = try? await context.fileSystem.identity(at: node.url) {
                identity = currentIdentity
            } else {
                continue
            }
            guard identity.kind == .file else { continue }
            let active = context.isActive(node.url)
            var risk: RiskLevel = active || !node.isReadable ? .blocked : .review
            var evidence = [Evidence(
                code: "large-file",
                summary: L10n.text("大文件仅因体积被发现，不会自动清理")
            )]
            do { _ = try context.pathPolicy.validateCandidate(node.url) }
            catch { risk = .blocked; evidence.append(Evidence(code: "protected-path", summary: L10n.text("路径受到安全策略保护"))) }
            output.append(context.protectionPolicy.applying(to: CleanupCandidate(
                url: node.url, displayName: node.url.lastPathComponent, category: category, bytes: node.ownBytes,
                risk: risk, evidence: evidence, identity: identity, source: .diskAnalysis,
                lastAccessDate: node.modifiedAt, isActive: active
            )))
        }
        return output.sorted { $0.bytes > $1.bytes }
    }
}
