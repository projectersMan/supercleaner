import Foundation
import Darwin

public enum PermissionLevel: String, Codable, Hashable, Sendable {
    case full
    case limited
}

public enum PermissionCapabilityStatus: String, Codable, Hashable, Sendable {
    case granted
    case actionRequired
    case unverified
}

public struct PermissionCapabilitySnapshot: Codable, Hashable, Sendable {
    public let status: PermissionCapabilityStatus
    public let settingsURL: URL
    public let explanation: String

    public init(status: PermissionCapabilityStatus, settingsURL: URL, explanation: String) {
        self.status = status
        self.settingsURL = settingsURL
        self.explanation = explanation
    }
}

public struct PermissionSnapshot: Codable, Hashable, Sendable {
    public let level: PermissionLevel
    public let availableCategories: Set<CleanupCategory>
    public let affectedCategories: Set<CleanupCategory>
    public let settingsURL: URL
    public let explanation: String
    public let fullDiskAccess: PermissionCapabilitySnapshot
    public let appManagement: PermissionCapabilitySnapshot

    public init(
        level: PermissionLevel,
        availableCategories: Set<CleanupCategory>,
        affectedCategories: Set<CleanupCategory>,
        settingsURL: URL,
        explanation: String,
        fullDiskAccess: PermissionCapabilitySnapshot,
        appManagement: PermissionCapabilitySnapshot
    ) {
        self.level = level
        self.availableCategories = availableCategories
        self.affectedCategories = affectedCategories
        self.settingsURL = settingsURL
        self.explanation = explanation
        self.fullDiskAccess = fullDiskAccess
        self.appManagement = appManagement
    }
}

public struct PermissionStatusService: Sendable {
    public static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    public static let appManagementSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
    private let fileSystem: any FileSystemAccess
    private let homeDirectory: URL
    private let appManagementObservation: PermissionCapabilityStatus

    public init(
        fileSystem: any FileSystemAccess = LocalFileSystem(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        appManagementObservation: PermissionCapabilityStatus = .unverified
    ) {
        self.fileSystem = fileSystem
        self.homeDirectory = homeDirectory
        self.appManagementObservation = appManagementObservation
    }

    public func snapshot() async -> PermissionSnapshot {
        // Other apps' data directories can have independent restrictions. They
        // are not evidence that this process lacks Full Disk Access.
        let probes = [
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC", isDirectory: true),
        ]
        var access = PermissionCapabilityStatus.unverified
        for probe in probes {
            do {
                _ = try await fileSystem.children(of: probe)
                access = .granted
                break
            } catch {
                let failure = error as NSError
                let denied = (failure.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(failure.code))
                    || (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError)
                if denied { access = .actionRequired }
            }
        }
        let settingsURL = Self.fullDiskAccessSettingsURL
        let appManagementSettingsURL = Self.appManagementSettingsURL
        let appManagementExplanation: String = switch appManagementObservation {
        case .granted: L10n.text("最近一次应用卸载已通过系统授权并成功删除")
        case .actionRequired: L10n.text("最近一次应用操作被系统拒绝或未完成，请检查 App 管理权限")
        case .unverified: L10n.text("macOS 不提供只读查询接口；将在首次真实卸载时安全验证")
        }
        let appManagement = PermissionCapabilitySnapshot(
            status: appManagementObservation,
            settingsURL: appManagementSettingsURL,
            explanation: appManagementExplanation
        )
        let explanation: String
        switch access {
        case .granted:
            explanation = L10n.text("当前 App 可读取完全磁盘访问检查位置；其他位置以实际扫描为准")
        case .actionRequired:
            explanation = L10n.text("当前 App 访问保护位置被拒绝。请检查当前版本授权，必要时重启；可继续扫描可访问位置。")
        case .unverified:
            explanation = L10n.text("无法确认完全磁盘访问状态；目录缺失或读取错误不代表未授权，可继续扫描可访问位置。")
        }
        let affected: Set<CleanupCategory> = access == .granted ? [] : [.applicationSupport, .log, .configuration]
        return PermissionSnapshot(
            level: access == .granted ? .full : .limited,
            availableCategories: Set(CleanupCategory.allCases).subtracting(affected),
            affectedCategories: affected,
            settingsURL: settingsURL,
            explanation: explanation,
            fullDiskAccess: PermissionCapabilitySnapshot(
                status: access,
                settingsURL: settingsURL,
                explanation: explanation
            ),
            appManagement: appManagement
        )
    }

}

public enum PermissionScanStartPolicy {
    public static func shouldStartFullScan(
        fullDiskAccess: PermissionCapabilityStatus
    ) -> Bool {
        true
    }
}

/// Touches the standard TCC-protected home folders serially before parallel
/// scanners start. macOS presents the Files and Folders prompt on access; the
/// scan continues with whatever locations the user allows.
public struct ScanPermissionPreflight: Sendable {
    private let fileSystem: any FileSystemAccess

    public init(fileSystem: any FileSystemAccess = LocalFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func requestStandardFolderAccess(homeDirectory: URL) async {
        for name in ["Documents", "Desktop", "Downloads"] {
            guard !Task.isCancelled else { return }
            let folder = homeDirectory.appendingPathComponent(name, isDirectory: true)
            _ = try? await fileSystem.children(of: folder)
        }
    }

    public func requestScanAccess(homeDirectory: URL, includeStandardFolders: Bool) async {
        if includeStandardFolders { await requestStandardFolderAccess(homeDirectory: homeDirectory) }
        var roots = ApplicationAssociationPathRegistry.roots(home: homeDirectory).map(\.url)
        roots += ["Applications", "Movies", "Music", "Pictures", "Library/Mail", "Library/Messages", "Library/Safari", "Library/Application Support/com.apple.TCC"]
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
        for provider in AgentProvider.allCases {
            roots += AgentResourcePathRegistry.homeRelativeRoots(for: provider)
                .map { homeDirectory.appendingPathComponent($0) }
            roots += AgentResourcePathRegistry.absoluteRoots(for: provider).map(\.url)
            roots += AgentResourcePathRegistry.environmentRoots(for: provider).map(\.url)
        }
        let applicationDataRoots = Set(["Application Support", "Containers", "Group Containers", "Caches", "WebKit", "HTTPStorages"]
            .map { homeDirectory.appendingPathComponent("Library/" + $0).standardizedFileURL })
        var pending = roots.map { ($0.standardizedFileURL, applicationDataRoots.contains($0.standardizedFileURL) ? 2 : 0) }
        var visited = Set<URL>()
        while let (directory, depth) = pending.popLast() {
            guard !Task.isCancelled else { return }
            guard visited.insert(directory).inserted,
                  let identity = try? await fileSystem.identity(at: directory), identity.kind == .directory,
                  let children = try? await fileSystem.children(of: directory) else { continue }
            if depth > 0 { pending += children.map { ($0.standardizedFileURL, depth - 1) } }
        }
    }
}

/// A prior declined preparation is not a grant. It only allows the user's chosen
/// limited mode to continue when privileged operations are unavailable.
public enum ScanPermissionPreparationPolicy {
    public static func canProceed(diskAccess: PermissionCapabilityStatus) -> Bool {
        diskAccess == .granted
    }
}
