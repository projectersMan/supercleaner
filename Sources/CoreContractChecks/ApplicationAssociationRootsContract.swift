import CleanerCore
import Foundation

private struct AssociationRootsNoInstallations: ApplicationInstallationInspecting {
    func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary) {
        ([:], .init())
    }
}

private struct AssociationRootsContractFailure: Error, CustomStringConvertible {
    let description: String
}

/// These tests inspect and modify only one uniquely named temporary fixture.
/// No installed application, user Library or system directory is changed.
func runApplicationAssociationRootsContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("ApplicationRoots-" + UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    let applicationRoot = home.appendingPathComponent("Applications")
    let identifier = "com.rawtherapee.rawtherapee5"

    func directory(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func write(_ url: URL, _ text: String) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func application(_ name: String, _ bundleID: String, groups: [String] = [], running: Bool = false) throws -> InstalledApplication {
        let url = try directory("home/Applications/" + name + ".app")
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleName": name,
            "CFBundleExecutable": name, "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
        ]
        let contents = url.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return InstalledApplication(bundleURL: url, bundleIdentifier: bundleID, name: name,
            version: "1", isRunning: running, isSystem: false, applicationGroups: groups)
    }
    func scanner(additionalRoots: [ApplicationAssociationRoot] = [], temporaryDirectories: [URL] = [], maximumEntries: Int = 20_000) -> ApplicationScanner {
        ApplicationScanner(ownershipBuilder: .init(installationInspector: AssociationRootsNoInstallations(),
            configurationFiles: [], additionalAssociationRoots: additionalRoots,
            maximumEntries: maximumEntries, includeSystemRoots: false, userTemporaryDirectories: temporaryDirectories),
            applicationRoots: [applicationRoot], diagnosticScanner: .init(includeSystemRoots: false))
    }
    let context = ScanContext(homeDirectory: home)
    let app = try application("RawTherapee", identifier)
    let container = try directory("home/Library/Containers/" + identifier)
    let containerPayload = container.appendingPathComponent("Data/settings")
    try write(containerPayload, "retain this fixture payload through recovery")
    let scripts = try directory("home/Library/Application Scripts/" + identifier)
    let isolatedScanner = scanner()

    func analyze(_ source: ApplicationScanner, applications: [InstalledApplication]) async -> ApplicationUninstallInventory {
        await ApplicationUninstallAnalyzer(scanner: source).analyze(
            inventory: .init(applications: applications, coverage: .init(), scannedAt: Date()), context: context)
    }
    func pathKey(_ url: URL) -> String { url.standardizedFileURL.path }
    func requiredPlan(_ inventory: ApplicationUninstallInventory, owner: InstalledApplication) throws -> UninstallPlan {
        guard let plan = inventory.analysis(for: owner.id)?.plan else {
            throw AssociationRootsContractFailure(description: "Missing uninstall plan for fixture application " + owner.id.path)
        }
        return plan
    }
    func requiredItem(_ plan: UninstallPlan, at path: URL) throws -> UninstallItem {
        guard let item = plan.items.first(where: { pathKey($0.candidate.url) == pathKey(path) }) else {
            let found = plan.items.map { pathKey($0.candidate.url) + " [" + $0.candidate.risk.rawValue + "]" }.joined(separator: ", ")
            throw AssociationRootsContractFailure(description: "Missing fixture uninstall item " + pathKey(path) + "; actual items: " + found)
        }
        return item
    }
    func selectable(_ inventory: ApplicationUninstallInventory, owner: InstalledApplication, path: URL) -> Bool {
        guard let plan = inventory.analysis(for: owner.id)?.plan,
              let item = plan.items.first(where: { pathKey($0.candidate.url) == pathKey(path) }) else { return false }
        return plan.selectableItemIDs.contains(item.id)
    }
    let validateExpected: @Sendable (CleanupCandidate, String) async throws -> Void = { candidate, stage in
        do {
            try await ApplicationExecutionValidator(scanner: isolatedScanner).validate(candidate, context: context)
        } catch {
            let inventory = await isolatedScanner.installedApplications(context: context, maximumDepth: 12, maximumEntries: 30_000)
            let diagnosticIndex = await isolatedScanner.associationIndex(for: inventory.applications, context: context, resourceURL: candidate.url)
            let fullIndex = await isolatedScanner.associationIndex(for: inventory.applications, context: context)
            let applications = inventory.applications.map { $0.bundleIdentifier + " / " + $0.name + " / " + $0.id.path }.joined(separator: " | ")
            let associations = diagnosticIndex.associations.flatMap { owner, values in
                values.map { owner.path + " -> " + $0.url.path + " [" + $0.risk.rawValue + ", shared=" + String($0.isShared) + "]" }
            }.sorted().joined(separator: " | ")
            let fullAssociations = fullIndex.associations.flatMap { owner, values in
                values.map { owner.path + " -> " + $0.url.path + " [" + $0.risk.rawValue + "]" }
            }.sorted().joined(separator: " | ")
            let vendors = (try? await context.fileSystem.children(of: home.appendingPathComponent("Library/Caches"))) ?? []
            let vendorPaths = vendors.map { "raw=" + $0.absoluteString + " path=" + $0.path + " resolved=" + $0.resolvingSymlinksInPath().path }.joined(separator: " | ")
            throw AssociationRootsContractFailure(description: "Expected successful ownership revalidation at " + stage
                + " for " + candidate.url.standardizedFileURL.path + "; rejected with " + String(describing: error)
                + "; installed fixture metadata: " + applications + "; targeted associations: " + associations
                + "; unavailable roots: " + diagnosticIndex.coverage.unavailableRoots.map(\.path).joined(separator: ",")
                + "; scanned roots: " + diagnosticIndex.coverage.scannedRoots.map(\.path).joined(separator: ",")
                + "; full associations: " + fullAssociations + "; vendor roots: " + vendorPaths
                + "; target raw=" + candidate.url.absoluteString + " resolved=" + candidate.url.resolvingSymlinksInPath().path)
        }
    }

    let initial = await analyze(isolatedScanner, applications: [app])
    guard let initialPlan = initial.analysis(for: app.id)?.plan else {
        require(false, "RawTherapee fixture must have an uninstall plan")
        return
    }
    require(initialPlan.items.count == 3 && initialPlan.selectableItemIDs.count == 3,
            "app, container and empty Application Scripts directory must be three selectable uninstall items")
    let scriptsItem = try requiredItem(initialPlan, at: scripts)
    require(scriptsItem.containsUserData && scriptsItem.candidate.bytes == 0 && scriptsItem.candidate.risk == .review,
            "empty script directories remain visible, explicitly selectable user data rather than auto-cleanup")
    require(UninstallBatchSelectionState().selectedItems(in: [initialPlan]).isEmpty,
            "new association roots must never opt applications or user scripts into default cleanup")
    var explicitSelection = UninstallBatchSelectionState()
    explicitSelection.toggle(plan: initialPlan)
    require(explicitSelection.selectedItems(in: [initialPlan]).count == 3,
            "explicit whole-app selection includes the independently verified empty scripts directory")
    try await validateExpected(scriptsItem.candidate, "initial Application Scripts discovery")

    let targetedScripts = await isolatedScanner.associationIndex(for: [app], context: context, resourceURL: scripts)
    let targetedScriptAssociations = targetedScripts.associations[app.id, default: []]
    require(targetedScriptAssociations.count == 1
            && targetedScriptAssociations.first.map { pathKey($0.url) == pathKey(scripts) && $0.risk.isSelectable } == true,
            "resourceURL revalidation must rediscover only the selected scripts directory, independent of URL trailing slash spelling")
    let lowBudgetScanner = scanner(maximumEntries: 1)
    let lowBudget = await lowBudgetScanner.associationIndex(for: [app], context: context, resourceURL: scripts)
    require(lowBudget.coverage.budgetLimitedModules.contains(.applications)
            && lowBudget.associations[app.id, default: []].isEmpty
            && lowBudget.ownershipGraph?.application(at: app.id)?.ownershipVerified == false,
            "a budget exhausted before root ownership discovery must expose incomplete coverage without granting new deletion rights")
    do {
        try await ApplicationExecutionValidator(scanner: lowBudgetScanner).validate(scriptsItem.candidate, context: context)
        require(false, "an old preview cannot bypass execution revalidation whose ownership budget is exhausted")
    } catch ApplicationExecutionRejection.stillReferenced { }
    let cancelledDiscovery = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await isolatedScanner.associationIndex(for: [app], context: context, resourceURL: scripts)
    }
    let cancelledIndex = await cancelledDiscovery.value
    require(cancelledIndex.coverage.budgetLimitedModules.contains(.applications)
            && cancelledIndex.associations[app.id, default: []].isEmpty
            && cancelledIndex.ownershipGraph?.application(at: app.id)?.ownershipVerified == false,
            "cancelled discovery must not manufacture selectable ownership from an incomplete root scan")

    let registered = ApplicationAssociationPathRegistry.roots(home: home, userTemporaryDirectories: [])
    let registeredPaths = Set(registered.map { $0.url.standardizedFileURL.path })
    for relative in ["Library/Application Scripts", "Library/Containers", "Library/Preferences/ByHost", "Library/Cookies"] {
        require(registeredPaths.contains(home.appendingPathComponent(relative).path),
                "the unified association registry must include " + relative)
    }
    for leaf in ["Application Support", "Caches", "Preferences", "LaunchAgents", "LaunchDaemons", "StartupItems",
                 "Application Support/CrashReporter", "Logs/DiagnosticReports", "Logs/CrashReporter"] {
        require(registeredPaths.contains(home.appendingPathComponent("Library/" + leaf).path),
                "the XApp user Library search boundary must be represented: " + leaf)
        require(registeredPaths.contains(URL(fileURLWithPath: "/Library/" + leaf).path),
                "the XApp global Library search boundary must be represented: " + leaf)
    }
    for leaf in ["Saved Application State", "Containers", "Group Containers", "HTTPStorages", "Application Scripts", "WebKit",
                 "Preferences/ByHost", "Cookies", "Autosave Information", "Scripts"] {
        require(registeredPaths.contains(home.appendingPathComponent("Library/" + leaf).path),
                "user application association search coverage must include " + leaf)
    }
    for leaf in ["Preferences/ByHost", "QuickLook", "PreferencePanes", "Services", "Internet Plug-Ins", "Input Methods",
                 "ScriptingAdditions", "Screen Savers", "Audio/Plug-Ins/Components", "Audio/Plug-Ins/VST",
                 "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL", "Spotlight"] {
        for boundary in [home.appendingPathComponent("Library/" + leaf), URL(fileURLWithPath: "/Library/" + leaf)] {
            require(registeredPaths.contains(boundary.path),
                    "the shared registry must retain additional supported preferences/plugin boundaries: " + boundary.path)
        }
    }
    for path in ["/Applications/Utilities", "/Library/Receipts", "/private/var/db/receipts"] {
        require(registered.contains { pathKey($0.url) == pathKey(URL(fileURLWithPath: path)) && $0.isSystem && $0.removalPolicy == .referenceOnly },
                "global utilities and installer receipts remain discovery-only boundaries: " + path)
    }
    require(registeredPaths.count == registered.count,
            "the directory registry must not enumerate duplicate physical search definitions")
    require(registered.filter(\.isSystem).allSatisfy { $0.removalPolicy == .referenceOnly },
            "system association roots must be reference-only even if their files are writable")
    require(registered.contains { $0.kind == .installationReceipt && $0.removalPolicy == .referenceOnly },
            "installation receipts are registered as evidence, never as recoverable app-owned data")

    let byHost = try directory("home/Library/Preferences/ByHost")
    let hostID = "A5D6E7F8-1234-4ABC-89DE-1234567890AB"
    let hostPreference = byHost.appendingPathComponent(identifier + "." + hostID + ".plist")
    try write(hostPreference, "fixture preferences")
    let invalidHostNames = [identifier + ".invalid-uuid.plist", identifier + "2." + hostID + ".plist",
                            identifier + ".helper." + hostID + ".plist", identifier + "." + hostID + ".plist.backup"]
    for name in invalidHostNames { try write(byHost.appendingPathComponent(name), "unrelated preferences") }
    let cookieRoot = try directory("home/Library/Cookies")
    let cookies = cookieRoot.appendingPathComponent(identifier + ".binarycookies")
    try write(cookies, "app-specific fixture cookies")
    let sharedCookies = cookieRoot.appendingPathComponent("Cookies.binarycookies")
    try write(sharedCookies, "shared fixture cookies must remain")
    let unrelatedCookies = cookieRoot.appendingPathComponent(identifier + "2.binarycookies")
    try write(unrelatedCookies, "other app fixture cookies")
    let scriptPrefix = try directory("home/Library/Application Scripts/" + identifier + ".helper")
    let scriptDisplayName = try directory("home/Library/Application Scripts/RawTherapee")
    let mixed = await analyze(isolatedScanner, applications: [app])
    require(selectable(mixed, owner: app, path: hostPreference) && selectable(mixed, owner: app, path: cookies),
            "exact app-owned ByHost preferences and cookies must be manually selectable")
    for path in [byHost, cookieRoot, scripts.deletingLastPathComponent(), scriptPrefix, scriptDisplayName, sharedCookies, unrelatedCookies]
        + invalidHostNames.map({ byHost.appendingPathComponent($0) }) {
        require(!selectable(mixed, owner: app, path: path),
                "parent directories, product names and identifier/UUID prefix collisions must not grant ownership: " + path.lastPathComponent)
    }

    let temporaryRoot = try directory("home/current-user-temporary")
    let appTemporary = try directory("home/current-user-temporary/" + identifier)
    let otherTemporary = try directory("home/current-user-temporary/" + identifier + "2")
    let anotherUsersTemporary = try directory("another-user-temporary/" + identifier)
    try write(appTemporary.appendingPathComponent("scratch"), "temporary fixture")
    let temporaryScanner = scanner(temporaryDirectories: [temporaryRoot])
    let temporaryInventory = await analyze(temporaryScanner, applications: [app])
    require(selectable(temporaryInventory, owner: app, path: appTemporary),
            "only a registered current-user temporary root's exact app child may become selectable")
    for path in [temporaryRoot, otherTemporary, anotherUsersTemporary] {
        require(!selectable(temporaryInventory, owner: app, path: path),
                "temporary root parents, similar identifiers and other users' directories are never claimed")
    }
    let defaultTemporaryInventory = await analyze(isolatedScanner, applications: [app])
    require(!selectable(defaultTemporaryInventory, owner: app, path: appTemporary),
            "unregistered temporary roots cannot acquire deletion eligibility")

    let chrome = try application("Google Chrome", "com.google.Chrome")
    let vendorDirectory = try directory("home/Library/Caches/Google")
    let chromeCache = try directory("home/Library/Caches/Google/Chrome")
    let anotherVendorProduct = try directory("home/Library/Caches/Google/Other Product")
    try write(chromeCache.appendingPathComponent("cache-entry"), "Chrome-only fixture cache")
    try write(anotherVendorProduct.appendingPathComponent("sentinel"), "another vendor product")
    let vendorInventory = await analyze(isolatedScanner, applications: [chrome])
    require(selectable(vendorInventory, owner: chrome, path: chromeCache),
            "one-level vendor discovery must attribute Google/Chrome to Google Chrome")
    require(!selectable(vendorInventory, owner: chrome, path: vendorDirectory)
            && !selectable(vendorInventory, owner: chrome, path: anotherVendorProduct),
            "vendor parents and sibling products must never join a product's uninstall selection")
    let vendorPlan = try requiredPlan(vendorInventory, owner: chrome)
    let vendorCandidate = try requiredItem(vendorPlan, at: chromeCache).candidate
    try await validateExpected(vendorCandidate, "one-level vendor cache discovery")

    let shimIdentifier = "com.google.Chrome.app.contract-shim"
    let shimCache = try directory("home/Library/Caches/" + shimIdentifier)
    try write(shimCache.appendingPathComponent("state"), "independent app-shim fixture state")
    let browserOnly = await analyze(isolatedScanner, applications: [chrome])
    require(!selectable(browserOnly, owner: chrome, path: shimCache),
            "the browser's identifier prefix cannot claim an independently named Chrome app-shim cache")
    let shimApp = try application("Independent Chrome Shim", shimIdentifier)
    let browserAndShim = await analyze(isolatedScanner, applications: [chrome, shimApp])
    require(!selectable(browserAndShim, owner: chrome, path: shimCache)
            && selectable(browserAndShim, owner: shimApp, path: shimCache),
            "Chrome app-shim caches belong only to their exact installed app identity, never the browser")

    let legacyPreferences = [
        ("Logi Options Fixture", "com.logi.optionsplus", "com.logi.cp-dev-mgr"),
        ("iStat Menus Fixture", "com.bjango.istatmenus", "com.bjango.istatmenus6.extras"),
    ]
    for (name, productIdentifier, legacyIdentifier) in legacyPreferences {
        let product = try application(name, productIdentifier)
        let preference = home.appendingPathComponent("Library/Preferences/" + legacyIdentifier + ".plist")
        try write(preference, "legacy compatibility clue, not independent ownership proof")
        let hintIndex = await isolatedScanner.associationIndex(for: [product], context: context, resourceURL: preference)
        let clue = hintIndex.associations[product.id, default: []].first { pathKey($0.url) == pathKey(preference) }
        require(clue?.ownershipBasis == .compatibilityHint && clue?.removalPolicy == .referenceOnly
                && clue?.risk == .blocked,
                "a non-namespace legacy preference must remain a visible reference-only compatibility clue: " + legacyIdentifier)
        let productOnly = await analyze(isolatedScanner, applications: [product])
        let productPlan = try requiredPlan(productOnly, owner: product)
        let clueItem = try requiredItem(productPlan, at: preference)
        require(!productPlan.selectableItemIDs.contains(clueItem.id),
                "discovering a legacy preference must not silently authorize its deletion")
        let actualOwner = try application("Legacy Preference Owner " + legacyIdentifier, legacyIdentifier)
        let withActualOwner = await analyze(isolatedScanner, applications: [product, actualOwner])
        require(!selectable(withActualOwner, owner: product, path: preference),
                "a compatibility table cannot let a parent product remove another installed app's exact preference domain")
        do {
            try await ApplicationExecutionValidator(scanner: isolatedScanner).validate(
                clueItem.candidate.replacing(risk: .review, evidence: clueItem.candidate.evidence), context: context)
            require(false, "forged selectable risk cannot override a legacy preference's reference-only compatibility policy")
        } catch ApplicationExecutionRejection.stillReferenced { }
    }

    let embeddedIdentifier = "com.contract.embedded-product"
    let embeddedParent = try application("Embedded Product", embeddedIdentifier)
    func embeddedBundle(at url: URL, identifier childIdentifier: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": childIdentifier, "CFBundleName": url.deletingPathExtension().lastPathComponent,
                                   "CFBundleExecutable": "fixture", "CFBundleVersion": "1", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
    let embeddedChildren = [
        ("XPCServices/ContractWorker.xpc", ".worker"),
        ("PlugIns/ContractPlugin.appex", ".plugin"),
        ("Applications/ContractApplication.app", ".application"),
        ("Library/LoginItems/ContractLogin.app", ".login"),
        ("Library/LaunchServices/ContractService.app", ".service"),
        ("Helpers/ContractHelper.app", ".helper"),
    ]
    for (relative, suffix) in embeddedChildren {
        try embeddedBundle(at: embeddedParent.id.appendingPathComponent("Contents/" + relative), identifier: embeddedIdentifier + suffix)
    }
    let foreignIdentifier = "org.foreign.unrelated-product"
    try embeddedBundle(at: embeddedParent.id.appendingPathComponent("Contents/Helpers/Foreign.app"), identifier: foreignIdentifier)
    let similarIdentifier = embeddedIdentifier + "Extra.helper"
    try embeddedBundle(at: embeddedParent.id.appendingPathComponent("Contents/Helpers/Similar.app"), identifier: similarIdentifier)
    let escapedIdentifier = embeddedIdentifier + ".escaped"
    let escapedBundle = root.appendingPathComponent("outside-embedded/External.app")
    try embeddedBundle(at: escapedBundle, identifier: escapedIdentifier)
    try manager.createSymbolicLink(at: embeddedParent.id.appendingPathComponent("Contents/Helpers/Escaped.app"), withDestinationURL: escapedBundle)
    guard let metadata = BundleApplicationMetadataProvider().metadata(for: embeddedParent.id) else {
        require(false, "the embedded-bundle fixture's real Info.plist metadata must be readable")
        return
    }
    let discoveredChildren = Set(metadata.associatedBundleIdentifiers ?? [])
    require(Set(embeddedChildren.map { embeddedIdentifier + $0.1 }).isSubset(of: discoveredChildren),
            "bounded bundle metadata discovery must inspect all supported helper/extension directories")
    require(!discoveredChildren.contains(foreignIdentifier) && !discoveredChildren.contains(similarIdentifier)
            && !discoveredChildren.contains(escapedIdentifier),
            "unsigned foreign namespaces, identifier prefixes and external symlink bundles cannot grant ownership")
    let embeddedApp = InstalledApplication(bundleURL: embeddedParent.id, bundleIdentifier: metadata.bundleIdentifier,
        name: metadata.name, version: metadata.version, isRunning: false, isSystem: false,
        teamIdentifier: metadata.teamIdentifier, applicationGroups: metadata.applicationGroups,
        associatedBundleIdentifiers: metadata.associatedBundleIdentifiers)
    let helperIdentifier = embeddedIdentifier + ".helper"
    let helperContainer = try directory("home/Library/Containers/" + helperIdentifier)
    let helperPreference = home.appendingPathComponent("Library/Preferences/" + helperIdentifier + ".plist")
    try write(helperPreference, "helper fixture preferences")
    let foreignContainer = try directory("home/Library/Containers/" + foreignIdentifier)
    let similarContainer = try directory("home/Library/Containers/" + similarIdentifier)
    let escapedContainer = try directory("home/Library/Containers/" + escapedIdentifier)
    let embeddedInventory = await analyze(isolatedScanner, applications: [embeddedApp])
    require(selectable(embeddedInventory, owner: embeddedApp, path: helperContainer)
            && selectable(embeddedInventory, owner: embeddedApp, path: helperPreference),
            "validated embedded bundle identifiers must discover their own containers and preferences")
    for path in [foreignContainer, similarContainer, escapedContainer] {
        require(!selectable(embeddedInventory, owner: embeddedApp, path: path),
                "rejected embedded identifiers cannot grant ownership of similarly named user data")
    }
    let helperPlan = try requiredPlan(embeddedInventory, owner: embeddedApp)
    for path in [helperContainer, helperPreference] {
        let candidate = try requiredItem(helperPlan, at: path).candidate
        try await validateExpected(candidate, "embedded helper " + path.lastPathComponent)
    }

    let copy = try application("RawTherapee Copy", identifier)
    let withCopy = await analyze(isolatedScanner, applications: [app, copy])
    require(!selectable(withCopy, owner: app, path: scripts) && !selectable(withCopy, owner: app, path: container),
            "another installed copy protects the app's scripts and container")
    let targetedShared = await isolatedScanner.associationIndex(for: [app, copy], context: context, resourceURL: scripts)
    let targetedSharedAssociation = targetedShared.associations[app.id, default: []].first { pathKey($0.url) == pathKey(scripts) }
    require(targetedSharedAssociation?.risk == .blocked && targetedSharedAssociation?.ownerBundleURLs?.count == 2,
            "resourceURL narrowing must retain every installed copy's shared-ownership protection")
    do {
        try await ApplicationExecutionValidator(scanner: isolatedScanner).validate(scriptsItem.candidate, context: context)
        require(false, "a newly installed copy must invalidate a formerly selectable script directory")
    } catch ApplicationExecutionRejection.stillReferenced { }
    try manager.removeItem(at: copy.id)
    try await validateExpected(scriptsItem.candidate, "after removing the duplicate app fixture")

    let groupID = "TEAM.association-root-contract"
    let groupedApp = InstalledApplication(bundleURL: app.id, bundleIdentifier: identifier, name: app.name,
        version: "1", isRunning: false, isSystem: false, applicationGroups: [groupID])
    let secondOwner = try application("Other Product", "com.contract.other-product", groups: [groupID])
    let groupScripts = try directory("home/Library/Application Scripts/" + groupID)
    let exclusiveGroup = await analyze(isolatedScanner, applications: [groupedApp])
    require(selectable(exclusiveGroup, owner: groupedApp, path: groupScripts),
            "an explicitly declared script group with one installed owner remains manually reviewable")
    let sharedGroup = await analyze(isolatedScanner, applications: [groupedApp, secondOwner])
    require(!selectable(sharedGroup, owner: groupedApp, path: groupScripts),
            "multiple declared script-group owners must keep the shared directory protected")
    try manager.removeItem(at: secondOwner.id)

    let referenceRoot = try directory("home/reference-only-plugins")
    let plugin = try directory("home/reference-only-plugins/" + identifier)
    let systemRoot = try directory("fixture-system/Scripts")
    let systemScript = try directory("fixture-system/Scripts/" + identifier)
    let protectedScanner = scanner(additionalRoots: [
        .init(url: referenceRoot, kind: .plugin, containsUserData: true, removalPolicy: .referenceOnly),
        .init(url: systemRoot, kind: .applicationScripts, containsUserData: true, isSystem: true, removalPolicy: .referenceOnly),
    ])
    let protectedIndex = await protectedScanner.associationIndex(for: [app], context: context)
    for path in [plugin, systemScript] {
        let association = protectedIndex.associations[app.id]?.first { pathKey($0.url) == pathKey(path) }
        require(association?.removalPolicy == .referenceOnly && association?.risk == .blocked,
                "strong Bundle ID evidence must never promote reference-only associations during graph aggregation")
    }
    let protectedInventory = await analyze(protectedScanner, applications: [app])
    require(!selectable(protectedInventory, owner: app, path: plugin)
            && !selectable(protectedInventory, owner: app, path: systemScript),
            "reference-only and system items must be excluded from selectable uninstall counts")
    let protectedPlan = try requiredPlan(protectedInventory, owner: app)
    let pluginCandidate = try requiredItem(protectedPlan, at: plugin).candidate
    do {
        try await ApplicationExecutionValidator(scanner: protectedScanner).validate(
            pluginCandidate.replacing(risk: .review, evidence: pluginCandidate.evidence), context: context)
        require(false, "forged or stale preview risk must not override the current reference-only root policy")
    } catch ApplicationExecutionRejection.stillReferenced { }

    let retainedScripts = root.appendingPathComponent("retained-scripts")
    let outside = try directory("outside-script-target")
    try write(outside.appendingPathComponent("sentinel"), "must stay intact")
    try manager.moveItem(at: scripts, to: retainedScripts)
    try manager.createSymbolicLink(at: scripts, withDestinationURL: outside)
    let linkedLeaf = await analyze(isolatedScanner, applications: [app])
    require(!selectable(linkedLeaf, owner: app, path: scripts) && !selectable(linkedLeaf, owner: app, path: outside),
            "a symlink-shaped app scripts directory cannot authorize moving its target")
    try manager.removeItem(at: scripts)
    try manager.moveItem(at: retainedScripts, to: scripts)
    let scriptRoot = scripts.deletingLastPathComponent()
    let retainedRoot = root.appendingPathComponent("retained-script-root")
    let outsideRoot = try directory("outside-script-root")
    try manager.createDirectory(at: outsideRoot.appendingPathComponent(identifier), withIntermediateDirectories: true)
    try manager.moveItem(at: scriptRoot, to: retainedRoot)
    try manager.createSymbolicLink(at: scriptRoot, withDestinationURL: outsideRoot)
    let linkedRoot = await analyze(isolatedScanner, applications: [app])
    require(!selectable(linkedRoot, owner: app, path: scripts),
            "a registered root replaced by a symlink must not grant ownership of external children")
    try manager.removeItem(at: scriptRoot)
    try manager.moveItem(at: retainedRoot, to: scriptRoot)
    let externalSentinel = try String(contentsOf: outside.appendingPathComponent("sentinel"), encoding: .utf8)
    require(externalSentinel == "must stay intact",
            "script-link discovery must leave the external target intact")

    let fresh = await analyze(isolatedScanner, applications: [app])
    let freshItems = try requiredPlan(fresh, owner: app).items
    let originalPaths = Set([app.id, container, scripts].map(pathKey))
    let selectedItems = freshItems.filter { originalPaths.contains(pathKey($0.candidate.url)) }
    require(selectedItems.count == 3, "fixture uninstall must retain all three original independently verified items")
    let plan = try PlanBuilder(protectionPolicy: .init(homeDirectory: home)).build(
        candidates: freshItems.map(\.candidate), selectedIDs: Set(selectedItems.map(\.id)))
    require(plan.selectedItems.last.map { pathKey($0.candidate.url) } == pathKey(app.id),
            "associated data must be revalidated and moved before its app metadata source")
    let executor = CleanupExecutor(pathPolicy: .init(homeDirectory: home),
        quarantineRoot: root.appendingPathComponent("quarantine"), currentRuleVersion: plan.ruleVersion,
        loadProtection: { ProtectionPolicy(homeDirectory: home) },
        validateCandidate: { candidate in
            try await validateExpected(candidate, "recoverable fixture execution")
        })
    let receipt = await executor.execute(plan: plan)
    require(receipt.overallStatus == .completed && receipt.results.count == 3
            && receipt.results.allSatisfy { $0.status == .succeeded && $0.disposition == .quarantined },
            "new root candidates must pass live validation and enter recoverable quarantine")
    require(originalPaths.allSatisfy { !manager.fileExists(atPath: $0) },
            "successful fixture execution must remove all three original paths")
    require(manager.fileExists(atPath: sharedCookies.path) && manager.fileExists(atPath: invalidHostNames.map { byHost.appendingPathComponent($0) }[0].path),
            "fixture uninstall must preserve unselected shared cookies and unrelated ByHost files")
    let restored = await executor.restore(receipt: receipt)
    require(restored.results.count == 3 && restored.results.allSatisfy { $0.disposition == .restored },
            "new association roots must restore through the ordinary recovery path")
    require(originalPaths.allSatisfy { manager.fileExists(atPath: $0) },
            "recovery must restore app, container and the originally empty script directory")
    let restoredPayload = try String(contentsOf: containerPayload, encoding: .utf8)
    require(restoredPayload == "retain this fixture payload through recovery",
            "recoverable uninstall must preserve container payload contents")
    let encoded = try JSONEncoder().encode(scriptsItem)
    let decoded = try JSONDecoder().decode(UninstallItem.self, from: encoded)
    require(decoded == scriptsItem, "new association root candidates must retain identity and selection evidence in Codable round trips")
    let association = ApplicationAssociation(url: plugin, kind: .plugin, ownershipEvidence: "fixture identity",
        containsUserData: true, isShared: false, risk: .blocked, ownershipBasis: .bundleIdentifier,
        removalPolicy: .referenceOnly)
    let associationData = try JSONEncoder().encode(association)
    let decodedAssociation = try JSONDecoder().decode(ApplicationAssociation.self, from: associationData)
    require(decodedAssociation == association && decodedAssociation.removalPolicy == .referenceOnly,
            "typed ownership and reference-only policy must survive persisted association round trips")
    guard var legacyObject = try JSONSerialization.jsonObject(with: associationData) as? [String: Any] else {
        throw AssociationRootsContractFailure(description: "Encoded association must be a JSON object")
    }
    legacyObject.removeValue(forKey: "removalPolicy")
    legacyObject.removeValue(forKey: "ownershipBasis")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyAssociation = try JSONDecoder().decode(ApplicationAssociation.self, from: legacyData)
    require(legacyAssociation.removalPolicy == nil && legacyAssociation.ownershipBasis == nil,
            "old persisted associations lacking the new typed policy/evidence fields must remain decodable")
    print("PASS: unified application roots, empty scripts, ByHost/cookie boundaries, user temp scope, copies/groups, reference-only policy, symlinks and recoverable execution")
}
