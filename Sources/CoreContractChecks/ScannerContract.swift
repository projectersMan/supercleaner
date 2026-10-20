import CleanerCore
import Foundation

func runScannerContracts() async throws {
    require(LargeFileThreshold(storedBytes: nil) == .mb100, "missing large-file preferences must use the 100 MB default")
    require(LargeFileThreshold(storedBytes: 500_000_000) == .mb500, "a supported stored threshold must round-trip")
    require(LargeFileThreshold(storedBytes: 42) == .mb100, "invalid stored thresholds must safely fall back to 100 MB")
    require(
        LargeFileThreshold.allCases.map(\.bytes) == [10_000_000, 50_000_000, 100_000_000, 500_000_000, 1_000_000_000],
        "large-file settings must offer the approved threshold choices"
    )
    require(!ScanModuleState.waiting.isTerminal, "waiting scan modules must remain nonterminal")
    require(!ScanModuleState.scanning.isTerminal, "scanning modules must remain nonterminal")
    require(ScanModuleState.completed.isTerminal, "completed scan modules must be terminal")
    require(ScanModuleState.limited.isTerminal, "limited scan modules must be terminal")
    require(ScanModuleState.failed.isTerminal, "failed scan modules must be terminal")
    require(ScanModuleState.cancelled.isTerminal, "cancelled scan modules must be terminal")

    let duplicatedRoot = URL(fileURLWithPath: "/Users/tester/Documents/../Downloads")
    let standardizedRoot = URL(fileURLWithPath: "/Users/tester/Downloads")
    let coverage = CoverageSummary(
        scannedRoots: [duplicatedRoot, standardizedRoot],
        unavailableRoots: [duplicatedRoot, standardizedRoot],
        budgetLimitedModules: [.largeFiles]
    )
    require(coverage.scannedRoots == [standardizedRoot], "coverage scanned roots must be standardized and deduplicated")
    require(coverage.unavailableRoots == [standardizedRoot], "coverage unavailable roots must be standardized and deduplicated")
    require(DiskUsageScanner().maximumDepth == nil, "production disk scanning must not have a default depth limit")
    require(DiskUsageScanner().maximumEntries == nil, "production disk scanning must not have a default entry limit")
    require(LargeFileScanner().maximumDepth == nil, "production large-file scanning must not have a default depth limit")
    require(LargeFileScanner().maximumEntries == nil, "production large-file scanning must not have a default entry limit")
    try await runDeveloperArtifactScannerContracts()

    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let now = Date(timeIntervalSince1970: 10_000_000)
    let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
    let oldCacheDirectory = cacheRoot.appendingPathComponent("old-directory", isDirectory: true)
    let staleCacheDirectory = cacheRoot.appendingPathComponent("stale-directory", isDirectory: true)
    let staleCachePayload = staleCacheDirectory.appendingPathComponent("payload.bin")
    let linkedOnlyCacheDirectory = cacheRoot.appendingPathComponent("linked-only-directory", isDirectory: true)
    let linkedOnlyEntry = linkedOnlyCacheDirectory.appendingPathComponent("external", isDirectory: true)
    let deepCacheDirectory = oldCacheDirectory.appendingPathComponent("deep", isDirectory: true)
    let bulkCacheDirectory = oldCacheDirectory.appendingPathComponent("bulk", isDirectory: true)
    let linkedCacheDirectory = oldCacheDirectory.appendingPathComponent("linked", isDirectory: true)
    let overflowCacheDirectory = cacheRoot.appendingPathComponent("overflow-directory", isDirectory: true)
    let diagnosticReports = home.appendingPathComponent("Library/DiagnosticReports", isDirectory: true)
    let diagnosticReport = diagnosticReports.appendingPathComponent("CleanerApp-2026-08-25.ips")
    let duplicateDiagnosticReport = diagnosticReports.appendingPathComponent("nested/../CleanerApp-2026-08-25.ips")
    let crashReporter = home.appendingPathComponent("Library/Application Support/CrashReporter", isDirectory: true)
    let crashReporterRecord = crashReporter.appendingPathComponent("CleanerApp.crash")
    let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
    let chromePartialDownload = downloads.appendingPathComponent("browser-image.crdownload")
    let safariPartialDownload = downloads.appendingPathComponent("macOS-update.download")
    let genericPartialDownload = downloads.appendingPathComponent("model.bin.part")
    let duplicateGenericPartialDownload = downloads.appendingPathComponent("nested/../model.bin.part")
    let completedDownload = downloads.appendingPathComponent("completed.zip")
    let researchData = home.appendingPathComponent("ResearchData", isDirectory: true)
    let researchArchive = researchData.appendingPathComponent("model-weights.bin")
    let project = downloads.appendingPathComponent("LargeProject", isDirectory: true)
    let projectSmallFile = project.appendingPathComponent("small-project-note.txt")
    let linkedDirectory = project.appendingPathComponent("Linked", isDirectory: true)
    let deepRoot = downloads.appendingPathComponent("DeepTree", isDirectory: true)
    var contractEntries: [URL: [ContractEntry]] = [
        home: [
            ContractEntry(url: cacheRoot, size: 0, modified: now, kind: .directory),
            ContractEntry(url: downloads, size: 0, modified: now, kind: .directory),
            ContractEntry(url: researchData, size: 0, modified: now, kind: .directory),
        ],
        cacheRoot: [
            ContractEntry(url: cacheRoot.appendingPathComponent("recent"), size: 50, modified: now.addingTimeInterval(-86_400)),
            ContractEntry(url: cacheRoot.appendingPathComponent("old"), size: 75, modified: now.addingTimeInterval(-86_400 * 45)),
            ContractEntry(url: oldCacheDirectory, size: 75, modified: now.addingTimeInterval(-86_400 * 45), kind: .directory),
            ContractEntry(url: staleCacheDirectory, size: 0, modified: now.addingTimeInterval(-86_400 * 45), kind: .directory),
            ContractEntry(url: linkedOnlyCacheDirectory, size: 0, modified: now.addingTimeInterval(-86_400 * 45), kind: .directory),
            ContractEntry(url: overflowCacheDirectory, size: 0, modified: now, kind: .directory),
        ],
        staleCacheDirectory: [
            ContractEntry(url: staleCachePayload, size: 640, modified: now.addingTimeInterval(-86_400 * 45)),
        ],
        linkedOnlyCacheDirectory: [
            ContractEntry(url: linkedOnlyEntry, size: 0, modified: now.addingTimeInterval(-86_400 * 45), kind: .symbolicLink),
        ],
        oldCacheDirectory: [
            ContractEntry(url: oldCacheDirectory.appendingPathComponent("payload.bin"), size: 500, modified: now),
            ContractEntry(url: deepCacheDirectory, size: 0, modified: now, kind: .directory),
            ContractEntry(url: bulkCacheDirectory, size: 0, modified: now, kind: .directory),
            ContractEntry(url: linkedCacheDirectory, size: 0, modified: now, kind: .symbolicLink),
            ContractEntry(url: oldCacheDirectory.appendingPathComponent("alias/../payload.bin"), size: 500, modified: now),
        ],
        linkedCacheDirectory: [ContractEntry(url: linkedCacheDirectory.appendingPathComponent("must-not-count.bin"), size: 9_000, modified: now)],
        overflowCacheDirectory: [
            ContractEntry(url: overflowCacheDirectory.appendingPathComponent("maximum.bin"), size: .max, modified: now),
            ContractEntry(url: overflowCacheDirectory.appendingPathComponent("one-more.bin"), size: 1, modified: now),
        ],
        diagnosticReports: [
            ContractEntry(url: diagnosticReport, size: 900, modified: now.addingTimeInterval(-86_400)),
            ContractEntry(url: duplicateDiagnosticReport, size: 900, modified: now.addingTimeInterval(-86_400)),
        ],
        crashReporter: [
            ContractEntry(url: crashReporterRecord, size: 700, modified: now.addingTimeInterval(-86_400 * 45)),
        ],
        downloads: [
            ContractEntry(url: downloads.appendingPathComponent("archive.bin"), size: 1_000, modified: now),
            ContractEntry(url: downloads.appendingPathComponent("small-note.txt"), size: 10, modified: now),
            ContractEntry(url: chromePartialDownload, size: 300, modified: now),
            ContractEntry(url: safariPartialDownload, size: 400, modified: now),
            ContractEntry(url: genericPartialDownload, size: 500, modified: now),
            ContractEntry(url: duplicateGenericPartialDownload, size: 500, modified: now),
            ContractEntry(url: completedDownload, size: 600, modified: now),
            ContractEntry(url: project, size: 1, modified: now, kind: .directory),
            ContractEntry(url: deepRoot, size: 0, modified: now, kind: .directory),
        ],
        project: [
            ContractEntry(url: project.appendingPathComponent("nested.bin"), size: 600, modified: now),
            ContractEntry(url: projectSmallFile, size: 10, modified: now),
            ContractEntry(url: linkedDirectory, size: 1, modified: now, kind: .symbolicLink),
        ],
        linkedDirectory: [ContractEntry(url: linkedDirectory.appendingPathComponent("must-not-read.bin"), size: 5_000, modified: now)],
        researchData: [ContractEntry(url: researchArchive, size: 800, modified: now)],
    ]
    var deepCacheParent = deepCacheDirectory
    contractEntries[deepCacheDirectory] = []
    for depth in 0...40 {
        let child = deepCacheParent.appendingPathComponent("level-\(depth)", isDirectory: true)
        contractEntries[deepCacheParent, default: []].append(ContractEntry(url: child, size: 0, modified: now, kind: .directory))
        contractEntries[child] = []
        deepCacheParent = child
    }
    contractEntries[deepCacheParent, default: []].append(
        ContractEntry(url: deepCacheParent.appendingPathComponent("deep-payload.bin"), size: 700, modified: now)
    )
    contractEntries[bulkCacheDirectory] = (0..<10_005).map { index in
        ContractEntry(url: bulkCacheDirectory.appendingPathComponent("payload-\(index).bin"), size: 1, modified: now)
    }
    var deepParent = deepRoot
    contractEntries[deepRoot] = []
    for depth in 0...12 {
        let child = deepParent.appendingPathComponent("level-\(depth)", isDirectory: true)
        contractEntries[deepParent, default: []].append(ContractEntry(url: child, size: 0, modified: now, kind: .directory))
        contractEntries[child] = []
        deepParent = child
    }
    let beyondLegacyDepth = deepParent.appendingPathComponent("beyond-legacy-depth.txt")
    contractEntries[deepParent, default: []].append(ContractEntry(url: beyondLegacyDepth, size: 110, modified: now))
    let fileSystem = ContractFileSystem(entries: contractEntries)
    let context = ScanContext(
        homeDirectory: home,
        fileSystem: fileSystem,
        now: now,
        activePaths: [crashReporterRecord]
    )

    let inaccessibleDirectory = home.appendingPathComponent("Restricted", isDirectory: true)
    let readableLargeFile = home.appendingPathComponent("readable-large.bin")
    let partialFileSystem = ContractFileSystem(
        entries: [
            home: [
                ContractEntry(url: readableLargeFile, size: 1_000, modified: now),
                ContractEntry(url: inaccessibleDirectory, size: 0, modified: now, kind: .directory),
            ],
            inaccessibleDirectory: [],
        ],
        failingChildDirectories: [inaccessibleDirectory]
    )
    let partialTree = try await DiskUsageScanner(minimumFileBytes: 100).scan(
        context: ScanContext(homeDirectory: home, fileSystem: partialFileSystem, now: now)
    )
    require(partialTree.roots.map(\.url) == [home], "one inaccessible descendant must not discard the user-home root")
    require(partialTree.largeFiles.map(\.url) == [readableLargeFile], "readable files must survive a sibling directory access failure")
    require(partialTree.node(at: inaccessibleDirectory)?.isReadable == false, "an inaccessible descendant must remain visible in the disk tree")
    require(partialTree.coverage.unavailableRoots == [inaccessibleDirectory], "coverage must identify the exact inaccessible descendant")

    let caches = try await UserCacheScanner().scan(context: context)
    require(caches.first { $0.displayName == "recent" }?.risk == .review, "recent cache must require review")
    require(caches.first { $0.displayName == "old" }?.risk == .safe, "old inactive cache should be safe")
    require(caches.first { $0.displayName == "stale-directory" }?.risk == .safe, "a fully stale rebuildable cache directory should be safe")
    require(caches.first { $0.displayName == "old-directory" }?.risk == .review, "a stale directory shell must remain review-only when nested content is recent or unverified")
    require(caches.first { $0.displayName == "linked-only-directory" }?.risk == .review, "a stale cache directory containing a symbolic link must not be recommended")
    require(
        caches.first { $0.displayName == "old-directory" }?.bytes == 11_205,
        "cache directory size must traverse every depth and entry exactly once without a production cap"
    )
    require(
        caches.first { $0.displayName == "overflow-directory" }?.bytes == .max,
        "cache directory size must saturate instead of overflowing"
    )

    let diagnostics = try await LogScanner().scan(context: context)
    require(
        Set(diagnostics.map(\.url.standardizedFileURL)) == Set([diagnosticReport, crashReporterRecord]),
        "log scanning must cover DiagnosticReports and CrashReporter without duplicate canonical paths"
    )
    require(diagnostics.allSatisfy { $0.category == .log && $0.source == .general }, "diagnostic artifacts must have an explicit general-log classification")
    require(diagnostics.allSatisfy { $0.evidence.contains(where: { $0.code == "diagnostic-report" }) }, "diagnostic artifacts must explain why they were discovered")
    require(diagnostics.first { $0.url.standardizedFileURL == diagnosticReport.standardizedFileURL }?.risk == .review, "recent diagnostic reports must require review")
    require(diagnostics.first { $0.url.standardizedFileURL == crashReporterRecord.standardizedFileURL }?.risk == .blocked, "active CrashReporter records must remain blocked")
    let diagnosticChildRequests = await fileSystem.requestedChildren()
    require(diagnosticChildRequests.contains(diagnosticReports.path), "log scanning must inspect the user DiagnosticReports directory")
    require(diagnosticChildRequests.contains(crashReporter.path), "log scanning must inspect the user CrashReporter directory")
    require(
        !diagnosticChildRequests.contains(home.appendingPathComponent("Library/Application Support", isDirectory: true).path),
        "diagnostic scanning must not broaden into durable Application Support state"
    )

    let diskTree = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: context)
    require(diskTree.minimumFileBytes == 100, "disk reports must preserve the threshold used to generate their visible files")
    require(diskTree.roots.map(\.url) == [home], "default disk scanning must use the user home as its single root")
    let projectNode = diskTree.node(at: project)
    require(projectNode?.kind == .directory, "disk tree must retain directories as navigation nodes")
    require(projectNode?.recursiveBytes == 610, "directory occupancy must include files hidden below the large-file threshold")
    require(diskTree.node(at: projectSmallFile) == nil, "files below the threshold must not be retained as visible disk nodes")
    require(diskTree.largeFiles.contains { $0.url == downloads.appendingPathComponent("archive.bin") }, "disk tree must expose large files under standard folders")
    require(diskTree.largeFiles.contains { $0.url == project.appendingPathComponent("nested.bin") }, "disk tree must expose nested concrete large files")
    require(diskTree.largeFiles.contains { $0.url == researchArchive }, "disk tree must expose large files outside the legacy folder allowlist")
    require(diskTree.node(at: beyondLegacyDepth) != nil, "default disk scanning must continue past the legacy depth cap")
    require(!diskTree.coverage.budgetLimitedModules.contains(.largeFiles), "complete default disk scans must not report a synthetic budget limit")
    let depthLimitedTree = try await DiskUsageScanner(minimumFileBytes: 100, maximumDepth: 3).scan(context: context)
    require(depthLimitedTree.node(at: beyondLegacyDepth) == nil, "an explicit diagnostic depth cap must still stop traversal")
    require(depthLimitedTree.coverage.budgetLimitedModules.contains(.largeFiles), "an explicit diagnostic depth cap must report limited coverage")
    let entryLimitedTree = try await DiskUsageScanner(minimumFileBytes: 100, maximumEntries: 1).scan(context: context)
    require(entryLimitedTree.coverage.budgetLimitedModules.contains(.largeFiles), "an explicit diagnostic entry cap must report limited coverage")
    let childRequests = await fileSystem.requestedChildren()
    require(!childRequests.contains(linkedDirectory.path), "disk tree must never traverse symbolic links")
    require(!childRequests.contains(linkedCacheDirectory.path), "general directory measurement must never traverse symbolic links")

    let identityRequestsBeforeCandidateMaterialization = await fileSystem.identityRequestCount()
    _ = try await LargeFileScanner(minimumBytes: 100).candidates(from: diskTree, context: context)
    let identityRequestsAfterCandidateMaterialization = await fileSystem.identityRequestCount()
    require(
        identityRequestsAfterCandidateMaterialization == identityRequestsBeforeCandidateMaterialization,
        "disk candidate materialization must reuse identities already captured by the directory scan"
    )
    let stricterCandidates = try await LargeFileScanner(minimumBytes: 700).candidates(from: diskTree, context: context)
    require(stricterCandidates.allSatisfy { $0.bytes >= 700 }, "candidate materialization must enforce its configured threshold")

    let largeFiles = try await LargeFileScanner(minimumBytes: 100).scan(context: context)
    require(largeFiles.allSatisfy { $0.risk != .safe }, "large files cannot be safe based on size")
    require(largeFiles.allSatisfy { $0.identity.kind == .file }, "large-file cleanup candidates must be concrete files")
    require(!largeFiles.contains { $0.url == project }, "directories must never become large-file cleanup candidates")
    require(!largeFiles.contains { $0.url == downloads.appendingPathComponent("small-note.txt") }, "files below the threshold must not become cleanup candidates")

    let indexedTree = try await IndexedLargeFileScanner(
        minimumBytes: 100,
        index: ContractLargeFileMetadataIndex(urls: [
            downloads.appendingPathComponent("archive.bin"),
            downloads.appendingPathComponent("archive.bin"),
            downloads.appendingPathComponent("small-note.txt"),
            project,
            URL(fileURLWithPath: "/Users/other/private.bin"),
        ])
    ).scan(context: context)
    require(indexedTree.analysisState == .indexedResults, "metadata discovery must identify its result as an indexed preview")
    require(indexedTree.coverage.scannedRoots.isEmpty, "an indexed preview must not claim that the directory tree was fully scanned")
    require(indexedTree.largeFiles.map(\.url) == [downloads.appendingPathComponent("archive.bin")], "indexed discovery must revalidate type, size, scope, and canonical-path uniqueness")
    require(indexedTree.roots == indexedTree.largeFiles, "indexed discovery must publish a file-first list without waiting for a directory hierarchy")
    let previewCandidate = try await LargeFileScanner(minimumBytes: 100).candidates(from: indexedTree, context: context)[0]
    let replacementCandidate = CleanupCandidate(
        url: previewCandidate.url,
        displayName: previewCandidate.displayName,
        category: previewCandidate.category,
        bytes: previewCandidate.bytes,
        risk: previewCandidate.risk,
        evidence: previewCandidate.evidence,
        identity: previewCandidate.identity,
        source: previewCandidate.source,
        lastAccessDate: previewCandidate.lastAccessDate,
        isActive: previewCandidate.isActive
    )
    let preservedDiskSelection = DiskUsageSelectionState(
        candidates: [previewCandidate],
        selectedIDs: [previewCandidate.id]
    )
    require(
        preservedDiskSelection.selectedCandidateIDs(in: [replacementCandidate]) == [replacementCandidate.id],
        "large-file selection must survive replacement candidates by canonical file path"
    )
    var diskSelection = DiskUsageSelectionState()
    diskSelection.toggle(projectNode!)
    require(diskSelection.selectedFileURLs.isEmpty, "disk usage directories must not be selectable")
    diskSelection.toggle(diskTree.largeFiles[0])
    require(diskSelection.selectedFileURLs == [diskTree.largeFiles[0].url], "concrete disk usage files must be selectable")

    let scanners: [any CleanerCore.Scanner] = [UserCacheScanner(), ContractFailingScanner()]
    let report = await ScanCoordinator(maxConcurrentScanners: 2).scan(
        using: scanners,
        context: context
    )
    require(!report.candidates.isEmpty, "coordinator should retain successful scanner output")
    require(report.failures.map { $0.scannerID } == ["contract.failure"], "coordinator should contain scanner errors")

    let progressRecorder = SystemScanProgressRecorder()
    let moduleResultRecorder = SystemScanModuleResultRecorder()
    let publicationRecorder = SystemScanPublicationRecorder()
    let systemReport = await SystemScanCoordinator(
        largeFileIndex: ContractLargeFileMetadataIndex(urls: [downloads.appendingPathComponent("archive.bin")])
    ).scan(
        context: context,
        runningBundleIdentifiers: [],
        moduleResult: { result in
            await moduleResultRecorder.append(result)
            await publicationRecorder.appendResult(result)
        }
    ) { event in
        await progressRecorder.append(event)
        await publicationRecorder.appendProgress(event)
    }
    require(systemReport != nil, "full-system coordinator must commit a terminal report")
    let systemReportValue = systemReport!
    require(systemReportValue.isCommitEligible, "full-system report must commit only terminal module states")
    require(ScanModuleID.allCases.allSatisfy { systemReportValue.modules[$0]?.state.isTerminal == true }, "every full-system module must reach a terminal state")
    let progressEvents = await progressRecorder.events()
    require(!progressEvents.isEmpty, "full-system coordinator must publish module progress")
    require(Set(progressEvents.map(\.generationID)) == [systemReportValue.generationID], "all module progress must belong to one generation")
    let moduleResults = await moduleResultRecorder.results()
    require(moduleResults.count == ScanModuleID.allCases.count, "each module must publish exactly one completed result")
    require(Set(moduleResults.map(\.generationID)) == [systemReportValue.generationID], "progressive module results must use the final report generation")
    require(Set(moduleResults.map(\.module)) == Set(ScanModuleID.allCases), "progressive publication must cover every scan module")
    let publicationEvents = await publicationRecorder.events()
    for module in ScanModuleID.allCases {
        let resultIndex = publicationEvents.firstIndex(of: .result(module))
        let terminalIndex = publicationEvents.firstIndex(of: .terminalProgress(module))
        require(resultIndex != nil && terminalIndex != nil && resultIndex! < terminalIndex!, "a module payload must be installed before its completed progress becomes navigable")
    }
    let largeFileResults = moduleResults.filter { $0.module == .largeFiles }
    require(largeFileResults.count == 1, "large files must publish one terminal result")
    if case let .largeFiles(firstTree, _) = largeFileResults[0].payload {
        require(firstTree.analysisState == .indexedResults, "a successful Spotlight query must complete from indexed results")
    } else {
        require(false, "the large-file payload must contain a disk tree")
    }
    require(systemReportValue.diskUsageTree.analysisState == .indexedResults, "the final report must retain indexed results")
    require(systemReportValue.modules[.largeFiles]?.state == .completed, "indexed large-file scanning must complete the module")
    require(systemReportValue.modules[.largeFiles]?.message != nil, "indexed scanning must identify its data source")
    require(progressEvents.filter { $0.module == .largeFiles && $0.state.isTerminal }.count == 1, "large files must finish only once")

    let fallbackReport = await SystemScanCoordinator(
        largeFileIndex: ContractUnavailableLargeFileMetadataIndex()
    ).scan(context: context)
    require(fallbackReport?.isCommitEligible == true, "an unavailable index must still produce a completed report")
    require(fallbackReport?.diskUsageTree.analysisState == .complete, "an unavailable index must fall back to directory scanning")

    let emptyIndexReport = await SystemScanCoordinator(
        largeFileIndex: ContractLargeFileMetadataIndex(urls: [])
    ).scan(context: context)
    require(emptyIndexReport?.modules[.largeFiles]?.state == .completed, "an empty successful index must complete the module")
    require(emptyIndexReport?.diskUsageTree.analysisState == .indexedResults, "an empty Spotlight result must not trigger exact directory scanning")

    let indexedLimitedReport = await SystemScanCoordinator(
        diskUsageScanner: DiskUsageScanner(minimumFileBytes: 100, maximumEntries: 0),
        largeFileIndex: ContractLargeFileMetadataIndex(urls: [downloads.appendingPathComponent("archive.bin")])
    ).scan(context: context)
    require(
        indexedLimitedReport?.modules[.largeFiles]?.state == .completed,
        "a successful Spotlight result must remain completed without exact scanning"
    )
    require(
        indexedLimitedReport?.diskUsageTree.analysisState == .indexedResults,
        "a successful Spotlight result must not masquerade as an exact directory scan"
    )

    let moduleRefreshCompletedAt = now.addingTimeInterval(30)
    let moduleRefreshedReport = systemReportValue.replacing(
        module: .applications,
        payload: .applications(systemReportValue.applicationUninstallInventory),
        completedAt: moduleRefreshCompletedAt
    )
    require(
        moduleRefreshedReport.generationID == systemReportValue.generationID,
        "single-module replacement must preserve the report generation"
    )
    require(
        moduleRefreshedReport.startedAt == systemReportValue.startedAt,
        "single-module replacement must preserve the generation start time"
    )
    require(
        ScanModuleID.allCases.filter { $0 != .applications }.allSatisfy {
            moduleRefreshedReport.modules[$0] == systemReportValue.modules[$0]
        },
        "single-module replacement must preserve every untouched module status"
    )
    require(
        moduleRefreshedReport.generalCandidates.map(\.id) == systemReportValue.generalCandidates.map(\.id)
            && moduleRefreshedReport.largeFileCandidates.map(\.id) == systemReportValue.largeFileCandidates.map(\.id)
            && moduleRefreshedReport.agentAssets.map(\.id) == systemReportValue.agentAssets.map(\.id)
            && moduleRefreshedReport.agentSkills.map(\.id) == systemReportValue.agentSkills.map(\.id),
        "single-module replacement must preserve selectable identities from untouched modules"
    )

    let progressiveGenerationID = UUID()
    let progressiveApplicationStatus = ScanModuleStatus(
        module: .applications,
        state: .limited,
        startedAt: now,
        completedAt: now,
        message: "关联分析受限"
    )
    let progressiveApplicationResult = SystemScanModuleResult(
        generationID: progressiveGenerationID,
        status: progressiveApplicationStatus,
        payload: .applications(systemReportValue.applicationUninstallInventory)
    )
    let progressivelyMerged = systemReportValue.replacing(moduleResult: progressiveApplicationResult)
    require(progressivelyMerged.generationID == progressiveGenerationID, "progressive merge must adopt the active scan generation")
    require(progressivelyMerged.modules[.applications] == progressiveApplicationStatus, "progressive merge must preserve the emitted module status")
    require(progressivelyMerged.generalCandidates == systemReportValue.generalCandidates, "progressive merge must preserve untouched general results")
    require(progressivelyMerged.diskUsageTree == systemReportValue.diskUsageTree, "progressive merge must preserve untouched disk results")
    require(progressivelyMerged.agentAssets == systemReportValue.agentAssets, "progressive merge must preserve untouched Agent results")
    require(progressivelyMerged.agentSkills == systemReportValue.agentSkills, "progressive merge must preserve untouched Skill catalog results")

    let waitingStatuses = Dictionary(uniqueKeysWithValues: ScanModuleID.allCases.map {
        ($0, ScanModuleStatus(module: $0, state: .waiting))
    })
    var progressiveAccumulator = ProgressiveScanReportAccumulator(
        generationID: progressiveGenerationID,
        startedAt: now,
        rulesetVersion: "contract-progressive",
        baseline: systemReportValue,
        initialStatuses: waitingStatuses
    )
    let staleResult = SystemScanModuleResult(
        generationID: UUID(),
        status: progressiveApplicationStatus,
        payload: .applications(systemReportValue.applicationUninstallInventory)
    )
    require(!progressiveAccumulator.apply(staleResult), "a stale module result must be rejected")
    require(progressiveAccumulator.report.modules.values.allSatisfy { $0.state == .waiting }, "a stale result must not mutate module state")
    require(progressiveAccumulator.apply(progressiveApplicationResult), "the active generation result must be installed")
    require(progressiveAccumulator.report.generationID == progressiveGenerationID, "the progressive accumulator must retain its active generation")
    require(progressiveAccumulator.report.modules[.applications] == progressiveApplicationStatus, "the active module status must become visible immediately")
    require(progressiveAccumulator.report.generalCandidates == systemReportValue.generalCandidates, "waiting modules must retain their prior payload until replacement")
    require(systemReportValue.candidates.allSatisfy { $0.identity.kind != .symbolicLink }, "shared report must not include symbolic-link candidates")
    require(
        systemReportValue.applicationUninstallInventory.analyses.count == systemReportValue.applicationInventory.applications.count,
        "committed system reports must carry scan-time uninstall analysis for every discovered application"
    )
    let incompleteDownloads = systemReportValue.candidates.filter {
        $0.evidence.contains(where: { $0.code == "incomplete-download" })
    }
    require(
        Set(incompleteDownloads.map(\.url.standardizedFileURL)) == Set([chromePartialDownload, safariPartialDownload, genericPartialDownload]),
        "system scanning must recognize .crdownload, .download, and .part files in Downloads without including completed files"
    )
    require(incompleteDownloads.count == 3, "incomplete-download candidates must be deduplicated by canonical path")
    require(incompleteDownloads.allSatisfy { $0.category == .temporaryFile }, "incomplete downloads must be explicitly classified as temporary files")
    require(incompleteDownloads.allSatisfy { $0.risk == .review }, "incomplete downloads must require review instead of becoming automatic cleanup")
    if let firstCandidate = systemReportValue.candidates.first {
        require(systemReportValue.candidate(id: firstCandidate.id) == firstCandidate, "materialized system report must provide constant-time candidate lookup")
    }
    let writes = await fileSystem.mutationCount()
    require(writes == 0, "scanners must be read-only")
}

