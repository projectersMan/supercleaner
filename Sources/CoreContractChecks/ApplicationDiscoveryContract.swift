import CleanerCore
import Foundation

private struct DiscoveryNoInstallations: ApplicationInstallationInspecting {
    func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary) { ([:], .init()) }
}

func runApplicationDiscoveryContracts() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Discovery-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    let bundle = home.appendingPathComponent("Applications/Cetus ADE.app")
    let appRoot = bundle.appendingPathComponent("Contents/Resources/app")
    let data = home.appendingPathComponent("Library/Application Support/Cetus")
    try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
    try fm.createDirectory(at: data, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: data.appendingPathComponent("state.db"))
    let info: [String: Any] = ["CFBundleIdentifier": "com.contract.cetus", "CFBundleName": "Cetus ADE", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    let app = InstalledApplication(bundleURL: bundle, bundleIdentifier: "com.contract.cetus", name: "Cetus ADE", version: "1", isRunning: false, isSystem: false)
    let context = ScanContext(homeDirectory: home)
    let scanner = ApplicationScanner(ownershipBuilder: .init(installationInspector: DiscoveryNoInstallations(), configurationFiles: [], includeSystemRoots: false), applicationRoots: [home.appendingPathComponent("Applications")])
    let sourceURL = appRoot.appendingPathComponent("index.js")
    let declaration = #"G.app.setPath(`userData`,process.env.CETUS_USER_DATA_PATH||(0,K.join)(G.app.getPath(`appData`),`Cetus`));"#
    try Data(#"{"main":"./index.js"}"#.utf8).write(to: appRoot.appendingPathComponent("package.json"))
    func writeSource(_ source: String) throws { try Data(source.utf8).write(to: sourceURL) }
    func matches() async -> [ApplicationAssociation] {
        let index = await scanner.associationIndex(for: [app], context: context)
        return index.associations[app.id, default: []].filter { $0.url.path == data.path }
    }
    try writeSource(declaration)
    let found = await matches()
    require(found.count == 1 && found.first?.risk == .review, "explicit custom data path must be found and opt-in")
    require(found.first?.ownershipBasis == .bundleDataDeclaration && found.first?.declarationSource == sourceURL.path, "retain typed declaration evidence and provenance")
    let analyzed = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(inventory: .init(applications: [app], coverage: .init(), scannedAt: Date()), context: context)
    let plan = analyzed.plans.first!
    let item = plan.items.first { $0.candidate.url.path == data.path }!
    require(item.containsUserData && item.candidate.risk == .review, "declared user data is selectable but never safe/default")
    require(UninstallBatchSelectionState().selectedItems(in: [plan]).isEmpty, "new data must not be auto-selected")
    let analyzer = ApplicationUninstallAnalyzer(scanner: scanner)
    let runningApp = app.withRunningState(true)
    let prepared = await analyzer.analyze(inventory: .init(applications: [runningApp], coverage: .init(), scannedAt: Date()), context: context)
    let runningDetails = prepared.analysis(for: app.id)!
    require(runningDetails.plan == nil && runningDetails.state == .running && prepared.plans.isEmpty,
            "prepared running plans must not enter executable inventory")
    let ready = runningDetails.withRunningState(false)
    require(ready.plan?.items.contains { $0.candidate.url.path == data.path && $0.containsUserData && $0.candidate.risk == .review } == true,
            "initial running scan must retain associated data without treating running state as permanent protection")
    require(ready.plan?.id == runningDetails.preparedPlan?.id
        && ready.withRunningState(true).withRunningState(false).plan == ready.plan,
            "quit and relaunch reuse exact plans and candidate IDs without discovery")
    let restoredPrepared = try JSONDecoder().decode(ApplicationUninstallInventory.self, from: JSONEncoder().encode(prepared))
    require(restoredPrepared.analysis(for: app.id)?.withRunningState(false).plan == ready.plan,
            "prepared plans survive report serialization")
    let whileRunning = await analyzer.analyzeStoppedApplications([app.id], in: [runningApp], context: context)
    require(whileRunning.isEmpty, "a running app must not receive a refreshed uninstall plan")
    try writeSource("// declaration temporarily absent: cached supplementation must not rediscover it")
    let afterQuit = await analyzer.analyzeStoppedApplications([app.id], in: [runningApp.withRunningState(false)], context: context, cachedIndex: prepared.associationIndex)
    require(afterQuit.first?.plan?.items.contains {
        $0.candidate.url.path == data.path && $0.containsUserData && $0.candidate.risk == .review
    } == true, "quitting an app must refresh its plan with opt-in associated data")
    try writeSource(declaration)
    try await ApplicationExecutionValidator(scanner: scanner).validate(item.candidate, context: context)
    let ordered = try PlanBuilder(protectionPolicy: .init(homeDirectory: home)).build(candidates: plan.items.map(\.candidate), selectedIDs: plan.selectableItemIDs)
    let declaredIndex = ordered.selectedItems.firstIndex { $0.candidate.id == item.id }
    let bundleIndex = ordered.selectedItems.firstIndex { $0.candidate.category == .application }
    require(declaredIndex != nil && bundleIndex != nil && declaredIndex! < bundleIndex!,
            "revalidate declared data before removing its source app")

    // A long minified identifier with no declaration used to make the unanchored
    // regular expression try every suffix, blocking uninstall revalidation.
    try writeSource("const " + String(repeating: "a", count: 200_000) + "=1;" + declaration)
    let parsingStarted = Date()
    let minified = await matches()
    require(minified.count == 1 && Date().timeIntervalSince(parsingStarted) < 3,
            "long minified identifiers must not stall declaration discovery")

    for source in ["/* " + declaration + " */", "// " + declaration, "const example = '" + declaration + "';", "const re = /" + declaration + "/;", declaration.replacingOccurrences(of: "`Cetus`", with: "`../Cetus`"), declaration.replacingOccurrences(of: "`Cetus`", with: "`Other`"), declaration.replacingOccurrences(of: "G.app.getPath", with: "other.getPath")] {
        try writeSource(source)
        let result = await matches()
        require(result.isEmpty, "comments, quoted examples, traversal, other roots and mismatched receivers must not grant ownership")
    }
    do {
        try await ApplicationExecutionValidator(scanner: scanner).validate(item.candidate, context: context)
        require(false, "removed declaration must invalidate an existing cleanup candidate")
    } catch ApplicationExecutionRejection.stillReferenced { }
    try writeSource(declaration + declaration.replacingOccurrences(of: "`Cetus`", with: "`Cetus Legacy`"))
    let ambiguous = await matches()
    require(ambiguous.isEmpty, "ambiguous multiple data roots must not become deletable")
    try writeSource(declaration)
    let copyURL = home.appendingPathComponent("Applications/Cetus Copy.app")
    try fm.copyItem(at: bundle, to: copyURL)
    let copy = InstalledApplication(bundleURL: copyURL, bundleIdentifier: app.bundleIdentifier, name: "Cetus Copy", version: "1", isRunning: false, isSystem: false)
    let shared = await scanner.associationIndex(for: [app, copy], context: context)
    require(shared.associations[app.id]?.first { $0.url.path == data.path }?.risk == .blocked, "another app copy protects the declared data directory")
    try fm.removeItem(at: copyURL)
    let elsewhere = root.appendingPathComponent("elsewhere")
    try fm.moveItem(at: data, to: elsewhere)
    try fm.createSymbolicLink(at: data, withDestinationURL: elsewhere)
    let linked = await matches()
    require(linked.isEmpty, "declared path must not follow symlinks into other data")
    try fm.removeItem(at: data)
    try fm.moveItem(at: elsewhere, to: data)

    let archiveURL = bundle.appendingPathComponent("Contents/Resources/app.asar")
    try makeDiscoveryAsar(package: Data(#"{"main":"index.js"}"#.utf8), source: Data(declaration.utf8)).write(to: archiveURL)
    let packed = await matches()
    require(packed.first?.risk == .review && packed.first?.declarationSource?.contains("app.asar/index.js") == true, "packed Electron declarations must be read without extracting/executing the app")
    try Data([4, 0, 0, 0, 255, 255, 255, 255]).write(to: archiveURL)
    let invalid = await matches()
    require(invalid.isEmpty, "corrupt/oversized ASAR headers must fail closed")

    let processes = "100 1 \(bundle.path)/Contents/MacOS/Cetus ADE\n101 100 /usr/bin/helper\n102 101 /usr/bin/node\n200 1 /Applications/Cetus ADE2.app/Contents/MacOS/Cetus\n"
    let owners = LocalApplicationFileObserver.processOwners(processes, applications: [app])
    require(Set(owners.keys) == [100, 101, 102], "track descendants without matching similarly named application paths")
    let opened = "p101\nf3\nn\(data.path)/state.db\np200\nf4\nn\(home.path)/Library/Application Support/Unrelated/file\np102\nn\(home.path)/Documents/important.txt\nn/System/Library/Fonts/font.ttf\n"
    let parsed = LocalApplicationFileObserver.parseOpenFiles(opened, owners: owners, home: home)
    require(parsed.paths[app.id]?.map(\.path) == [data.path], "open-file observations exclude unrelated processes, personal documents and system dependencies")
    require(LocalApplicationFileObserver.candidateDirectory(for: home.path + "/Library/Application Support/../private", home: home) == nil, "runtime paths cannot escape through traversal")
    let sampler = ApplicationRuntimeSampler(observer: DiscoveryFixtureObserver(directory: data), samples: 2, intervalNanoseconds: 0)
    let observation = await sampler.observe(applications: [app], home: home)
    require(observation[app.id]?.sampleCount == 2 && observation[app.id]?.directories == [data], "bounded sampling merges and deduplicates discoveries")
    let enriched = analyzed.observing(observation)
    require(enriched.plans == analyzed.plans && enriched.analyses.first?.runtimeObservation != nil, "runtime use alone must not change deletion eligibility or selection IDs")
    let task = Task { await sampler.observe(applications: [app], home: home) }
    task.cancel()
    let cancelled = await task.value
    require(cancelled[app.id]?.state == .cancelled, "cancelled sampling is never reported as a complete trace")
    // Verify the local observer against an actual file held open by this test
    // process. This never launches or closes a user's application.
    let held = try FileHandle(forReadingFrom: data.appendingPathComponent("state.db"))
    defer { try? held.close() }
    // Runtime configuration can select a product-specific name that neither
    // directory matching nor the bundle's recognized declaration establishes.
    // Keep that useful discovery as a clue without granting deletion rights.
    let runtimeOnly = home.appendingPathComponent("Library/Application Support/RuntimeChosenStore")
    try fm.createDirectory(at: runtimeOnly, withIntermediateDirectories: true)
    let runtimeFile = runtimeOnly.appendingPathComponent("state.db")
    try Data("runtime fixture".utf8).write(to: runtimeFile)
    let runtimeHeld = try FileHandle(forReadingFrom: runtimeFile)
    defer { try? runtimeHeld.close() }
    try makeDiscoveryAsar(package: Data(#"{"main":"index.js"}"#.utf8), source: Data(declaration.utf8)).write(to: archiveURL)
    let staticWithRuntimeDirectory = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(
        inventory: .init(applications: [app], coverage: .init(), scannedAt: Date()), context: context)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let selfApp = InstalledApplication(bundleURL: executable.deletingLastPathComponent(), bundleIdentifier: "com.contract.observer", name: "Observer fixture", version: nil, isRunning: true, isSystem: false)
    let actualObservation = await LocalApplicationFileObserver().capture(applications: [selfApp], home: home)
    require(actualObservation[selfApp.id]?.directories.contains { $0.path == data.path } == true,
        "real open-file snapshot must attribute the test process's held data file")
    require(actualObservation[selfApp.id]?.directories.contains { $0.path == runtimeOnly.path } == true
        && staticWithRuntimeDirectory.plans.flatMap(\.items).contains { $0.candidate.url.path == data.path }
        && !staticWithRuntimeDirectory.plans.flatMap(\.items).contains { $0.candidate.url.path == runtimeOnly.path },
        "runtime observation must supplement static discovery with an unrecognized custom directory, without adding it as deletable")

    let now = Date()
    require(!ApplicationObservationLifecycle.shouldRequestQuit(processID: 100, preexistingProcessIDs: [100], launchDate: now, observationStartedAt: now), "never quit an already-running instance")
    require(!ApplicationObservationLifecycle.shouldRequestQuit(processID: 101, preexistingProcessIDs: [], launchDate: nil, observationStartedAt: now), "unknown launch provenance cannot authorize quitting")
    require(!ApplicationObservationLifecycle.shouldRequestQuit(processID: 101, preexistingProcessIDs: [], launchDate: now.addingTimeInterval(-1), observationStartedAt: now), "a preexisting/raced launch must remain untouched")
    require(ApplicationObservationLifecycle.shouldRequestQuit(processID: 101, preexistingProcessIDs: [], launchDate: now.addingTimeInterval(1), observationStartedAt: now), "only a newly launched instance may receive a quit request")

    // Run a complete temporary-app uninstall through final ownership validation,
    // preserving the declaration source until all associated data is moved.
    try makeDiscoveryAsar(package: Data(#"{"main":"index.js"}"#.utf8), source: Data(declaration.utf8)).write(to: archiveURL)
    let fresh = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(inventory: .init(applications: [app], coverage: .init(), scannedAt: Date()), context: context)
    let freshItems = fresh.plans.flatMap(\.items).map(\.candidate)
    let removal = try PlanBuilder(protectionPolicy: .init(homeDirectory: home)).build(candidates: freshItems, selectedIDs: Set(freshItems.map(\.id)))
    let executor = CleanupExecutor(pathPolicy: PathPolicy(homeDirectory: home), quarantineRoot: root.appendingPathComponent("quarantine"),
        currentRuleVersion: removal.ruleVersion, validateCandidate: { candidate in
            try await ApplicationExecutionValidator(scanner: scanner).validate(candidate, context: context)
        })
    let receipt = await executor.execute(plan: removal)
    require(receipt.overallStatus == .completed && receipt.results.count == 2,
            "temporary app and declared data must finish uninstall with live ownership validation")
    require(!fm.fileExists(atPath: bundle.path) && !fm.fileExists(atPath: data.path),
            "successful uninstall must move both app body and associated data")
    print("PASS: application declaration discovery, ASAR bounds, ownership revalidation, sharing, symlinks, observation attribution and cancellation")
}

private struct DiscoveryFixtureObserver: ApplicationFileObserving {
    let directory: URL
    func capture(applications: [InstalledApplication], home: URL) async -> [URL: ApplicationRuntimeObservation] {
        Dictionary(uniqueKeysWithValues: applications.map { ($0.id, .init(directories: [directory], sampleCount: 1, state: .sampled)) })
    }
}

private func makeDiscoveryAsar(package: Data, source: Data) throws -> Data {
    let tree: [String: Any] = ["files": [
        "package.json": ["offset": "0", "size": package.count],
        "index.js": ["offset": String(package.count), "size": source.count]
    ]]
    let json = try JSONSerialization.data(withJSONObject: tree)
    let padding = (4 - json.count % 4) % 4
    let headerSize = 8 + json.count + padding
    var result = Data()
    for value in [4, headerSize, headerSize - 4, json.count] {
        var word = UInt32(value).littleEndian
        withUnsafeBytes(of: &word) { result.append(contentsOf: $0) }
    }
    result.append(json); result.append(Data(repeating: 0, count: padding))
    result.append(package); result.append(source)
    return result
}
