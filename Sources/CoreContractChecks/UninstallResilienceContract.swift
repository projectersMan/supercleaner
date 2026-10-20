import CleanerCore
import Foundation

/// Optional read-only reproduction against explicitly supplied installed apps.
/// This constructs plans only; it never executes them or writes to application data.
func runInstalledUninstallReadOnlyCheck(paths: [String]) async throws {
    require(!paths.isEmpty, "provide application paths for the read-only uninstall check")
    let metadataProvider = BundleApplicationMetadataProvider()
    let apps = paths.compactMap { path -> InstalledApplication? in
        let url = URL(fileURLWithPath: path)
        guard let metadata = metadataProvider.metadata(for: url) else { return nil }
        return InstalledApplication(
            bundleURL: url, bundleIdentifier: metadata.bundleIdentifier, name: metadata.name,
            version: metadata.version, isRunning: false, isSystem: path.hasPrefix("/System/")
        )
    }
    require(apps.count == paths.count, "every supplied application must have readable bundle metadata")
    let context = ScanContext(homeDirectory: FileManager.default.homeDirectoryForCurrentUser, fileSystem: LocalFileSystem())
    let inventory = await ApplicationUninstallAnalyzer().analyze(
        inventory: ApplicationInventory(applications: apps, coverage: .init(), scannedAt: Date()),
        context: context
    )
    for app in apps {
        guard let analysis = inventory.analysis(for: app.id) else {
            require(false, "analysis missing for \(app.name)")
            continue
        }
        require(analysis.plan != nil, "\(app.name): \(analysis.message ?? "unavailable")")
        print("Read-only uninstall check: \(app.name), state=\(analysis.state.rawValue), planItems=\(analysis.plan?.items.count ?? 0), limitations=\(analysis.limitations.count)")
    }
}

func runUninstallResilienceContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("SuperCleaner-Uninstall-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }

    // Reproduce the exact Electron singleton-link failure with the real filesystem.
    let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
    try manager.createDirectory(at: appURL, withIntermediateDirectories: true)
    try Data("application".utf8).write(to: appURL.appendingPathComponent("payload"))
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    let cookie = cache.appendingPathComponent("SingletonCookie")
    try manager.createSymbolicLink(atPath: cookie.path, withDestinationPath: "missing-cookie-target")
    let context = ScanContext(homeDirectory: root, fileSystem: LocalFileSystem())
    let app = InstalledApplication(bundleURL: appURL, bundleIdentifier: "com.example.resilient", name: "Example", version: nil, isRunning: false, isSystem: false)
    let cacheAssociation = ApplicationAssociation(url: cache, kind: .cache, ownershipEvidence: "fixture", containsUserData: false, isShared: false, risk: .safe)
    do {
        let plan = try await UninstallPlanner().buildPlan(app, associations: [cacheAssociation], context: context)
        require(plan.plan.items.contains { $0.candidate.url.path == appURL.path }, "a dangling Electron singleton link must not discard the application's uninstall plan")
    } catch {
        require(false, "dangling Electron singleton links must be measured as links, not missing files: \(error)")
    }
    let linkIdentity = try await LocalFileSystem().identity(at: cookie)
    require(linkIdentity.kind == .symbolicLink, "real dangling links must expose their own filesystem identity")

    let fileSystem = UninstallResilienceFileSystem(home: root, application: appURL, cache: cache)
    let failingContext = ScanContext(homeDirectory: root, fileSystem: fileSystem)
    let inventory = ApplicationInventory(applications: [app], coverage: .init(), scannedAt: Date())
    let analysis = await ApplicationUninstallAnalyzer().analyze(inventory: inventory, context: failingContext)
    let result = analysis.analysis(for: app.id)
    require(result?.plan?.items.contains { $0.candidate.url.path == appURL.path } == true, "an unreadable cache descendant must leave the application bundle uninstallable")
    require(result?.state == .limited, "incomplete cache measurement must be reported as limited, not as an unavailable app")
    require(result?.limitations.contains { $0.title == L10n.text("没有读取权限") && $0.path?.lastPathComponent == "restricted.run" } == true, "uninstall diagnostics must preserve the actual permission failure and its path")
    let inspectedCachePath = root.appendingPathComponent("Library/Caches/com.example.resilient").path
    require(result?.plan?.items.first { $0.candidate.url.path == inspectedCachePath }?.candidate.risk == .review, "a partially measured association must be opt-in review, not permanently protected")
    let visited = await fileSystem.visitedPaths()
    require(visited.contains(fileSystem.userDataChild.path), "explicitly selectable exclusive user data must be included in uninstall size measurement")

    let partialBundleFS = UninstallResilienceFileSystem(home: root, application: appURL, cache: cache, bundleChildFails: true)
    let partialBundle = await ApplicationUninstallAnalyzer().analyze(inventory: inventory, context: ScanContext(homeDirectory: root, fileSystem: partialBundleFS))
    require(partialBundle.analysis(for: app.id)?.plan != nil, "a size error inside a readable application bundle must not discard the bundle's uninstall plan")
    require(partialBundle.analysis(for: app.id)?.state == .limited, "a partially measured application bundle must report incomplete size")

    let missingBundleFS = UninstallResilienceFileSystem(home: root, application: appURL, cache: cache, bundleMissing: true)
    let missingBundle = await ApplicationUninstallAnalyzer().analyze(inventory: inventory, context: ScanContext(homeDirectory: root, fileSystem: missingBundleFS))
    require(missingBundle.analysis(for: app.id)?.state == .unavailable, "an unverifiable application root must remain unavailable")
    require(missingBundle.analysis(for: app.id)?.plan == nil, "an unverifiable application root must never get an executable uninstall plan")
}

