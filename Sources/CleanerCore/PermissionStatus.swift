import Foundation

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
        let probes = [
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Mail", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Safari", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Messages", isDirectory: true),
        ]
        var readableProbeCount = 0
        var inaccessible = 0
        for probe in probes {
            do {
                _ = try await fileSystem.children(of: probe)
                readableProbeCount += 1
            } catch {
                if await fileSystem.fileExists(probe) { inaccessible += 1 }
            }
        }
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        let appManagementSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        let appManagementExplanation: String = switch appManagementObservation {
        case .granted: "最近一次应用卸载已通过系统授权并成功删除"
        case .actionRequired: "最近一次应用操作被系统拒绝或未完成，请检查 App 管理权限"
        case .unverified: "macOS 不提供只读查询接口；将在首次真实卸载时安全验证"
        }
        let appManagement = PermissionCapabilitySnapshot(
            status: appManagementObservation,
            settingsURL: appManagementSettingsURL,
            explanation: appManagementExplanation
        )
        if readableProbeCount > 0 {
            return PermissionSnapshot(
                level: .full,
                availableCategories: Set(CleanupCategory.allCases),
                affectedCategories: [],
                settingsURL: settingsURL,
                explanation: "可访问所有已启用的扫描区域",
                fullDiskAccess: PermissionCapabilitySnapshot(
                    status: .granted,
                    settingsURL: settingsURL,
                    explanation: "可读取已启用的系统保护扫描区域"
                ),
                appManagement: appManagement
            )
        }
        if inaccessible == 0 {
            let affected: Set<CleanupCategory> = [.applicationSupport, .log, .configuration]
            return PermissionSnapshot(
                level: .limited,
                availableCategories: Set(CleanupCategory.allCases).subtracting(affected),
                affectedCategories: affected,
                settingsURL: settingsURL,
                explanation: "当前没有可用于验证完全磁盘访问的系统保护目录",
                fullDiskAccess: PermissionCapabilitySnapshot(
                    status: .unverified,
                    settingsURL: settingsURL,
                    explanation: "无法从当前账户的目录状态确认；可重新检查或在扫描结果中查看实际覆盖范围"
                ),
                appManagement: appManagement
            )
        }
        let affected: Set<CleanupCategory> = [.applicationSupport, .log, .configuration]
        return PermissionSnapshot(
            level: .limited,
            availableCategories: Set(CleanupCategory.allCases).subtracting(affected),
            affectedCategories: affected,
            settingsURL: settingsURL,
            explanation: "部分受系统保护区域不可访问；其余清理和历史恢复仍可使用",
            fullDiskAccess: PermissionCapabilitySnapshot(
                status: .actionRequired,
                settingsURL: settingsURL,
                    explanation: "系统保护目录不可读取；请在系统设置中为当前 App 开启完全磁盘访问"
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
}
