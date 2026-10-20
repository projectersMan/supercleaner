import CleanerCore
import Foundation

func runCachedFirmwareScannerContracts() async throws {
    let home = URL(fileURLWithPath: "/Users/firmware-tester", isDirectory: true)
    let now = Date(timeIntervalSince1970: 30_000_000)
    let phoneRoot = home.appendingPathComponent("Library/iTunes/iPhone Software Updates", isDirectory: true)
    let tabletRoot = home.appendingPathComponent("Library/iTunes/iPad Software Updates", isDirectory: true)
    let mediaPlayerRoot = home.appendingPathComponent("Library/iTunes/iPod Software Updates", isDirectory: true)
    let configuratorRoot = home.appendingPathComponent(
        "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware",
        isDirectory: true
    )
    let configuratorPhoneRoot = configuratorRoot.appendingPathComponent("iPhone", isDirectory: true)

    let phoneFirmware = phoneRoot.appendingPathComponent("phone.ipsw")
    let duplicatePhoneFirmware = phoneRoot.appendingPathComponent("nested/../phone.ipsw")
    let activeTabletFirmware = tabletRoot.appendingPathComponent("tablet.IPSW")
    let linkedMediaPlayerFirmware = mediaPlayerRoot.appendingPathComponent("player.ipsw")
    let nestedConfiguratorFirmware = configuratorPhoneRoot.appendingPathComponent("configurator.ipsw")
    let unknownConfiguratorFirmware = configuratorPhoneRoot.appendingPathComponent("unknown.ipsw")
    let unrelatedArchive = phoneRoot.appendingPathComponent("backup.zip")
    let nestedITunesDirectory = phoneRoot.appendingPathComponent("nested", isDirectory: true)
    let nestedITunesFirmware = nestedITunesDirectory.appendingPathComponent("not-in-shallow-scope.ipsw")

    let fileSystem = CachedFirmwareContractFileSystem(entries: [
        phoneRoot: [
            CachedFirmwareContractEntry(url: phoneFirmware, size: 6_000, modified: now),
            CachedFirmwareContractEntry(url: duplicatePhoneFirmware, size: 6_000, modified: now),
            CachedFirmwareContractEntry(url: unrelatedArchive, size: 500, modified: now),
            CachedFirmwareContractEntry(url: nestedITunesDirectory, size: 0, modified: now, kind: .directory),
        ],
        nestedITunesDirectory: [
            CachedFirmwareContractEntry(url: nestedITunesFirmware, size: 6_100, modified: now),
        ],
        tabletRoot: [
            CachedFirmwareContractEntry(url: activeTabletFirmware, size: 6_200, modified: now),
        ],
        mediaPlayerRoot: [
            CachedFirmwareContractEntry(url: linkedMediaPlayerFirmware, size: 6_300, modified: now, kind: .symbolicLink),
        ],
        configuratorRoot: [
            CachedFirmwareContractEntry(url: configuratorPhoneRoot, size: 0, modified: now, kind: .directory),
        ],
        configuratorPhoneRoot: [
            CachedFirmwareContractEntry(url: nestedConfiguratorFirmware, size: 6_400, modified: now),
            CachedFirmwareContractEntry(url: unknownConfiguratorFirmware, size: 6_500, modified: now, kind: .other),
        ],
    ])
    let context = ScanContext(
        homeDirectory: home,
        fileSystem: fileSystem,
        now: now,
        activePaths: [activeTabletFirmware]
    )

    let candidates = try await CachedFirmwareScanner().scan(context: context)
    let byPath: [String: CleanupCandidate] = Dictionary(
        candidates.map { ($0.url.standardizedFileURL.path, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    require(byPath[phoneFirmware.standardizedFileURL.path]?.risk == .review, "cached firmware must always require explicit review")
    require(byPath[nestedConfiguratorFirmware.standardizedFileURL.path]?.risk == .review, "nested Configurator firmware must require explicit review")
    require(byPath[activeTabletFirmware.standardizedFileURL.path]?.risk == .blocked, "active firmware must remain blocked")
    require(byPath[linkedMediaPlayerFirmware.standardizedFileURL.path]?.risk == .blocked, "symbolic-link firmware must remain blocked")
    require(byPath[unknownConfiguratorFirmware.standardizedFileURL.path]?.risk == .blocked, "unknown firmware entries must remain blocked")
    require(!byPath.keys.contains(unrelatedArchive.standardizedFileURL.path), "non-IPSW files must not enter firmware cleanup")
    require(!byPath.keys.contains(nestedITunesFirmware.standardizedFileURL.path), "legacy iTunes roots must remain shallow")
    require(candidates.allSatisfy { $0.category == .installerArtifact && $0.source == .general }, "firmware must have explicit installer-artifact classification")
    require(candidates.allSatisfy { $0.risk != .safe }, "firmware must never become automatic cleanup")
    require(candidates.allSatisfy { $0.evidence.contains(where: { $0.code == "cached-device-firmware" }) }, "firmware candidates must explain why they were discovered")
    require(candidates.map { $0.url.standardizedFileURL.path }.count == Set(candidates.map { $0.url.standardizedFileURL.path }).count, "firmware candidates must be canonical-path deduplicated")

    let requestedRoots = Set(await fileSystem.requestedChildren())
    require(requestedRoots.isSuperset(of: [phoneRoot.path, tabletRoot.path, mediaPlayerRoot.path, configuratorRoot.path]), "firmware scanning must inspect every supported exact root")
    require(!requestedRoots.contains(home.appendingPathComponent("Library/Group Containers", isDirectory: true).path), "firmware scanning must not enumerate arbitrary group containers")
    require(!requestedRoots.contains(nestedITunesDirectory.path), "firmware scanning must not recurse through legacy iTunes roots")

    let report = await SystemScanCoordinator().scan(context: context)
    require(
        report?.generalCandidates.contains(where: { $0.url.standardizedFileURL == nestedConfiguratorFirmware.standardizedFileURL }) == true,
        "full-system scanning must include cached firmware discovery"
    )
    let mutationCount = await fileSystem.mutationCount()
    require(mutationCount == 0, "firmware scanning must remain read-only")
}

private struct CachedFirmwareContractEntry: Sendable {
    let url: URL
    let size: UInt64
    let modified: Date
    let kind: FileIdentity.Kind

    init(url: URL, size: UInt64, modified: Date, kind: FileIdentity.Kind = .file) {
        self.url = url
        self.size = size
        self.modified = modified
        self.kind = kind
    }
}

private actor CachedFirmwareContractFileSystem: FileSystemAccess {
    private let entries: [URL: [CachedFirmwareContractEntry]]
    private let entriesByPath: [String: CachedFirmwareContractEntry]
    private var childRequests: [String] = []
    private var writes = 0

    init(entries: [URL: [CachedFirmwareContractEntry]]) {
        self.entries = entries
        self.entriesByPath = Dictionary(
            entries.values.lazy.flatMap { $0 }.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func identity(at url: URL) throws -> FileIdentity {
        guard let entry = entriesByPath[url.standardizedFileURL.path] else {
            throw FileSystemError.missing(url)
        }
        return FileIdentity(
            device: 1,
            inode: UInt64(bitPattern: Int64(url.standardizedFileURL.path.hashValue)),
            size: entry.size,
            modificationTime: Int64(entry.modified.timeIntervalSince1970),
            kind: entry.kind
        )
    }

    func children(of url: URL) -> [URL] {
        childRequests.append(url.standardizedFileURL.path)
        return entries.first { $0.key.standardizedFileURL.path == url.standardizedFileURL.path }?.value.map(\.url) ?? []
    }

    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool {
        entries.keys.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }
    func move(_ source: URL, to destination: URL) { writes += 1 }
    func createDirectory(_ url: URL) { writes += 1 }
    func removeEmptyDirectory(_ url: URL) { writes += 1 }
    func trash(_ url: URL) -> URL { writes += 1; return url }
    func requestedChildren() -> [String] { childRequests }
    func mutationCount() -> Int { writes }
}