private actor UninstallResilienceFileSystem: FileSystemAccess {
    let userDataChild: URL
    private let application: URL
    private let cache: URL
    private let cacheRoot: URL
    private let userData: URL
    private let supportRoot: URL
    private let failingChild: URL
    private let payload: URL
    private let bundleChildFails: Bool
    private let bundleMissing: Bool
    private var visited = Set<String>()

    init(home: URL, application: URL, cache: URL, bundleChildFails: Bool = false, bundleMissing: Bool = false) {
        self.application = application
        self.cache = cache
        self.bundleChildFails = bundleChildFails
        self.bundleMissing = bundleMissing
        cacheRoot = home.appendingPathComponent("Library/Caches")
        supportRoot = home.appendingPathComponent("Library/Application Support")
        userData = supportRoot.appendingPathComponent("com.example.resilient")
        userDataChild = userData.appendingPathComponent("private-user-data")
        failingChild = cache.appendingPathComponent("restricted.run")
        payload = application.appendingPathComponent("payload")
    }

    func identity(at url: URL) throws -> FileIdentity {
        visited.insert(url.path)
        if url.path == failingChild.path || (bundleChildFails && url.path == payload.path) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        }
        if bundleMissing && url.path == application.path { throw FileSystemError.missing(url) }
        return FileIdentity(device: 1, inode: 1, size: 12, modificationTime: 1, kind: url.path == payload.path ? .file : .directory)
    }
    func children(of url: URL) throws -> [URL] {
        visited.insert(url.path)
        if url.path == cacheRoot.path {
            // Match the scanner's bundle-ID ownership rule.
            return [cacheRoot.appendingPathComponent("com.example.resilient")]
        }
        if url.path == cacheRoot.appendingPathComponent("com.example.resilient").path { return [failingChild] }
        if url.path == supportRoot.path { return [userData] }
        if url.path == application.path { return [payload] }
        if url.path == cache.path { return [failingChild] }
        if url.path == userData.path { return [userDataChild] }
        return []
    }
    func fileExists(_ url: URL) -> Bool { [cacheRoot.path, supportRoot.path, application.path].contains(url.path) }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
    func visitedPaths() -> Set<String> { visited }
}
