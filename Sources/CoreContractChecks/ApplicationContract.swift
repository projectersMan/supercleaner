import CleanerCore
import Foundation

func runApplicationContracts() async throws {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let appURL = URL(fileURLWithPath: "/Applications/Example.app", isDirectory: true)
    let application = InstalledApplication(bundleURL: appURL, bundleIdentifier: "com.example.app", name: "Example", version: "1.0", isRunning: false, isSystem: false)
    let contractFileSystem = ApplicationContractFileSystem(home: home, appURL: appURL)
    let context = ScanContext(homeDirectory: home, fileSystem: contractFileSystem)
    let associations = try await ApplicationScanner().associations(for: application, context: context)

    require(!associations.contains { $0.url.lastPathComponent == "com.example.app2" }, "bundle ID prefix collision must not match")
    require(associations.contains { $0.url.lastPathComponent == "com.example.app" }, "exact bundle ID should match")
    require(
        associations.first { $0.kind == .cache && $0.url.lastPathComponent == "com.example.app" }?.risk == .safe,
        "an inactive app's exactly-owned cache must be safe for default cleanup"
    )
    require(
        !associations.contains { $0.url.lastPathComponent == "ExampleCache" },
        "a bare product-name prefix must not claim an unrelated cache directory"
    )
    require(
        associations.first { $0.kind == .cache && $0.url.lastPathComponent == "Example" }?.risk == .review,
        "a cache matched only by the application display name must require review"
    )
    require(
        associations.contains { $0.kind == .applicationSupport && $0.url.lastPathComponent == "Example" },
        "an exact application display name must remain trusted ownership evidence"
    )
    let shortNameApplication = InstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/Exam.app"),
        bundleIdentifier: "com.vendor.exam",
        name: "Exam",
        version: "1.0",
        isRunning: false,
        isSystem: false
    )
    let shortNameFileSystem = ApplicationContractFileSystem(home: home, appURL: appURL)
    let shortNameIndex = await ApplicationScanner().associationIndex(
        for: [shortNameApplication],
        context: ScanContext(homeDirectory: home, fileSystem: shortNameFileSystem)
    )
    require(
        shortNameIndex.associations[shortNameApplication.id]?.isEmpty == true,
        "short product-name prefixes must not claim unrelated cache directories"
    )
    let runningApplication = InstalledApplication(
        bundleURL: appURL,
        bundleIdentifier: "com.example.app",
        name: "Example",
        version: "1.0",
        isRunning: true,
        isSystem: false
    )
    let runningFileSystem = ApplicationContractFileSystem(home: home, appURL: appURL)
    let runningContext = ScanContext(homeDirectory: home, fileSystem: runningFileSystem)
    let runningAssociations = try await ApplicationScanner().associations(for: runningApplication, context: runningContext)
    require(
        runningAssociations.first { $0.kind == .cache && $0.url.lastPathComponent == "com.example.app" }?.risk == .blocked,
        "a running app's cache must stay out of default cleanup"
    )

    let restrictedAssociationFileSystem = RestrictedAssociationContractFileSystem(
        home: home,
        appURL: appURL
    )
    let restrictedContext = ScanContext(
        homeDirectory: home,
        fileSystem: restrictedAssociationFileSystem
    )
    let restrictedIndex = await ApplicationScanner().associationIndex(
        for: [application],
        context: restrictedContext
    )
    require(
        restrictedIndex.associations[application.id]?.contains {
            $0.url.lastPathComponent == "com.example.app"
        } == true,
        "an unreadable association root must not discard matches from readable roots"
    )
    require(
        restrictedIndex.coverage.unavailableRoots == [
            home.appendingPathComponent("Library/Containers", isDirectory: true)
        ],
        "association coverage must identify the exact unreadable root"
    )
    require(restrictedIndex.ownershipGraph?.application(at: application.id)?.blocksAssociationDeletion == false, "an unrelated unavailable data root must not blanket-block independently verified associations")
    let restrictedInventory = await ApplicationUninstallAnalyzer().analyze(
        inventory: ApplicationInventory(
            applications: [application],
            coverage: .init(),
            scannedAt: restrictedContext.now
        ),
        context: restrictedContext
    )
    require(
        restrictedInventory.analysis(for: application.id)?.state == .complete,
        "a global association-root limitation must not mark every application row as individually limited"
    )
    let restrictedCoverage = restrictedInventory.moduleCoverage
    require(restrictedCoverage.applicationListState == .complete, "application discovery must report its own complete state")
    require(restrictedCoverage.associationAnalysisState == .limited, "association analysis must report its independent limited state")
    require(
        restrictedCoverage.summary == L10n.text("应用清单完成 · 关联分析 {0} 个位置受限", "1"),
        "module summary must distinguish discovery coverage from association coverage"
    )
    require(
        restrictedCoverage.limitations.first?.path == home.appendingPathComponent("Library/Containers", isDirectory: true),
        "module limitations must preserve the exact path for user inspection"
    )

    let plan = try await UninstallPlanner().planUninstall(application, context: context)
    let sensitive = plan.items.filter { $0.containsUserData || $0.isShared }
    require(sensitive.filter(\.isShared).allSatisfy { $0.candidate.risk == .blocked }, "shared content must remain blocked")
    let exactUserData = sensitive.filter {
        $0.containsUserData && !$0.isShared && $0.candidate.evidence.contains { $0.code == "ownership" && $0.summary.contains(L10n.text("完整 Bundle ID 边界")) }
    }
    require(!exactUserData.isEmpty, "the fixture must include a complete-Bundle-ID user-data association")
    require(exactUserData.allSatisfy { $0.candidate.risk.isSelectable }, "exclusively-owned user data must be selectable for explicit removal")
    let exactDisplayNameSupport = sensitive.filter {
        $0.containsUserData && !$0.isShared
            && $0.candidate.url.path.contains("/Library/Application Support/")
            && $0.candidate.evidence.contains { $0.code == "ownership" && $0.summary.contains(L10n.text("显示名精确匹配")) }
    }
    require(exactDisplayNameSupport.allSatisfy { $0.candidate.risk.isSelectable }, "exact app-specific Application Support folders should remain manually selectable")
    require(sensitive.filter { $0.containsUserData && !$0.isShared && !exactUserData.contains($0) && !exactDisplayNameSupport.contains($0) && !$0.candidate.evidence.contains { $0.code == "app-group-data" } }.allSatisfy { !$0.candidate.risk.isSelectable }, "ambiguous display-name-only user data must remain protected")
    require(plan.items.first { $0.candidate.url == appURL }?.candidate.risk == .review, "app bundle removal must require review")
    require(plan.items.first { $0.candidate.url == appURL }?.candidate.bytes == 900, "application bundle size must include nested contents")
    let selectableItems = plan.selectableItemIDs
    require(selectableItems.contains(plan.items.first { $0.candidate.url == appURL }!.id), "application bundle should be manually selectable for uninstall")
    require(selectableItems.allSatisfy { id in plan.items.first { $0.id == id }?.isShared == false }, "shared uninstall items must not be selectable")

    let deepSizeFileSystem = DeepApplicationSizeContractFileSystem(appURL: appURL, depth: 40, leafBytes: 4_096)
    let deepSizeContext = ScanContext(homeDirectory: home, fileSystem: deepSizeFileSystem)
    let completeDeepPlan = try await UninstallPlanner().buildPlan(
        application,
        associations: [],
        context: deepSizeContext
    )
    require(
        completeDeepPlan.plan.items.first?.candidate.bytes == 4_096,
        "default uninstall size measurement must traverse beyond the legacy recursive depth cap"
    )
    require(!completeDeepPlan.reachedSizeBudget, "default uninstall size measurement must not impose an entry budget")
    let completeDeepAnalysis = await ApplicationUninstallAnalyzer().analyze(
        inventory: ApplicationInventory(applications: [application], coverage: .init(), scannedAt: context.now),
        context: deepSizeContext
    )
    require(
        completeDeepAnalysis.analysis(for: application.id)?.state == .complete,
        "production uninstall analysis must remain complete without an implicit size cap"
    )
    require(
        completeDeepAnalysis.analysis(for: application.id)?.plan?.items.first?.candidate.bytes == 4_096,
        "production uninstall analysis must report the fully measured bundle size"
    )

    let limitedDeepPlan = try await UninstallPlanner().buildPlan(
        application,
        associations: [],
        context: deepSizeContext,
        maximumSizeEntries: 2
    )
    require(limitedDeepPlan.reachedSizeBudget, "an explicit diagnostic size cap must disclose incomplete measurement")

    let analyzedInventory = await ApplicationUninstallAnalyzer(maximumSizeEntries: 1).analyze(
        inventory: ApplicationInventory(
            applications: [application,
                InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Runner.app"), bundleIdentifier: "com.example.runner", name: "Runner", version: nil, isRunning: true, isSystem: false),
                InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/System.app"), bundleIdentifier: "com.apple.system", name: "System", version: nil, isRunning: false, isSystem: true),
            ],
            coverage: .init(),
            scannedAt: context.now
        ),
        context: context
    )
    require(analyzedInventory.analyses.count == 3, "scan-time uninstall analysis must cover every discovered application")
    require(analyzedInventory.analysis(for: application.id)?.plan != nil, "uninstall details must exist before a row is selected")
    require(analyzedInventory.analysis(for: application.id)?.state == .limited, "bounded size traversal must disclose limited analysis")
    let runningAnalysis = analyzedInventory.analysis(for: URL(fileURLWithPath: "/Applications/Runner.app"))
    let systemAnalysis = analyzedInventory.analysis(for: URL(fileURLWithPath: "/System/Applications/System.app"))
    require(runningAnalysis?.state == .protected, "running applications must be protected without traversal")
    require(systemAnalysis?.state == .protected, "system applications must be protected without traversal")
    require(runningAnalysis?.statusTitle == L10n.text("运行中 · 暂不可卸载"), "running protection must be explicitly temporary")
    require(systemAnalysis?.statusTitle == L10n.text("系统保护"), "system protection must not be confused with temporary running protection")
    var protectedDisclosure = ApplicationUninstallDisclosureState()
    protectedDisclosure.toggle()
    require(protectedDisclosure.isExpanded, "protected application rows must expand even without an uninstall plan")
    protectedDisclosure.toggle()
    require(!protectedDisclosure.isExpanded, "a second row disclosure action must collapse the application")
    require(
        ApplicationUninstallRowInteraction.action(clickCount: 1) == .selectAndToggleExpansion,
        "single-clicking an application row must toggle its disclosure"
    )
    require(
        ApplicationUninstallRowInteraction.action(clickCount: 2) == .selectAndToggleExpansion,
        "double-clicking any application row must toggle its disclosure"
    )
    let associationRootRequests = await contractFileSystem.associationRootRequests(home: home)
    require(associationRootRequests.values.allSatisfy { $0 == 3 }, "association roots should be enumerated once per explicit scan, not once per application")

    var batchSelection = UninstallBatchSelectionState()
    require(batchSelection.selectedItemIDs.isEmpty, "application uninstall scan must not imply uninstall selection")
    require(batchSelection.selectionState(for: plan) == .none, "unselected uninstall plans must report no selection")
    batchSelection.toggle(plan: plan)
    require(batchSelection.selectionState(for: plan) == .all, "manually toggling an application selects all eligible uninstall items")
    let firstSelectableItem = plan.items.first { selectableItems.contains($0.id) }!
    batchSelection.toggle(item: firstSelectableItem)
    require(batchSelection.selectionState(for: plan) == .partial, "toggling one child must expose a partial application selection")
    if let protectedItem = sensitive.first(where: \.isShared) {
        let beforeProtectedToggle = batchSelection.selectedItemIDs
        batchSelection.toggle(item: protectedItem)
        require(batchSelection.selectedItemIDs == beforeProtectedToggle, "protected uninstall items must ignore forced selection")
    }

    let secondApplication = InstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/Second.app"),
        bundleIdentifier: "com.example.second",
        name: "Second",
        version: "1",
        isRunning: false,
        isSystem: false
    )
    let secondCandidate = CleanupCandidate(
        url: secondApplication.bundleURL,
        displayName: secondApplication.name,
        category: .application,
        bytes: 400,
        risk: .review,
        evidence: [],
        identity: FileIdentity(device: 1, inode: 400, size: 400, modificationTime: 1, kind: .directory),
        source: .application,
        lastAccessDate: nil,
        isActive: false
    )
    let secondPlan = UninstallPlan(
        application: secondApplication,
        items: [UninstallItem(candidate: secondCandidate, containsUserData: false, isShared: false)]
    )
    batchSelection.toggle(plan: secondPlan)
    let batchSummary = batchSelection.summary(plans: [plan, secondPlan])
    let flattenedBatchItems = batchSelection.selectedItems(in: [plan, secondPlan])
    let flattenedBatchBytes = flattenedBatchItems.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
    require(batchSummary.applicationCount == 2, "batch uninstall summary must count every selected application")
    require(batchSummary.itemCount == flattenedBatchItems.count, "batch summary and flattened items must agree")
    require(batchSummary.bytes == flattenedBatchBytes, "batch summary bytes must match deduplicated selected items")

    let running = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/Runner.app"), bundleIdentifier: "com.example.runner", name: "Runner", version: nil, isRunning: true, isSystem: false)
    let system = InstalledApplication(bundleURL: URL(fileURLWithPath: "/System/Applications/System.app"), bundleIdentifier: "com.apple.system", name: "System", version: nil, isRunning: false, isSystem: true)
    let filter = ApplicationListFilter(query: "example", scope: .all)
    require(filter.apply(to: [system, running, application]).map(\.name) == ["Example", "Runner"], "application filter searches and sorts by name")
    require(ApplicationListFilter(query: "", scope: .uninstallable).apply(to: [application, running, system]) == [application], "uninstallable excludes running and system apps")
    require(ApplicationListFilter(query: "", scope: .running).apply(to: [application, running, system]) == [running], "running scope")
    require(ApplicationListFilter(query: "", scope: .systemProtected).apply(to: [application, running, system]) == [system], "system-protected scope")
    require(filter.reconciledSelection(current: system.id, in: [system, running, application]) == application.id, "filter moves selection to the first visible application")
    require(filter.reconciledSelection(current: running.id, in: [system, running, application]) == running.id, "filter preserves a visible selection")
    let filterSummary = filter.summary(for: [system, running, application])
    require(filterSummary.visibleCount == 2 && filterSummary.totalCount == 3, "application filter must expose visible and total counts")
    require(filterSummary.canClear, "an active application query must expose clear-filter affordance")
    require(!ApplicationListFilter(query: "", scope: .all).summary(for: [application]).canClear, "default application inventory must not show redundant clear-filter action")

    let alpha = InstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Users/tester/Applications/Alpha.app", isDirectory: true),
        bundleIdentifier: "com.example.alpha",
        name: "Alpha",
        version: nil,
        isRunning: false,
        isSystem: false
    )
    let zulu = InstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/Zulu.app", isDirectory: true),
        bundleIdentifier: "com.example.zulu",
        name: "Zulu",
        version: nil,
        isRunning: false,
        isSystem: false
    )
    let sortableApplications = [zulu, alpha, application]
    let selectedApplicationURLs: Set<URL> = [zulu.bundleURL.standardizedFileURL]
    require(
        ApplicationSortOrder.name.sorted(sortableApplications).map(\.name) == ["Alpha", "Example", "Zulu"],
        "default application ordering must sort by name"
    )
    require(
        ApplicationSortOrder.name.sorted(sortableApplications, selectedApplicationURLs: selectedApplicationURLs).map(\.name) == ["Alpha", "Example", "Zulu"],
        "checking an application must not reorder the default application list"
    )
    require(
        ApplicationSortOrder.selection.sorted(sortableApplications, selectedApplicationURLs: selectedApplicationURLs).map(\.name) == ["Zulu", "Alpha", "Example"],
        "selection ordering must move checked applications first only when explicitly requested"
    )
    require(
        ApplicationSortOrder.directory.sorted(sortableApplications, selectedApplicationURLs: selectedApplicationURLs).map(\.name) == ["Example", "Zulu", "Alpha"],
        "directory ordering must remain independent from checkbox state"
    )

    let discoveryRoot = URL(fileURLWithPath: "/Applications", isDirectory: true)
    let utilities = discoveryRoot.appendingPathComponent("Utilities", isDirectory: true)
    let nestedDirectory = utilities.appendingPathComponent("Developer", isDirectory: true)
    let topApp = discoveryRoot.appendingPathComponent("Top.app", isDirectory: true)
    let nestedApp = nestedDirectory.appendingPathComponent("Nested.app", isDirectory: true)
    let discoveryFileSystem = ApplicationDiscoveryContractFileSystem(
        childrenByPath: [
            discoveryRoot.path: [topApp, utilities],
            utilities.path: [nestedDirectory],
            nestedDirectory.path: [nestedApp],
            topApp.path: [topApp.appendingPathComponent("Contents")],
            nestedApp.path: [nestedApp.appendingPathComponent("Contents")],
        ],
        directoryPaths: [discoveryRoot.path, utilities.path, nestedDirectory.path, topApp.path, nestedApp.path],
        unreadablePaths: [home.appendingPathComponent("Applications").path]
    )
    let metadataProvider = ApplicationDiscoveryContractMetadataProvider(values: [
        topApp: ApplicationBundleMetadata(bundleIdentifier: "com.example.top", name: "Top", version: "1"),
        nestedApp: ApplicationBundleMetadata(bundleIdentifier: "com.example.nested", name: "Nested", version: "2"),
    ])
    let inventory = await ApplicationScanner(metadataProvider: metadataProvider).installedApplications(
        context: ScanContext(homeDirectory: home, fileSystem: discoveryFileSystem),
        maximumDepth: 4,
        maximumEntries: 100
    )
    require(inventory.applications.map(\.name) == ["Nested", "Top"], "application discovery must include nested app bundles")
    let requestedChildren = await discoveryFileSystem.requestedChildren()
    require(!requestedChildren.contains(topApp.path), "application bundles must be treated as atomic")
    require(!requestedChildren.contains(nestedApp.path), "nested application bundles must be treated as atomic")
    require(inventory.coverage.unavailableRoots.map(\.path).contains(home.appendingPathComponent("Applications").standardizedFileURL.path), "unreadable application roots must remain visible in coverage")
    require(inventory.coverage.budgetLimitedModules.isEmpty, "a finite entry cap must not report limited coverage when traversal completes below it")

    let entryLimitedInventory = await ApplicationScanner(metadataProvider: metadataProvider).installedApplications(
        context: ScanContext(homeDirectory: home, fileSystem: discoveryFileSystem),
        maximumEntries: 1
    )
    require(entryLimitedInventory.applications.map(\.name) == ["Top"], "an explicit diagnostic entry cap must remain available")
    require(entryLimitedInventory.coverage.budgetLimitedModules.contains(.applications), "an explicit entry cap that omits candidates must disclose limited coverage")

    let deepLevel1 = discoveryRoot.appendingPathComponent("One", isDirectory: true)
    let deepLevel2 = deepLevel1.appendingPathComponent("Two", isDirectory: true)
    let deepLevel3 = deepLevel2.appendingPathComponent("Three", isDirectory: true)
    let deepLevel4 = deepLevel3.appendingPathComponent("Four", isDirectory: true)
    let deepLevel5 = deepLevel4.appendingPathComponent("Five", isDirectory: true)
    let deepLevel6 = deepLevel5.appendingPathComponent("Six", isDirectory: true)
    let deeplyNestedApp = deepLevel6.appendingPathComponent("Deep.app", isDirectory: true)
    let deepDiscoveryFileSystem = ApplicationDiscoveryContractFileSystem(
        childrenByPath: [
            discoveryRoot.path: [deepLevel1],
            deepLevel1.path: [deepLevel2],
            deepLevel2.path: [deepLevel3],
            deepLevel3.path: [deepLevel4],
            deepLevel4.path: [deepLevel5],
            deepLevel5.path: [deepLevel6],
            deepLevel6.path: [deeplyNestedApp],
        ],
        directoryPaths: [
            discoveryRoot.path, deepLevel1.path, deepLevel2.path, deepLevel3.path,
            deepLevel4.path, deepLevel5.path, deepLevel6.path, deeplyNestedApp.path,
        ],
        unreadablePaths: []
    )
    let deepMetadataProvider = ApplicationDiscoveryContractMetadataProvider(values: [
        deeplyNestedApp: ApplicationBundleMetadata(bundleIdentifier: "com.example.deep", name: "Deep", version: "1"),
    ])
    let completeInventory = await ApplicationScanner(metadataProvider: deepMetadataProvider).installedApplications(
        context: ScanContext(homeDirectory: home, fileSystem: deepDiscoveryFileSystem)
    )
    require(completeInventory.applications.map(\.name) == ["Deep"], "default application discovery must not omit apps beyond an arbitrary depth")
    require(completeInventory.coverage.budgetLimitedModules.isEmpty, "uncapped application discovery must report complete coverage")

    let depthLimitedInventory = await ApplicationScanner(metadataProvider: deepMetadataProvider).installedApplications(
        context: ScanContext(homeDirectory: home, fileSystem: deepDiscoveryFileSystem),
        maximumDepth: 2
    )
    require(depthLimitedInventory.applications.isEmpty, "an explicit diagnostic depth cap must remain available")
    require(depthLimitedInventory.coverage.budgetLimitedModules.contains(.applications), "an explicit depth cap that truncates traversal must disclose limited coverage")
}

private actor DeepApplicationSizeContractFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]

    init(appURL: URL, depth: Int, leafBytes: UInt64) {
        var directories = [appURL]
        for level in 1...depth {
            directories.append(directories.last!.appendingPathComponent("Level\(level)", isDirectory: true))
        }
        let leaf = directories.last!.appendingPathComponent("payload.bin")
        var children: [String: [URL]] = [:]
        for (parent, child) in zip(directories, directories.dropFirst()) {
            children[parent.path] = [child]
        }
        children[directories.last!.path] = [leaf]
        childrenByPath = children

        var values = Dictionary(uniqueKeysWithValues: directories.map { directory in
            (directory.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64(directory.path.hashValue)), size: 0, modificationTime: 1, kind: .directory))
        })
        values[leaf.path] = FileIdentity(device: 1, inode: 9_999, size: leafBytes, modificationTime: 1, kind: .file)
        identities = values
    }

    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] { childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}

private struct ApplicationDiscoveryContractMetadataProvider: ApplicationMetadataProviding {
    let values: [URL: ApplicationBundleMetadata]
    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? { values[bundleURL.standardizedFileURL] }
}

private actor ApplicationDiscoveryContractFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let directoryPaths: Set<String>
    private let unreadablePaths: Set<String>
    private var childRequests: [String] = []

    init(childrenByPath: [String: [URL]], directoryPaths: Set<String>, unreadablePaths: Set<String>) {
        self.childrenByPath = childrenByPath
        self.directoryPaths = directoryPaths
        self.unreadablePaths = unreadablePaths
    }

    func identity(at url: URL) throws -> FileIdentity {
        FileIdentity(device: 1, inode: UInt64(bitPattern: Int64(url.path.hashValue)), size: 1, modificationTime: 1, kind: directoryPaths.contains(url.path) ? .directory : .file)
    }
    func children(of url: URL) -> [URL] { childRequests.append(url.path); return childrenByPath[url.path, default: []] }
    func isReadable(_ url: URL) -> Bool { !unreadablePaths.contains(url.path) }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { childrenByPath[url.path] != nil || unreadablePaths.contains(url.path) }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
    func requestedChildren() -> [String] { childRequests }
}

