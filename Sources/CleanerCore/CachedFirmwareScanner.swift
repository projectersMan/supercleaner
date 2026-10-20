import Foundation

public struct CachedFirmwareScanner: Scanner {
    public let id = "general.cached-device-firmware"
    public let category = CleanupCategory.installerArtifact

    public init() {}

    public func scan(context: ScanContext) async throws -> [CleanupCandidate] {
        let shallowRoots = [
            "Library/iTunes/iPhone Software Updates",
            "Library/iTunes/iPad Software Updates",
            "Library/iTunes/iPod Software Updates",
        ].map { context.homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
        let configuratorFirmwareRoot = context.homeDirectory.appendingPathComponent(
            "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware",
            isDirectory: true
        ).standardizedFileURL

        var candidates: [CleanupCandidate] = []
        var seenCandidatePaths = Set<String>()

        for root in shallowRoots {
            try Task.checkCancellation()
            guard await context.fileSystem.fileExists(root) else { continue }
            for child in try await context.fileSystem.children(of: root) {
                try Task.checkCancellation()
                let url = child.standardizedFileURL
                guard url.pathExtension.lowercased() == "ipsw",
                      seenCandidatePaths.insert(url.path).inserted else { continue }
                let identity = try await context.fileSystem.identity(at: url)
                guard identity.kind != .directory else { continue }
                candidates.append(await candidate(for: url, identity: identity, context: context))
            }
        }

        if await context.fileSystem.fileExists(configuratorFirmwareRoot) {
            var pendingDirectories = [configuratorFirmwareRoot]
            var visitedDirectories = Set([configuratorFirmwareRoot.path])
            while let directory = pendingDirectories.popLast() {
                try Task.checkCancellation()
                for child in try await context.fileSystem.children(of: directory) {
                    try Task.checkCancellation()
                    let url = child.standardizedFileURL
                    let identity = try await context.fileSystem.identity(at: url)
                    if identity.kind == .directory {
                        if visitedDirectories.insert(url.path).inserted {
                            pendingDirectories.append(url)
                        }
                        continue
                    }
                    guard url.pathExtension.lowercased() == "ipsw",
                          seenCandidatePaths.insert(url.path).inserted else { continue }
                    candidates.append(await candidate(for: url, identity: identity, context: context))
                }
            }
        }

        return candidates
    }

    private func candidate(
        for url: URL,
        identity: FileIdentity,
        context: ScanContext
    ) async -> CleanupCandidate {
        let readable = await context.fileSystem.isReadable(url)
        let active = context.isActive(url)
        var evidence = [Evidence(
            code: "cached-device-firmware",
            summary: "已发现缓存的 Apple 设备固件",
            details: "仅识别明确固件缓存目录中的 .ipsw 文件；不会自动加入清理计划。"
        )]

        var risk: RiskLevel = .review
        if active {
            risk = .blocked
            evidence.append(Evidence(code: "active", summary: "当前有任务或进程正在使用"))
        }
        if identity.kind == .symbolicLink {
            risk = .blocked
            evidence.append(Evidence(code: "symbolic-link", summary: "符号链接不会进入清理计划"))
        } else if identity.kind != .file {
            risk = .blocked
            evidence.append(Evidence(code: "unknown-file-kind", summary: "无法确认这是普通文件"))
        }
        if !readable {
            risk = .blocked
            evidence.append(Evidence(code: "unreadable", summary: "当前权限不足，无法验证文件"))
        }
        do {
            _ = try context.pathPolicy.validateCandidate(url)
        } catch {
            risk = .blocked
            evidence.append(Evidence(code: "protected-path", summary: "路径受到安全策略保护"))
        }

        return CleanupCandidate(
            url: url,
            displayName: url.lastPathComponent,
            category: category,
            bytes: identity.size,
            risk: risk,
            evidence: evidence,
            identity: identity,
            source: .general,
            lastAccessDate: Date(timeIntervalSince1970: Double(identity.modificationTime)),
            isActive: active
        )
    }
}