private func runDeveloperArtifactScannerContracts() async throws {
    let home = URL(fileURLWithPath: "/Users/developer", isDirectory: true)
    let now = Date(timeIntervalSince1970: 20_000_000)
    let old = now.addingTimeInterval(-86_400 * 45)
    let recent = now.addingTimeInterval(-86_400)

    let uvRoot = home.appendingPathComponent(".cache/uv", isDirectory: true)
    let npmExecRoot = home.appendingPathComponent(".npm/_npx", isDirectory: true)
    let gradleDaemonRoot = home.appendingPathComponent(".gradle/daemon", isDirectory: true)
    let swiftPMRoot = home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)
    let simulatorCacheRoot = home.appendingPathComponent("Library/Developer/CoreSimulator/Caches", isDirectory: true)
    let deviceSupportRoot = home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
    let documentationCacheRoot = URL(fileURLWithPath: "/Library/Developer/Xcode/DocumentationCache", isDirectory: true)

    let oldUVCache = uvRoot.appendingPathComponent("archive-v0.bin")
    let oldUVCacheDirectory = uvRoot.appendingPathComponent("archive-v1", isDirectory: true)
    let oldUVCachePayload = oldUVCacheDirectory.appendingPathComponent("payload.bin")
    let duplicateOldUVCache = uvRoot.appendingPathComponent("nested/../archive-v0.bin")
    let recentNPMExec = npmExecRoot.appendingPathComponent("temporary-command", isDirectory: true)
    let activeGradleDaemon = gradleDaemonRoot.appendingPathComponent("8.12", isDirectory: true)
    let linkedSwiftCache = swiftPMRoot.appendingPathComponent("linked", isDirectory: true)
    let unknownSwiftCache = swiftPMRoot.appendingPathComponent("opaque")
    let oldSimulatorCache = simulatorCacheRoot.appendingPathComponent("runtime-cache.bin")
    let oldDeviceSymbols = deviceSupportRoot.appendingPathComponent("18.4", isDirectory: true)
    let systemDocumentation = documentationCacheRoot.appendingPathComponent("index.db")

    let fileSystem = ContractFileSystem(entries: [
        uvRoot: [
            ContractEntry(url: oldUVCache, size: 400, modified: old),
            ContractEntry(url: duplicateOldUVCache, size: 400, modified: old),
            ContractEntry(url: oldUVCacheDirectory, size: 0, modified: old, kind: .directory),
        ],
        oldUVCacheDirectory: [ContractEntry(url: oldUVCachePayload, size: 500, modified: old)],
        npmExecRoot: [ContractEntry(url: recentNPMExec, size: 0, modified: recent, kind: .directory)],
        gradleDaemonRoot: [ContractEntry(url: activeGradleDaemon, size: 0, modified: old, kind: .directory)],
        swiftPMRoot: [
            ContractEntry(url: linkedSwiftCache, size: 0, modified: old, kind: .symbolicLink),
            ContractEntry(url: unknownSwiftCache, size: 20, modified: old, kind: .other),
        ],
        simulatorCacheRoot: [ContractEntry(url: oldSimulatorCache, size: 100, modified: old)],
        deviceSupportRoot: [ContractEntry(url: oldDeviceSymbols, size: 0, modified: old, kind: .directory)],
        documentationCacheRoot: [ContractEntry(url: systemDocumentation, size: 80, modified: old)],
    ])
    let context = ScanContext(
        homeDirectory: home,
        fileSystem: fileSystem,
        now: now,
        activePaths: [activeGradleDaemon]
    )

    let candidates = try await DeveloperArtifactScanner().scan(context: context)
    let byPath = Dictionary(candidates.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })

    require(byPath[oldUVCache.standardizedFileURL.path]?.risk == .safe, "old rebuildable uv cache files should be eligible for safe cleanup")
    require(byPath[oldUVCacheDirectory.standardizedFileURL.path]?.risk == .safe, "fully stale rebuildable developer cache directories should be eligible for safe cleanup")
    require(byPath[recentNPMExec.standardizedFileURL.path]?.risk == .review, "recent developer cache directories must require review")
    require(byPath[activeGradleDaemon.standardizedFileURL.path]?.risk == .blocked, "active Gradle state must remain blocked")
    require(byPath[linkedSwiftCache.standardizedFileURL.path]?.risk == .blocked, "symbolic-link developer cache entries must remain blocked")
    require(byPath[unknownSwiftCache.standardizedFileURL.path]?.risk == .blocked, "unknown developer cache entry kinds must remain blocked")
    require(byPath[oldSimulatorCache.standardizedFileURL.path]?.risk == .review, "CoreSimulator cache entries must require review regardless of age")
    require(byPath[oldDeviceSymbols.standardizedFileURL.path]?.risk == .review, "Xcode DeviceSupport entries must require review regardless of age")
    require(byPath[systemDocumentation.standardizedFileURL.path]?.risk == .blocked, "system Xcode documentation caches must remain protected")
    require(candidates.map { $0.url.standardizedFileURL.path }.count == Set(candidates.map { $0.url.standardizedFileURL.path }).count, "developer cache candidates must be canonical-path deduplicated")

    let requestedRoots = Set(await fileSystem.requestedChildren())
    let requiredRoots = [uvRoot, npmExecRoot, gradleDaemonRoot, swiftPMRoot, simulatorCacheRoot, deviceSupportRoot, documentationCacheRoot]
    require(requiredRoots.allSatisfy { requestedRoots.contains($0.path) }, "developer scanning must inspect supported tool cache roots")
    require(!requestedRoots.contains(home.appendingPathComponent(".cache", isDirectory: true).path), "developer scanning must not broaden into the entire user cache namespace")
    require(!requestedRoots.contains(home.appendingPathComponent("Library/Developer", isDirectory: true).path), "developer scanning must not broadly enumerate durable developer state")
}