private actor ApplicationContractFileSystem: FileSystemAccess {
    private let childrenByPath: [String: [URL]]
    private let identities: [String: FileIdentity]
    private var requestedChildren: [String: Int] = [:]
    init(home: URL, appURL: URL) {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let groups = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let nestedExecutable = appURL.appendingPathComponent("Contents/MacOS/Example")
        let urls = [appURL, caches.appendingPathComponent("com.example.app"), caches.appendingPathComponent("com.example.app2"), caches.appendingPathComponent("ExampleCache"), caches.appendingPathComponent("Example"), support.appendingPathComponent("Example"), groups.appendingPathComponent("group.com.example.app"), support.appendingPathComponent("com.example.app")]
        childrenByPath = [appURL.path: [nestedExecutable], caches.path: Array(urls[1...4]), support.path: [urls[5], urls[7]], groups.path: [urls[6]]]
        var identityPairs = urls.map { ($0.path, FileIdentity(device: 1, inode: UInt64(bitPattern: Int64($0.path.hashValue)), size: 100, modificationTime: 1, kind: .directory)) }
        identityPairs.append((nestedExecutable.path, FileIdentity(device: 1, inode: 99, size: 900, modificationTime: 1, kind: .file)))
        identities = Dictionary(uniqueKeysWithValues: identityPairs)
    }
    func identity(at url: URL) throws -> FileIdentity { identities[url.path]! }
    func children(of url: URL) -> [URL] {
        requestedChildren[url.path, default: 0] += 1
        return childrenByPath[url.path, default: []]
    }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil || childrenByPath[url.path] != nil }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
    func associationRootRequests(home: URL) -> [String: Int] {
        let roots = [
            "Library/Caches", "Library/Application Support", "Library/Preferences",
            "Library/Saved Application State", "Library/LaunchAgents", "Library/Containers",
            "Library/Group Containers",
        ].map { home.appendingPathComponent($0, isDirectory: true).path }
        return Dictionary(uniqueKeysWithValues: roots.compactMap { path in
            requestedChildren[path].map { (path, $0) }
        })
    }
}

