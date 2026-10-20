import CleanerCore
import Foundation

private struct NoInstallations: ApplicationInstallationInspecting {
    func installations(for applications: [InstalledApplication], context: ScanContext) async -> (values: [URL: ApplicationInstallation], coverage: CoverageSummary) { ([:], .init()) }
}

func runApplicationOwnershipContracts() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("ownership-contract-" + UUID().uuidString).resolvingSymlinksInPath()
    defer { try? manager.removeItem(at: root) }
    let home = root.appendingPathComponent("home")
    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func write(_ url: URL, _ text: String) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func app(_ name: String, _ id: String, groups: [String] = []) throws -> InstalledApplication {
        let url = try directory("home/Applications/" + name + ".app")
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleVersion": "1"], format: .xml, options: 0)
        try manager.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try info.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return InstalledApplication(bundleURL: url, bundleIdentifier: id, name: name, version: "1", isRunning: false, isSystem: false, applicationGroups: groups)
    }
    let stable = try app("Stable", "com.contract.product", groups: ["TEAM.shared"])
    let beta = try app("Beta", "com.contract.product", groups: ["TEAM.shared"])
    let other = try app("Other", "com.contract.other", groups: ["TEAM.shared"])
    let cache = try directory("home/Library/Caches/com.contract.product")
    let group = try directory("home/Library/Group Containers/TEAM.shared")
    let config = home.appendingPathComponent(".codex/config.toml")
    try write(config, "secret = 'never-export-this-secret'\ncommand = '\(stable.id.path)/Contents/MacOS/tool'\nother = 'com.contract.product2'\n")
    let builder = ApplicationOwnershipGraphBuilder(installationInspector: NoInstallations(), configurationFiles: [config], includeSystemRoots: false)
    let scanner = ApplicationScanner(ownershipBuilder: builder, applicationRoots: [home.appendingPathComponent("Applications")])
    let context = ScanContext(homeDirectory: home)
    let index = await scanner.associationIndex(for: [stable, beta, other], context: context)
    let ownedCache = index.associations[stable.id]?.first { $0.url.path == cache.path }
    require(ownedCache?.risk == .blocked && ownedCache?.isShared == true, "duplicate copies must protect even exactly matched caches")
    require(Set(ownedCache?.ownerBundleURLs ?? []) == [stable.id, beta.id], "graph must retain both differently named copies of same ID")
    let groupNode = index.ownershipGraph?.resources.first { $0.id.path == group.path }
    require(Set(groupNode?.owners ?? []) == [stable.id, beta.id, other.id], "entitlement groups must union all owners")
    require(groupNode?.isShared == true, "shared groups are never selectable")
    let references = index.ownershipGraph?.application(at: stable.id)?.configurationReferences ?? []
    require(references.count == 1 && references[0].line == 2 && references[0].file == config, "configuration references expose exact location and reject ID-prefix collisions")
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let json = String(decoding: try encoder.encode(index.ownershipGraph), as: UTF8.self)
    require(!json.contains("never-export-this-secret") && !json.contains("Contents/MacOS/tool"), "graph serialization must contain no configuration contents or arguments")

    let inventory = ApplicationInventory(applications: [stable, beta, other], coverage: .init(), scannedAt: context.now)
    let analysis = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(inventory: inventory, context: context)
    require(analysis.ownershipGraph != nil && analysis.analysis(for: stable.id)?.ownership?.copies == [beta.id], "analysis and JSON retain ownership graph")
    require(analysis.analysis(for: stable.id)?.plan?.items.first { $0.candidate.url.path == cache.path }?.isShared == true, "planner uses graph, not single-app filename guessing")

    // A new copy after preview must invalidate resource execution, even if its
    // name differs and the selected file identity has not changed.
    let oneIndex = await scanner.associationIndex(for: [stable], context: context)
    let onePlan = try await UninstallPlanner().buildPlan(stable, associations: oneIndex.associations[stable.id, default: []], context: context)
    let oldCacheCandidate = onePlan.plan.items.first { $0.candidate.url.path == cache.path }!.candidate
    do {
        try await ApplicationExecutionValidator(scanner: scanner).validate(oldCacheCandidate, context: context)
        require(false, "new duplicate copy must invalidate old candidate")
    } catch ApplicationExecutionRejection.stillReferenced { }
    try manager.removeItem(at: beta.id)
    try await ApplicationExecutionValidator(scanner: scanner).validate(oldCacheCandidate, context: context)

    let singleOwnerIndex = await scanner.associationIndex(for: [stable], context: context)
    let singleOwnerGroup = singleOwnerIndex.associations[stable.id]?.first { $0.url.path == group.path }
    require(singleOwnerGroup?.isShared == false && singleOwnerGroup?.risk == .review, "an app group with no other installed owner must be explicitly reviewable")
    let groupPlan = try await UninstallPlanner(scanner: scanner).buildPlan(stable, associations: singleOwnerIndex.associations[stable.id, default: []], context: context)
    let groupItem = groupPlan.plan.items.first { $0.candidate.url.path == group.path }!
    require(groupPlan.plan.selectableItemIDs.contains(groupItem.id), "exclusive group data is manually selectable without being auto-selected")
    var groupSelection = UninstallBatchSelectionState()
    groupSelection.toggle(item: groupItem)
    require(groupSelection.selectedItemIDs.contains(groupItem.id), "exclusive app-group data can be selected for recoverable deletion")

    let serviceRoot = try directory("system/LaunchDaemons")
    let helperRoot = try directory("system/PrivilegedHelperTools")
    let helper = helperRoot.appendingPathComponent("com.contract.product")
    try write(helper, "not-an-executable")
    let service = serviceRoot.appendingPathComponent("unrelated-label.plist")
    let plist: [String: Any] = ["Label": "unrelated-label", "ProgramArguments": [helper.path, stable.id.path + "/Contents/MacOS/tool", "secret-service-argument"]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: service)
    let serviceBuilder = ApplicationOwnershipGraphBuilder(installationInspector: NoInstallations(), configurationFiles: [], additionalAssociationRoots: [
        .init(url: serviceRoot, kind: .launchDaemon, isSystem: true), .init(url: helperRoot, kind: .privilegedHelper, isSystem: true),
    ], includeSystemRoots: false)
    let serviceIndex = await ApplicationScanner(ownershipBuilder: serviceBuilder).associationIndex(for: [stable, beta], context: context)
    let helperNode = serviceIndex.ownershipGraph?.resources.first { $0.id.path == helper.path }
    require(helperNode?.references.first?.file.path == service.path && helperNode?.isSystemResource == true, "service paths protect referenced helpers independent of labels")
    require(serviceIndex.ownershipGraph?.application(at: stable.id)?.requiresExternalUninstall == true, "body must not leave a broken surviving launch service")
    require(serviceIndex.ownershipGraph?.application(at: stable.id)?.blocksAssociationDeletion == false, "an app-owned service must not blanket-block independently verified associations")
    let serviceScanner = ApplicationScanner(ownershipBuilder: serviceBuilder, applicationRoots: [home.appendingPathComponent("Applications")])
    try await ApplicationExecutionValidator(scanner: serviceScanner).validate(onePlan.plan.items.first!.candidate, context: context)
    try await ApplicationExecutionValidator(scanner: serviceScanner).validate(oldCacheCandidate, context: context)
    let serviceJSON = String(decoding: try encoder.encode(serviceIndex), as: UTF8.self)
    require(!serviceJSON.contains("secret-service-argument"), "service arguments never escape into evidence")

    let loginItem = try directory("home/Applications/Other.app/Contents/Library/LoginItems/Background.app")
    let embedded = await scanner.associationIndex(for: [other], context: context)
    let embeddedNode = embedded.ownershipGraph?.application(at: other.id)
    require(embeddedNode?.requiresExternalUninstall == true && embeddedNode?.serviceReferences?.contains { $0.file.standardizedFileURL.path == loginItem.standardizedFileURL.path } == true,
            "embedded SMAppService login item must protect body without pretending registration is known")
    let embeddedAnalysis = await ApplicationUninstallAnalyzer(scanner: scanner).analyze(inventory: .init(applications: [other], coverage: .init(), scannedAt: context.now), context: context)
    require(embeddedAnalysis.analysis(for: other.id)?.plan?.items.first?.candidate.risk == .review, "a stopped user app remains explicitly uninstallable while related service data stays separate")
    try manager.removeItem(at: loginItem)
    let afterRemovingDefinition = await scanner.associationIndex(for: [other], context: context)
    require(afterRemovingDefinition.ownershipGraph?.application(at: other.id)?.requiresExternalUninstall == false, "empty embedded service directory does not imply registration")

    // Cask receipts and Steam manifests route to native channels; neither is
    // executed or erased by the scanner. Nonstandard cask token is not guessed.
    let caskRoot = try directory("Caskroom")
    let caskReceipt = caskRoot.appendingPathComponent("product/.metadata/1/2026/Casks/product.json")
    try write(caskReceipt, "{\"token\":\"product\",\"artifacts\":[{\"app\":[\"Stable.app\",{\"target\":\"\(stable.id.path)\"}]}]}")
    let steamRoot = try directory("steamapps")
    let gameURL = try directory("steamapps/common/Game/Game.app")
    let game = InstalledApplication(bundleURL: gameURL, bundleIdentifier: "com.contract.game", name: "Game", version: nil, isRunning: false, isSystem: false)
    try write(steamRoot.appendingPathComponent("appmanifest_42.acf"), "\"appid\" \"42\"\n\"installdir\" \"Game\"")
    let inspector = LocalApplicationInstallationInspector(caskRoots: [caskRoot], receiptRoots: [], steamRoots: [steamRoot])
    let installs = await inspector.installations(for: [stable, game], context: context)
    require(installs.values[stable.id]?.source == .homebrew && installs.values[stable.id]?.packageManagerCommand == "brew uninstall --cask -- product", "cask receipt produces safe explicit handoff command")
    require(installs.values[game.id]?.source == .steam && installs.values[game.id]?.requiresExternalUninstall == true, "Steam library ownership must retain managed state")
    let receipts = try directory("receipts")
    let payload = try directory("payload")
    _ = try directory("payload/Stable.app")
    let bom = receipts.appendingPathComponent("unrelated-package-id.bom")
    let bomOutput = try await BoundedProcess.run("/usr/bin/mkbom", arguments: [payload.path, bom.path], timeout: 3)
    require(bomOutput.status == 0, "temporary test BOM generation")
    let packageReceipt = receipts.appendingPathComponent("unrelated-package-id.plist")
    let packageData = try PropertyListSerialization.data(fromPropertyList: ["PackageIdentifier": "org.unrelated.pkg", "InstallPrefixPath": stable.id.deletingLastPathComponent().path], format: .binary, options: 0)
    try packageData.write(to: packageReceipt)
    let packages = await LocalApplicationInstallationInspector(caskRoots: [], receiptRoots: [receipts], steamRoots: []).installations(for: [stable, other], context: context)
    require(packages.values[stable.id]?.source == .packageInstaller && packages.values[other.id]?.source == .unknown, "receipt association must use installed payload path, never package-name guesses")
    require(packages.values[stable.id]?.receipts.contains { $0.standardizedFileURL.path == bom.standardizedFileURL.path } == true, "receipt and BOM are retained as evidence, never cleanup candidates")
    let managedScanner = ApplicationScanner(ownershipBuilder: .init(installationInspector: inspector, configurationFiles: [], includeSystemRoots: false))
    let managed = await ApplicationUninstallAnalyzer(scanner: managedScanner).analyze(inventory: .init(applications: [stable], coverage: .init(), scannedAt: context.now), context: context)
    require(managed.analysis(for: stable.id)?.plan?.items.first?.candidate.risk == .review, "managed app body can be removed independently while package-managed associated files stay protected")
    let caskScanner = ApplicationScanner(ownershipBuilder: .init(installationInspector: inspector, configurationFiles: [], includeSystemRoots: false),
        applicationRoots: [home.appendingPathComponent("Applications")])
    do {
        try await ApplicationExecutionValidator(scanner: caskScanner).validate(oldCacheCandidate, context: context)
        require(false, "new Cask receipt must invalidate old associated cache preview")
    } catch ApplicationExecutionRejection.managedInstallation { }
    // A moved body is only an identity anchor, not permission to bypass an
    // installer receipt that still owns its original payload path.
    let isolatedBody = root.appendingPathComponent("isolated-Stable.app")
    try manager.moveItem(at: stable.id, to: isolatedBody)
    do {
        try await ApplicationExecutionValidator(scanner: caskScanner).validate(oldCacheCandidate, context: context)
        require(false, "absent-body anchor must retain managed installation protection")
    } catch ApplicationExecutionRejection.managedInstallation { }
    try manager.moveItem(at: isolatedBody, to: stable.id)

    let limited = await ApplicationOwnershipGraphBuilder(installationInspector: NoInstallations(), configurationFiles: [config], maximumEntries: 1, includeSystemRoots: false).build(applications: [stable], associations: [stable.id: oneIndex.associations[stable.id, default: []]], coverage: .init(), context: context)
    require(limited.coverage.budgetLimitedModules == [.applications], "graph budget exhaustion remains explicit")
    require(limited.associations[stable.id, default: []].contains { $0.risk.isSelectable }, "incomplete graph coverage must not blanket-block independently attributable app data")
    require(limited.ownershipGraph?.application(at: stable.id)?.ownershipVerified == false, "incomplete ownership coverage remains visible even when independent data can be reviewed")
    let unreadableConfig = home.appendingPathComponent("unreadable-config")
    try manager.createSymbolicLink(at: unreadableConfig, withDestinationURL: config)
    let incompleteReferences = await ApplicationOwnershipGraphBuilder(installationInspector: NoInstallations(), configurationFiles: [unreadableConfig], includeSystemRoots: false).build(applications: [stable], associations: [stable.id: oneIndex.associations[stable.id, default: []]], coverage: .init(), context: context)
    require(incompleteReferences.coverage.unavailableRoots.contains(unreadableConfig) && incompleteReferences.associations[stable.id, default: []].contains { $0.risk.isSelectable }, "unreadable reference files must not blanket-block independently attributable app data")
    print("PASS: application copies, entitlement owners, services, private configuration locations, managed uninstall and stale-plan rejection")
}