private actor SystemScanProgressRecorder {
    private var values: [SystemScanProgressEvent] = []
    func append(_ event: SystemScanProgressEvent) { values.append(event) }
    func events() -> [SystemScanProgressEvent] { values }
}

private actor SystemScanModuleResultRecorder {
    private var values: [SystemScanModuleResult] = []
    func append(_ result: SystemScanModuleResult) { values.append(result) }
    func results() -> [SystemScanModuleResult] { values }
}

private enum SystemScanPublicationEvent: Equatable {
    case result(ScanModuleID)
    case terminalProgress(ScanModuleID)
}

private actor SystemScanPublicationRecorder {
    private var values: [SystemScanPublicationEvent] = []

    func appendResult(_ result: SystemScanModuleResult) {
        values.append(.result(result.module))
    }

    func appendProgress(_ event: SystemScanProgressEvent) {
        guard event.state.isTerminal else { return }
        values.append(.terminalProgress(event.module))
    }

    func events() -> [SystemScanPublicationEvent] { values }
}

private struct ContractLargeFileMetadataIndex: LargeFileMetadataIndexing {
    let urls: [URL]
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] { urls }
}

private struct ContractUnavailableLargeFileMetadataIndex: LargeFileMetadataIndexing {
    func matchingFileURLs(minimumBytes: UInt64, scope: URL) async throws -> [URL] {
        throw LargeFileMetadataIndexError.queryUnavailable
    }
}