private actor RestrictedAssociationContractFileSystem: FileSystemAccess {
    private let appURL: URL
    private let cacheRoot: URL
    private let cacheEntry: URL
    private let restrictedRoot: URL

    init(home: URL, appURL: URL) {
        self.appURL = appURL
        cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        cacheEntry = cacheRoot.appendingPathComponent("com.example.app", isDirectory: true)
        restrictedRoot = home.appendingPathComponent("Library/Containers", isDirectory: true)
    }

    func identity(at url: URL) throws -> FileIdentity {
        FileIdentity(
            device: 1,
            inode: UInt64(bitPattern: Int64(url.path.hashValue)),
            size: url == cacheEntry ? 20 : 100,
            modificationTime: 1,
            kind: .directory
        )
    }

    func children(of url: URL) throws -> [URL] {
        if url == restrictedRoot { throw FileSystemError.missing(url) }
        if url == cacheRoot { return [cacheEntry] }
        return []
    }

    func isReadable(_ url: URL) -> Bool { url != restrictedRoot }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool {
        [appURL, cacheRoot, cacheEntry, restrictedRoot].contains(url)
    }
    func move(_ source: URL, to destination: URL) {}
    func createDirectory(_ url: URL) {}
    func removeEmptyDirectory(_ url: URL) {}
    func trash(_ url: URL) -> URL { url }
}
