import CleanerCore
import Foundation

private struct DiagnosticNoInstallations: ApplicationInstallationInspecting {
    func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary) { ([:], .init()) }
}

func runApplicationDiagnosticContracts() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Diagnostics-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    let bundle = home.appendingPathComponent("Applications/ImageViewer.app")
    let records = home.appendingPathComponent("Library/Application Support/CrashReporter")
    let reports = home.appendingPathComponent("Library/Logs/DiagnosticReports")
    for directory in [bundle.appendingPathComponent("Contents"), records, reports] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
    let info = ["CFBundleIdentifier": "com.imageviewer.app", "CFBundleName": "ImageViewer", "CFBundleExecutable": "ImageViewer", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    let app = InstalledApplication(bundleURL: bundle, bundleIdentifier: "com.imageviewer.app", name: "ImageViewer", version: "1", isRunning: false, isSystem: false)
    let context = ScanContext(homeDirectory: home)
    let scanner = ApplicationScanner(ownershipBuilder: .init(installationInspector: DiagnosticNoInstallations(), configurationFiles: [], includeSystemRoots: false), applicationRoots: [home.appendingPathComponent("Applications")], diagnosticScanner: .init(includeSystemRoots: false))
    let record = records.appendingPathComponent("ImageViewer_553E02D9-4546-5421-9E9A-29A5EF070B79.plist")
    try PropertyListSerialization.data(fromPropertyList: ["Date": Date()], format: .binary, options: 0).write(to: record)
    let ips = reports.appendingPathComponent("ImageViewer-2026-10-27-183052.ips")
    let payload = #"{"app_name":"ImageViewer","bundleID":"com.imageviewer.app"}"# + "\n" + #"{"procName":"ImageViewer","procPath":"/Applications/ImageViewer.app/Contents/MacOS/ImageViewer","bundleInfo":{"CFBundleIdentifier":"com.imageviewer.app"}}"#
    try Data(payload.utf8).write(to: ips)
    let index = await scanner.associationIndex(for: [app], context: context)
    let associations = index.associations[app.id, default: []]
    require(associations.contains { $0.url.path == record.path && $0.risk == .review }, "CrashReporter date record must be discovered and opt-in")
    require(associations.contains { $0.url.path == ips.path && $0.risk == .review }, "IPS report must be associated by its embedded bundle identity")
    require(!associations.contains { $0.url.path == records.path || $0.url.path == reports.path }, "never offer an entire shared diagnostic directory")
    let analyzed = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(inventory: .init(applications: [app], coverage: .init(), scannedAt: Date()), context: context)
    let diagnosticItems = analyzed.plans.flatMap(\.items).filter { $0.candidate.evidence.contains { $0.code == "diagnostic-file" } }
    require(diagnosticItems.count == 2 && diagnosticItems.allSatisfy { $0.candidate.category == .log && $0.candidate.risk == .review }, "diagnostics are individually reviewable logs, never safe/default candidates")
    require(UninstallBatchSelectionState().selectedItems(in: analyzed.plans).isEmpty, "diagnostics are not automatically selected")
    let oldCandidate = diagnosticItems.first { $0.candidate.url.path == ips.path }!.candidate
    try await ApplicationExecutionValidator(scanner: scanner).validate(oldCandidate, context: context)
    try Data(payload.replacingOccurrences(of: "com.imageviewer.app", with: "com.unrelated.app").utf8).write(to: ips)
    do {
        try await ApplicationExecutionValidator(scanner: scanner).validate(oldCandidate, context: context)
        require(false, "changed report identity must invalidate an earlier uninstall plan")
    } catch ApplicationExecutionRejection.stillReferenced { }
    try Data(payload.utf8).write(to: ips)

    // CrashReporter also stores force-quit timestamps, including records that
    // have both a crash date and a force-quit date.
    for dates in [["ForceQuitDate": Date()], ["Date": Date(), "ForceQuitDate": Date()]] {
        try PropertyListSerialization.data(fromPropertyList: dates, format: .binary, options: 0).write(to: record)
        let updated = await scanner.associationIndex(for: [app], context: context)
        require(updated.associations[app.id]?.first { $0.url.path == record.path }?.risk == .review,
                "valid force-quit timestamps must be individually reviewable diagnostic records")
    }
    let invalidRecords: [[String: Any]] = [[:], ["ForceQuitDate": "not a date"],
        ["Date": Date(), "ForceQuitDate": "not a date"], ["UnrecognizedDate": Date()],
        ["Date": Date(), "Other": "unexpected"]]
    for dates in invalidRecords {
        try PropertyListSerialization.data(fromPropertyList: dates, format: .binary, options: 0).write(to: record)
        let updated = await scanner.associationIndex(for: [app], context: context)
        require(updated.associations[app.id]?.first { $0.url.path == record.path }?.risk == .blocked,
                "empty, unknown or invalid timestamp fields must remain protected")
    }
    try PropertyListSerialization.data(fromPropertyList: ["Date": Date()], format: .binary, options: 0).write(to: record)

    let retired = reports.appendingPathComponent("Retired")
    let legacy = home.appendingPathComponent("Library/Logs/CrashReporter")
    for directory in [retired, legacy] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
    try Data(payload.utf8).write(to: retired.appendingPathComponent("renamed.ips"))
    let oldText = "Process: ImageViewer [123]\nPath: \(bundle.path)/Contents/MacOS/ImageViewer\nIdentifier: com.imageviewer.app\nVersion: 1\n\nBinary Images:\nIdentifier: com.unrelated.app\n"
    try Data(oldText.utf8).write(to: legacy.appendingPathComponent("ImageViewer_2026-10-28-120000_machine.crash"))
    let pathOnly = reports.appendingPathComponent("path-only.crash")
    try Data("Process: ImageViewer [123]\nPath: \(bundle.path)/Contents/MacOS/ImageViewer\n\n".utf8).write(to: pathOnly)
    let weak = reports.appendingPathComponent("ImageViewer-2026-10-28-120001.ips")
    try Data(#"{"app_name":"ImageViewer"}"#.utf8).write(to: weak)
    let conflict = reports.appendingPathComponent("ImageViewer-2026-10-28-120002.ips")
    try Data((#"{"bundleID":"com.imageviewer.app"}"# + "\n" + #"{"bundleInfo":{"CFBundleIdentifier":"com.unrelated.app"}}"#).utf8).write(to: conflict)
    let broken = reports.appendingPathComponent("ImageViewer-2026-10-28-120003.ips")
    try Data((#"{"bundleID":"com.imageviewer.app"}"# + "\n{broken").utf8).write(to: broken)
    let prefix = records.appendingPathComponent("ImageViewerPro_553E02D9-4546-5421-9E9A-29A5EF070B79.plist")
    try fm.copyItem(at: record, to: prefix)
    let invalidUUID = records.appendingPathComponent("ImageViewer_not-a-uuid.plist")
    try fm.copyItem(at: record, to: invalidUUID)
    let badRecord = records.appendingPathComponent("ImageViewer_653E02D9-4546-5421-9E9A-29A5EF070B79.plist")
    try PropertyListSerialization.data(fromPropertyList: ["Date": "not a date"], format: .binary, options: 0).write(to: badRecord)
    let link = reports.appendingPathComponent("ImageViewer-2026-10-28-120004.ips")
    try fm.createSymbolicLink(at: link, withDestinationURL: ips)
    let nested = reports.appendingPathComponent("Unrelated")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data(payload.utf8).write(to: nested.appendingPathComponent("deep.ips"))
    let extended = await scanner.associationIndex(for: [app], context: context)
    let items = extended.associations[app.id, default: []]
    func risk(_ url: URL) -> RiskLevel? { items.first { $0.url.path == url.path }?.risk }
    require(risk(retired.appendingPathComponent("renamed.ips")) == .review && risk(pathOnly) == .review, "retired and exact process-path reports are recognized")
    require(risk(legacy.appendingPathComponent("ImageViewer_2026-10-28-120000_machine.crash")) == .review, "legacy header identity ignores unrelated identifiers in stack/library sections")
    require(risk(weak) == .blocked && risk(conflict) == .blocked && risk(broken) == .blocked && risk(badRecord) == .blocked, "weak, conflicting and malformed evidence stays protected")
    require(risk(prefix) == nil && risk(invalidUUID) == nil && risk(link) == nil && risk(nested.appendingPathComponent("deep.ips")) == nil, "reject prefix collisions, invalid UUIDs, symlinks and arbitrary nested folders")
    require(extended.coverage.unavailableRoots.contains { $0.path == broken.path }, "unreadable/corrupt supported reports report limited coverage")

    let copyURL = home.appendingPathComponent("Applications/ImageViewer Copy.app")
    let copy = InstalledApplication(bundleURL: copyURL, bundleIdentifier: app.bundleIdentifier, name: "ImageViewer Copy", version: "1", isRunning: false, isSystem: false)
    let shared = await scanner.associationIndex(for: [app, copy], context: context)
    require(shared.associations[app.id]?.first { $0.url.path == record.path }?.risk == .blocked, "another installed copy protects the date record")
    require(shared.associations[app.id]?.first { $0.url.path == ips.path }?.isShared == true, "report ownership expands to every installed copy")
    let unrelated = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Other.app"), bundleIdentifier: "com.unrelated.app", name: "Other", version: "1", isRunning: false, isSystem: false)
    let conflictIndex = await scanner.associationIndex(for: [app, unrelated], context: context)
    require(conflictIndex.associations[unrelated.id]?.first { $0.url.path == conflict.path }?.risk == .blocked, "conflicting identities must not authorize either app")
    let publicRootApp = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/CrashReporter.app"), bundleIdentifier: "com.contract.reporter", name: "CrashReporter", version: "1", isRunning: false, isSystem: false)
    let rootsIndex = await scanner.associationIndex(for: [publicRootApp], context: context)
    require(!rootsIndex.associations[publicRootApp.id, default: []].contains { $0.url.path == records.path || $0.url.path == legacy.path }, "generic display-name rules cannot claim shared diagnostic directories")

    let systemDirectory = root.appendingPathComponent("system-reports")
    try fm.createDirectory(at: systemDirectory, withIntermediateDirectories: true)
    try Data(payload.utf8).write(to: systemDirectory.appendingPathComponent("ImageViewer-system.ips"))
    let virtualRoot = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
    let redirected = DiagnosticRedirectFileSystem(virtualRoot: virtualRoot, backingRoot: systemDirectory, deniedRoot: records)
    let restricted = await ApplicationDiagnosticScanner().scan(applications: [app], context: ScanContext(homeDirectory: home, fileSystem: redirected))
    require(restricted.associations[app.id]?.first { $0.url.path == virtualRoot.appendingPathComponent("ImageViewer-system.ips").path }?.risk == .blocked, "system diagnostics stay protected")
    require(restricted.coverage.unavailableRoots.contains { $0.path == records.path }, "denied shared directories must be reported as unavailable")

    let truncated = await ApplicationDiagnosticScanner(maximumEntries: 0, includeSystemRoots: false).scan(applications: [app], context: context)
    require(truncated.coverage.budgetLimitedModules.contains(.applications) && truncated.associations.isEmpty, "entry limits are explicit, never silent complete scans")
    let byteLimited = await ApplicationDiagnosticScanner(maximumTotalBytes: 1, includeSystemRoots: false).scan(applications: [app], context: context)
    require(byteLimited.coverage.budgetLimitedModules.contains(.applications), "total read budget is enforced")
    let oversized = await ApplicationDiagnosticScanner(maximumFileBytes: 8, includeSystemRoots: false).scan(applications: [app], context: context)
    require(!oversized.coverage.unavailableRoots.isEmpty && oversized.associations.isEmpty, "oversized reports never become deletable")
    let cancelled = Task { await ApplicationDiagnosticScanner(includeSystemRoots: false).scan(applications: [app], context: context) }
    cancelled.cancel()
    let cancelledResult = await cancelled.value
    require(cancelledResult.coverage.budgetLimitedModules.contains(.applications), "cancelled discovery reports incomplete coverage")
    print("PASS: diagnostic records, IPS/legacy headers, retained reports, exact identity, conflicts, copies, symlinks, budgets and execution revalidation")
}

private struct DiagnosticRedirectFileSystem: FileSystemAccess {
    let virtualRoot: URL
    let backingRoot: URL
    let deniedRoot: URL
    private let local = LocalFileSystem()
    private func physical(_ url: URL) -> URL {
        if url.path == virtualRoot.path { return backingRoot }
        if url.path.hasPrefix(virtualRoot.path + "/") {
            return backingRoot.appendingPathComponent(String(url.path.dropFirst(virtualRoot.path.count + 1)))
        }
        return url
    }
    func identity(at url: URL) async throws -> FileIdentity { try await local.identity(at: physical(url)) }
    func children(of url: URL) async throws -> [URL] {
        if url.path == deniedRoot.path { throw FileSystemError.unreadableContent(url) }
        let children = try await local.children(of: physical(url))
        return children.map { url.appendingPathComponent($0.lastPathComponent) }
    }
    func isReadable(_ url: URL) async -> Bool { url.path != deniedRoot.path }
    func isWritable(_ url: URL) async -> Bool { false }
    func fileExists(_ url: URL) async -> Bool { await local.fileExists(physical(url)) }
    func readData(at url: URL, maximumBytes: Int) async throws -> Data { try await local.readData(at: physical(url), maximumBytes: maximumBytes) }
    func move(_ source: URL, to destination: URL) async throws { throw FileSystemError.unreadableContent(source) }
    func createDirectory(_ url: URL) async throws { throw FileSystemError.unreadableContent(url) }
    func removeEmptyDirectory(_ url: URL) async throws { throw FileSystemError.unreadableContent(url) }
    func trash(_ url: URL) async throws -> URL { throw FileSystemError.unreadableContent(url) }
}