private struct ContractFailingScanner: CleanerCore.Scanner {
    let id = "contract.failure"
    let category = CleanupCategory.cache
    func scan(context: ScanContext) async throws -> [CleanupCandidate] { throw ContractScanError.expected }
}

private enum ContractScanError: Error { case expected }

private struct ContractEntry: Sendable {
    let url: URL
    let size: UInt64
    let modified: Date
    let kind: FileIdentity.Kind
    init(url: URL, size: UInt64, modified: Date, kind: FileIdentity.Kind = .file) { self.url = url; self.size = size; self.modified = modified; self.kind = kind }
}

private actor ContractFileSystem: FileSystemAccess {
    private let entries: [URL: [ContractEntry]]
    private let entriesByPath: [String: ContractEntry]
    private let failingChildDirectoryPaths: Set<String>
    private var writes = 0
    private var childRequests: [String] = []
    private var identityRequests = 0
    init(entries: [URL: [ContractEntry]], failingChildDirectories: Set<URL> = []) {
        self.entries = entries
        self.failingChildDirectoryPaths = Set(failingChildDirectories.map { $0.standardizedFileURL.path })
        self.entriesByPath = Dictionary(
            entries.values.lazy.flatMap { $0 }.map { ($0.url.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
    func identity(at url: URL) throws -> FileIdentity {
        identityRequests += 1
        guard let entry = entriesByPath[url.path] else {
            throw FileSystemError.missing(url)
        }
        return FileIdentity(device: 1, inode: UInt64(bitPattern: Int64(url.path.hashValue)), size: entry.size, modificationTime: Int64(entry.modified.timeIntervalSince1970), kind: entry.kind)
    }
    func children(of url: URL) throws -> [URL] {
        childRequests.append(url.path)
        if failingChildDirectoryPaths.contains(url.standardizedFileURL.path) {
            throw FileSystemError.missing(url)
        }
        return entries.first { $0.key.standardizedFileURL.path == url.standardizedFileURL.path }?.value.map(\.url) ?? []
    }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) -> Bool { true }
    func move(_ source: URL, to destination: URL) { writes += 1 }
    func createDirectory(_ url: URL) { writes += 1 }
    func removeEmptyDirectory(_ url: URL) { writes += 1 }
    func trash(_ url: URL) -> URL { writes += 1; return url }
    func mutationCount() -> Int { writes }
    func requestedChildren() -> [String] { childRequests }
    func identityRequestCount() -> Int { identityRequests }
}
