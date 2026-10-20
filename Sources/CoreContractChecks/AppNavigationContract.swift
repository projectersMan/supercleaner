import CleanerCore

func runAppNavigationContracts() {
    require(
        AppDestination.allCases.map(\.title) == [
            "概览", "清理中心", "系统清理", "应用卸载", "大文件", "Agent 环境", "恢复记录", "设置",
        ].map { L10n.text($0) },
        "sidebar must expose the approved task-centered destinations"
    )

    let policy = AppNavigationPolicy()
    require(!policy.showsGlobalScanToolbar, "global scan toolbar must be removed")
    require(policy.initialScanOwner == .dashboard, "overview must own the first complete scan")
    require(policy.emptyStateAction(for: .cleanupCenter) == .none, "cleanup center owns the scan overview")
    require(policy.emptyStateAction(for: .systemCleanup) == .returnToDashboard, "system cleanup must route to the scan center before scanning")
    require(policy.emptyStateAction(for: .applications) == .returnToDashboard, "applications must route to overview before scanning")
    require(policy.emptyStateAction(for: .largeFiles) == .returnToDashboard, "large files must route to overview before scanning")
    require(policy.emptyStateAction(for: .agentEnvironment) == .returnToDashboard, "Agent environment must route to overview before scanning")
    require(policy.emptyStateAction(for: .recovery) == .none, "recovery does not depend on a scan report")

    require(!policy.showsDimensionActionBar(for: .cleanupCenter), "scan center must not show a dimension action bar")
    require(policy.showsDimensionActionBar(for: .systemCleanup), "system cleanup needs the shared dimension action bar")
    require(policy.showsDimensionActionBar(for: .applications), "application uninstall needs the shared dimension action bar")
    require(policy.showsDimensionActionBar(for: .largeFiles), "large files needs the shared dimension action bar")
    require(policy.showsDimensionActionBar(for: .agentEnvironment), "Agent cleanup needs the shared dimension action bar")
    require(!policy.showsDimensionActionBar(for: .dashboard), "overview must not show a dimension action bar")
    require(!policy.showsDimensionActionBar(for: .recovery), "recovery must not show a dimension action bar")
    require(!policy.showsDimensionActionBar(for: .settings), "settings must not show a dimension action bar")
    require(!policy.usesCandidateReviewFocus(for: .cleanupCenter), "scan center does not traverse cleanup candidates")
    require(policy.usesCandidateReviewFocus(for: .systemCleanup), "system cleanup uses candidate review focus")
    require(policy.usesCandidateReviewFocus(for: .agentEnvironment), "Agent environment uses candidate review focus")
    require(!policy.usesCandidateReviewFocus(for: .applications), "application navigation must not traverse cleanup candidates")
    require(!policy.usesCandidateReviewFocus(for: .dashboard), "overview navigation must not traverse cleanup candidates")

    let expectedScanDestinations: [ScanModuleID: AppDestination] = [
        .general: .systemCleanup,
        .applications: .applications,
        .largeFiles: .largeFiles,
        .agentEnvironment: .agentEnvironment,
    ]
    for (module, destination) in expectedScanDestinations {
        require(
            policy.scanResultDestination(for: module, state: .completed) == destination,
            "completed \(module.rawValue) results must open \(destination.rawValue)"
        )
        require(
            policy.scanResultDestination(for: module, state: .limited) == destination,
            "limited \(module.rawValue) results must remain reviewable"
        )
        for unavailableState in [ScanModuleState.waiting, .scanning, .failed, .cancelled] {
            require(
                policy.scanResultDestination(for: module, state: unavailableState) == nil,
                "\(unavailableState.rawValue) \(module.rawValue) results must not navigate"
            )
        }
    }

    require(
        !policy.showsScanningPlaceholder(
            for: .systemCleanup,
            globalScanIsRunning: true,
            availableModules: [.general]
        ),
        "cleanup center must show its completed general result while unrelated modules continue scanning"
    )
    require(
        policy.showsScanningPlaceholder(
            for: .largeFiles,
            globalScanIsRunning: true,
            availableModules: [.general]
        ),
        "a destination must keep its placeholder until its own module result is available"
    )
    require(
        !policy.showsScanningPlaceholder(
            for: .systemCleanup,
            globalScanIsRunning: false,
            availableModules: []
        ),
        "a stopped scan must not leave a destination in a scanning placeholder"
    )

    for destination in [AppDestination.systemCleanup, .applications, .largeFiles, .agentEnvironment] {
        for state in [ScanModuleState.completed, .limited, .failed, .cancelled] {
            require(!policy.showsModuleScanControls(for: destination, globalScanIsRunning: true, moduleState: state), "terminal modules must hide scan controls while other modules scan")
        }
        require(policy.showsModuleScanControls(for: destination, globalScanIsRunning: true, moduleState: .waiting), "a waiting module must expose cancellation while the global scan is running")
        require(policy.showsModuleScanControls(for: destination, globalScanIsRunning: true, moduleState: .scanning), "a running module must retain cancellation")
        require(!policy.showsModuleScanControls(for: destination, globalScanIsRunning: false, moduleState: .scanning), "stopped scans must hide module scan controls")
    }

    let english = L10n.language == .english
    require(SelectionLabelPolicy.cleanupToggle(name: "Cache", isSelected: false, isBlocked: false) == (english ? "Add Cache to cleanup plan" : "将 Cache 加入清理计划"), "unchecked cleanup label describes inclusion")
    require(SelectionLabelPolicy.cleanupToggle(name: "Cache", isSelected: true, isBlocked: false) == (english ? "Remove Cache from cleanup plan" : "从清理计划移除 Cache"), "checked cleanup label describes removal")
    require(SelectionLabelPolicy.uninstallToggle(name: "Support", isSelected: true, isBlocked: false) == (english ? "Remove Support from uninstall plan" : "从卸载计划移除 Support"), "checked uninstall label describes removal")
    require(SelectionLabelPolicy.cleanupToggle(name: "Credential", isSelected: false, isBlocked: true) == (english ? "Credential, always protected" : "Credential，始终保护"), "blocked label describes protection")
}
