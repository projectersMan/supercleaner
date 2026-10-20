import CleanerCore
import Foundation

func runInstallerDiscoveryContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("installer-contract-\(UUID().uuidString)")
    let home = root.appendingPathComponent("home")
    let downloads = home.appendingPathComponent("Downloads")
    let nested = downloads.appendingPathComponent("nested")
    let brew = home.appendingPathComponent("Library/Caches/Homebrew/downloads")
    let mail = home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/attachment")
    for directory in [nested, brew, mail] { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
    defer { try? manager.removeItem(at: root) }
    let dmg = nested.appendingPathComponent("Example.DMG")
    let brewPackage = brew.appendingPathComponent("download.pkg")
    let mailISO = mail.appendingPathComponent("attachment.iso")
    for path in [dmg, brewPackage, mailISO] { try Data("installer fixture".utf8).write(to: path) }
    let mpkg = downloads.appendingPathComponent("Legacy.mpkg")
    try manager.createDirectory(at: mpkg, withIntermediateDirectories: true)
    try Data("package payload".utf8).write(to: mpkg.appendingPathComponent("payload"))
    let staging = root.appendingPathComponent("archive-source/Example.app/Contents")
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    try Data("fixture info".utf8).write(to: staging.appendingPathComponent("Info.plist"))
    let zip = downloads.appendingPathComponent("Example.zip")
    let zipped = try await BoundedProcess.run("/usr/bin/zip", arguments: ["-rq", zip.path, "Example.app"], directory: root.appendingPathComponent("archive-source"))
    require(zipped.status == 0, "installer ZIP fixture creation failed")
    try Data("broken zip".utf8).write(to: downloads.appendingPathComponent("broken.zip"))
    let ordinary = downloads.appendingPathComponent("ordinary.zip")
    let ordinaryZip = try await BoundedProcess.run("/usr/bin/zip", arguments: ["-q", ordinary.path, "payload"], directory: mpkg)
    require(ordinaryZip.status == 0, "ordinary ZIP fixture creation failed")
    let outside = root.appendingPathComponent("outside")
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    let ignored = outside.appendingPathComponent("private.dmg")
    try Data("outside fixture".utf8).write(to: ignored)
    try manager.createSymbolicLink(at: downloads.appendingPathComponent("linked"), withDestinationURL: outside)
    let context = ScanContext(homeDirectory: home)
    let found = try await InstallerScanner().scan(context: context)
    require(Set(found.map { $0.url.path }) == Set([dmg, brewPackage, mailISO, mpkg, zip].map(\.path)), "installer discovery must cover nested sources, MPKG and validated ZIP only; found: \(found.map { $0.url.path })")
    require(found.allSatisfy { $0.defaultSelection == false && $0.risk == .review }, "installers must require explicit selection")
    require(found.first { $0.url.path == mpkg.path }?.bytes == 15, "directory package size must include payload")
    let explicitAlias = root.appendingPathComponent("explicit")
    try manager.createSymbolicLink(at: explicitAlias, withDestinationURL: outside)
    let expanded = try await InstallerScanner(additionalRoots: [explicitAlias]).scan(context: context)
    require(expanded.contains { $0.url.path == ignored.resolvingSymlinksInPath().path }, "explicit scan root aliases must work without following descendant links")
    let policy = ProtectionPolicy(entries: [ProtectedPath(url: dmg)], homeDirectory: home)
    let protected = try await InstallerScanner().scan(context: ScanContext(homeDirectory: home, protectionPolicy: policy))
    require(protected.first { $0.url.path == dmg.path }?.risk == .blocked, "installer discovery must obey durable protection policy")
    do {
        _ = try await InstallerScanner(maximumEntries: 1).scan(context: context)
        require(false, "entry budget must discard incomplete installer list")
    } catch InstallerDiscoveryError.entryBudgetExceeded {}
    do {
        _ = try await InstallerDiscovery(timeLimit: 0).scan(context: context)
        require(false, "cumulative deadline must discard installer list")
    } catch InstallerDiscoveryError.deadlineExceeded {}
    let cancelled = Task { try await InstallerScanner().scan(context: context) }
    cancelled.cancel()
    do { _ = try await cancelled.value; require(false, "cancelled installer scan must not publish candidates") } catch is CancellationError {}
    do {
        _ = try await BoundedProcess.run("/bin/sleep", arguments: ["5"], timeout: 0.05)
        require(false, "subprocess must honor timeout")
    } catch ProcessFailure.timedOut {}
    do {
        _ = try await BoundedProcess.run("/usr/bin/yes", arguments: [], maximumOutputBytes: 256)
        require(false, "subprocess must cap captured output")
    } catch ProcessFailure.outputLimit {}
    print("PASS: multi-source installers, validated archives, budgets, cancellation and process limits")
}
