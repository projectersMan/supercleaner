import CleanerCore
import Foundation

func runPermissionContracts() async {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let snapshot = await PermissionStatusService(
        fileSystem: DeniedPermissionFileSystem(),
        homeDirectory: home,
        appManagementObservation: .unverified
    ).snapshot()
    require(snapshot.level == .limited, "denied full disk access should degrade to limited")
    require(!snapshot.affectedCategories.isEmpty, "limited permission must explain affected categories")
    require(snapshot.availableCategories.contains(.cache), "permission denial must not disable all scanning")
    require(snapshot.settingsURL.absoluteString.hasPrefix("x-apple.systempreferences:"), "permission snapshot must provide settings deep link")
    require(snapshot.fullDiskAccess.status == .actionRequired, "full disk access must expose an actionable independent status")
    require(snapshot.appManagement.status == .unverified, "app management must remain honest before a real uninstall result exists")
    require(
        snapshot.appManagement.settingsURL.absoluteString.contains("Privacy_AppBundles"),
        "app management must deep-link to the App Management pane"
    )
    require(
        PermissionScanStartPolicy.shouldStartFullScan(fullDiskAccess: .actionRequired),
        "limited full disk access must start scanning so macOS can request native authorization"
    )

    let grantedSnapshot = await PermissionStatusService(
        fileSystem: GrantedPermissionFileSystem(),
        homeDirectory: home,
        appManagementObservation: .granted
    ).snapshot()
    require(grantedSnapshot.fullDiskAccess.status == .granted, "readable protected probes must report full disk access")
    require(grantedSnapshot.appManagement.status == .granted, "a successful observed app operation must report app management as available")

    let missingProbeSnapshot = await PermissionStatusService(
        fileSystem: MissingPermissionProbeFileSystem(),
        homeDirectory: home
    ).snapshot()
    require(
        missingProbeSnapshot.fullDiskAccess.status == .unverified,
        "missing protected probes must remain unverified instead of falsely requesting authorization"
    )
}

private actor DeniedPermissionFileSystem: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) throws -> [URL] { throw FileSystemError.unreadableContent(url) }
    func isReadable(_ url: URL) -> Bool { !url.path.contains("Library/Mail") }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor GrantedPermissionFileSystem: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private actor MissingPermissionProbeFileSystem: FileSystemAccess {
    func identity(at url: URL) throws -> FileIdentity { throw FileSystemError.missing(url) }
    func children(of url: URL) throws -> [URL] { throw FileSystemError.missing(url) }
    func isReadable(_ url: URL) -> Bool { false }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { false }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
