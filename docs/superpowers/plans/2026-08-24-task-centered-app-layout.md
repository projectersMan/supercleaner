# Task-Centered App Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.
>
> **Historical note:** This plan records the layout migration. References to the former separate preview stage have been updated to the current direct-confirmation flow: build an immutable plan, confirm it, then revalidate immediately before real execution.

**Goal:** Replace the scanner-oriented layout with the approved task-centered seven-destination app, removing duplicated concepts and irrelevant actions while preserving the complete safety workflow.

**Architecture:** Keep the existing SwiftUI NavigationSplitView, engine, plan builder, execution-time revalidation, quarantine, and restore layers. Add small presentation policies for navigation, toolbar/action visibility, application filtering, Agent view state, and byte formatting; compose focused page views on the existing AppModel.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, CleanerCore contracts, XCTest.

**Spec:** docs/superpowers/specs/2026-08-24-task-centered-app-layout-design.md

## Global Constraints

- Exactly seven destinations: 概览, 清理中心, 应用卸载, 大文件, Agent 环境, 恢复记录, 设置.
- 开发工具 is not top-level; developer caches belong to 清理中心.
- PlanActionBar only appears in 清理中心, 大文件, and Agent 环境 cleanup view.
- Scan appears only in 概览, 清理中心, 大文件, and Agent 环境.
- Strategies are 推荐, 深度, 手动选择.
- Confirmation is non-mutating; execution revalidates the plan, then moves eligible items into recoverable quarantine.
- Blocked candidates, protected Agent assets, application user data, and shared containers remain unselectable.
- Native SwiftUI controls and SF Symbols only; no dependency or branding expansion.

---

### Task 1: Navigation and contextual shell policy

**Files:**
- Create: Sources/CleanerCore/AppNavigationPolicy.swift
- Modify: Sources/CleanerApp/AppModel.swift
- Modify: Sources/CleanerApp/ContentView.swift
- Create: Sources/CoreContractChecks/AppNavigationContract.swift
- Modify: Sources/CoreContractChecks/main.swift

**Interfaces:**
- Produces AppDestination cases dashboard, cleanupCenter, applications, largeFiles, agentEnvironment, recovery, settings; CleanerApp uses this type directly.
- Produces AppNavigationPolicy.showsScan(for:) and showsPlanBar(for:).

- [ ] **Step 1: Write the failing navigation contract**

    func runAppNavigationContracts() {
        require(AppDestination.allCases.map(\.title) == [
            "概览", "清理中心", "应用卸载", "大文件", "Agent 环境", "恢复记录", "设置"
        ], "task-centered sidebar contract")
        let policy = AppNavigationPolicy()
        require(policy.showsScan(for: .cleanupCenter), "cleanup center scan")
        require(!policy.showsScan(for: .recovery), "recovery has no scan")
        require(policy.showsPlanBar(for: .largeFiles), "large files plan bar")
        require(!policy.showsPlanBar(for: .applications), "uninstall owns its plan")
    }

- [ ] **Step 2: Run ./Scripts/build-app.sh and verify RED**

Expected: approved cases and AppNavigationPolicy are missing.

- [ ] **Step 3: Implement cases, titles, symbols, policy, and conditional ContentView composition**

    struct AppNavigationPolicy {
        func showsScan(for destination: AppDestination) -> Bool {
            [.dashboard, .cleanupCenter, .largeFiles, .agentEnvironment].contains(destination)
        }
        func showsPlanBar(for destination: AppDestination) -> Bool {
            [.cleanupCenter, .largeFiles, .agentEnvironment].contains(destination)
        }
    }

- [ ] **Step 4: Run ./Scripts/build-app.sh and verify GREEN**

- [ ] **Step 5: Commit**

    git add Sources/CleanerCore/AppNavigationPolicy.swift Sources/CleanerApp Sources/CoreContractChecks
    git commit -m "feat: add task-centered app navigation"

### Task 2: Cleanup Center strategy, scope, and copy

**Files:**
- Modify: Sources/CleanerCore/CleanupScopePolicy.swift
- Create: Sources/CleanerCore/ByteFormatting.swift
- Modify: Sources/CoreContractChecks/CleanupModeContract.swift
- Modify: Sources/CleanerApp/AppModel.swift
- Modify: Sources/CleanerApp/ReviewWorkspaceState.swift
- Modify: Sources/CleanerApp/CleanupReviewView.swift
- Modify: Sources/CleanerApp/GuidedCleanupView.swift
- Modify: Sources/CleanerApp/Components.swift
- Modify: Sources/CleanerApp cleanup confirmation UI.

**Interfaces:**
- Produces CleanupMode.displayTitle values 推荐, 深度, 手动选择.
- Produces CleanupScopePolicy.cleanupCenterCandidates(from:), including developer caches but excluding large-file and Agent candidates.
- Produces ByteCountFormatter.cleanerString(bytes:), with nonzero sub-kilobyte values shown as < 1 KB.

- [ ] **Step 1: Extend the failing scope/copy contract**

    let center = CleanupScopePolicy().cleanupCenterCandidates(from: [recommended, developer, large, agent])
    require(center.map(\.id) == [recommended.id, developer.id], "center scope")
    require(CleanupMode.allCases.map(\.displayTitle) == ["推荐", "深度", "手动选择"], "strategy copy")
    require(ByteCountFormatter.cleanerString(bytes: 1) == "< 1 KB", "tiny size copy")

- [ ] **Step 2: Run ./Scripts/build-app.sh and verify RED**

- [ ] **Step 3: Implement scope, labels, formatter, and AppModel callers**

    public func cleanupCenterCandidates(from candidates: [CleanupCandidate]) -> [CleanupCandidate] {
        candidates.filter { $0.source == .general && $0.category != .largeFile }
    }

    public extension ByteCountFormatter {
        static func cleanerString(bytes: UInt64) -> String {
            guard bytes > 0 else { return "0 KB" }
            guard bytes >= 1_000 else { return "< 1 KB" }
            return string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

- [ ] **Step 4: Simplify the page: one title, 方案 picker, one hero total, 手动调整, and real-execution confirmation**

    Text("清理中心").font(.largeTitle.bold())
    Picker("方案", selection: modeBinding) { /* 推荐, 深度, 手动选择 */ }
    Button("手动调整") { model.setCleanupMode(.custom) }
    Button("确认清理") { model.prepareExecutionConfirmation() }

- [ ] **Step 5: Build and commit**

    ./Scripts/build-app.sh
    git add Sources/CleanerCore Sources/CleanerApp Sources/CoreContractChecks
    git commit -m "feat: reshape cleanup center strategies"

### Task 3: Result-oriented Overview

**Files:**
- Modify: Sources/CleanerApp/DashboardView.swift
- Modify: Sources/CleanerApp/AppModel.swift
- Modify: Sources/CleanerCore/CleanupRecommendationPolicy.swift
- Create: Sources/CleanerCore/OverviewSummary.swift
- Modify: Sources/CoreContractChecks/CleanupRecommendationContract.swift

**Interfaces:**
- Consumes cleanup-center scope and recommendation policy.
- Produces before-scan entry and after-scan result hub.

- [ ] **Step 1: Add failing pure-summary assertions for recommended, deeper, large-file, Agent retained, and Agent protected totals**

    let summary = OverviewSummary(candidates: [safeCache, deepCache, large, agentAsset, credential])
    require(summary.recommendedCount == 1, "overview recommended partition")
    require(summary.deepCount == 1, "overview deeper partition")
    require(summary.largeFileCount == 1, "overview large-file partition")
    require(summary.agentRetainedCount == 1, "overview retained Agent partition")
    require(summary.agentProtectedCount == 1, "overview protected Agent partition")

- [ ] **Step 2: Run ./Scripts/build-app.sh and verify RED**

- [ ] **Step 3: Implement OverviewSummary and before-scan title/CTA/trust row**

    public struct OverviewSummary: Sendable {
        public let recommendedCount: Int
        public let recommendedBytes: UInt64
        public let deepCount: Int
        public let deepBytes: UInt64
        public let largeFileCount: Int
        public let largeFileBytes: UInt64
        public let agentRetainedCount: Int
        public let agentProtectedCount: Int
    }

- [ ] **Step 4: Implement after-scan recommendation hero, three opportunity cards, and application link**

    Button("查看推荐方案") { model.selection = .cleanupCenter }
    OpportunityCard(title: "深度空间", action: { model.openDeepCleanup() })
    OpportunityCard(title: "大文件", action: { model.selection = .largeFiles })
    OpportunityCard(title: "Agent 环境", action: { model.selection = .agentEnvironment })
    Button("应用卸载") { model.selection = .applications }

- [ ] **Step 5: Verify actions route to cleanupCenter, largeFiles, agentEnvironment, applications**

- [ ] **Step 6: Build and commit**

    ./Scripts/build-app.sh
    git add Sources/CleanerApp/DashboardView.swift Sources/CleanerApp/AppModel.swift Sources/CleanerCore/CleanupRecommendationPolicy.swift Sources/CoreContractChecks/CleanupRecommendationContract.swift
    git commit -m "feat: make overview a result hub"

### Task 4: Searchable Application Uninstall

**Files:**
- Create: Sources/CleanerCore/ApplicationListFilter.swift
- Create: Tests/CleanerCoreTests/ApplicationListFilterTests.swift
- Modify: Sources/CoreContractChecks/ApplicationContract.swift
- Modify: Sources/CleanerApp/AppModel.swift
- Modify: Sources/CleanerApp/ApplicationsView.swift

**Interfaces:**
- Produces ApplicationListScope: all, uninstallable, running, systemProtected.
- Produces ApplicationListFilter(query:scope:).includes(_:).
- Produces AppModel applicationQuery, applicationScope, visibleApplications, refreshApplications().

- [ ] **Step 1: Write failing filters**

    let filter = ApplicationListFilter(query: "studio", scope: .uninstallable)
    XCTAssertTrue(filter.includes(androidStudio))
    XCTAssertFalse(filter.includes(runningStudio))
    XCTAssertFalse(ApplicationListFilter(query: "", scope: .systemProtected).includes(androidStudio))

- [ ] **Step 2: Run ./Scripts/build-app.sh and verify RED**

- [ ] **Step 3: Implement filter and reconcile selection to first visible app**

    public func includes(_ application: InstalledApplication) -> Bool {
        let matchesQuery = query.isEmpty || application.name.localizedCaseInsensitiveContains(query)
            || application.bundleIdentifier.localizedCaseInsensitiveContains(query)
        let matchesScope = scope == .all
            || (scope == .uninstallable && !application.isRunning && !application.isSystem)
            || (scope == .running && application.isRunning)
            || (scope == .systemProtected && application.isSystem)
        return matchesQuery && matchesScope
    }

- [ ] **Step 4: Add native search, filter, selection, inspector, refresh, and recommendation sheet**

    TextField("搜索应用或 Bundle ID", text: $model.applicationQuery)
    Picker("范围", selection: $model.applicationScope) { /* four scopes */ }
    List(model.visibleApplications, selection: $model.selectedApplicationID) { /* native rows */ }

- [ ] **Step 5: Build and commit**

    ./Scripts/build-app.sh
    git add Sources/CleanerCore/ApplicationListFilter.swift Tests/CleanerCoreTests/ApplicationListFilterTests.swift Sources/CoreContractChecks/ApplicationContract.swift Sources/CleanerApp/AppModel.swift Sources/CleanerApp/ApplicationsView.swift
    git commit -m "feat: add searchable application uninstall"

### Task 5: Honest Large Files and action-oriented Agent Environment

**Files:**
- Modify: Sources/CleanerApp/DiskSpaceView.swift
- Delete: Sources/CleanerApp/AgentWorkspaceView.swift
- Create: Sources/CleanerApp/AgentEnvironmentView.swift
- Modify: Sources/CleanerApp/AppModel.swift
- Modify: Sources/CleanerApp/ReviewWorkspaceView.swift
- Modify: Sources/CleanerApp/Components.swift
- Create: Sources/CleanerCore/AgentEnvironmentSummary.swift
- Create: Sources/CoreContractChecks/AgentEnvironmentContract.swift
- Modify: Sources/CoreContractChecks/main.swift

**Interfaces:**
- Produces AgentEnvironmentSection cleanup/assets.
- Produces AgentEnvironmentSummary reclaimable bytes/count, retained count, protected count, grouped cleanup categories.

- [ ] **Step 1: Write failing Agent summary contract**

    let summary = AgentEnvironmentSummary(candidates: [modelCache, skill, credential], policy: CleanupRecommendationPolicy())
    require(summary.reclaimableCount == 1, "reproducible output")
    require(summary.retainedCount == 1, "retained Agent asset")
    require(summary.protectedCount == 1, "protected credential")

- [ ] **Step 2: Run ./Scripts/build-app.sh and verify RED**

- [ ] **Step 3: Rename and focus 大文件; state Downloads/Desktop scope and remove generic recommendation filter**

    CleanupReviewView(
        model: model,
        destination: .largeFiles,
        title: "大文件",
        subtitle: "下载与桌面中的大型项目，仅供审查，不会自动选择。",
        filterStyle: .searchAndSelection
    )

- [ ] **Step 4: Implement Agent 清理建议 summary view and 环境资产 detailed workbench**

    Picker("Agent 环境视图", selection: $model.agentEnvironmentSection) {
        Text("清理建议").tag(AgentEnvironmentSection.cleanup)
        Text("环境资产").tag(AgentEnvironmentSection.assets)
    }
    // cleanup: AgentEnvironmentSummaryView
    // assets: ReviewWorkspaceView(destination: .agentEnvironment)

- [ ] **Step 5: Gate Agent plan actions to cleanup view and ensure protected assets never imply selection**

- [ ] **Step 6: Build and commit**

    ./Scripts/build-app.sh
    git add Sources/CleanerApp Sources/CleanerCore/AgentEnvironmentSummary.swift Sources/CoreContractChecks
    git commit -m "feat: focus large file and Agent tasks"

### Task 6: Recovery, Settings, and accessibility

**Files:**
- Modify: Sources/CleanerApp/HistoryView.swift
- Modify: Sources/CleanerApp/PermissionsView.swift
- Modify: Sources/CleanerApp/Components.swift
- Modify: Sources/CleanerApp/ContentView.swift
- Modify: Sources/CleanerApp cleanup confirmation UI.
- Create: Sources/CleanerCore/SelectionLabelPolicy.swift
- Create: Sources/CoreContractChecks/SelectionLabelContract.swift
- Modify: Sources/CoreContractChecks/main.swift

**Interfaces:**
- Consumes contextual shell policy.
- Produces state-aware checkbox accessibility labels.

- [ ] **Step 1: Extend the failing accessibility-label contract**

    require(SelectionLabelPolicy.title(name: "Cache", isSelected: false, isProtected: false) == "将 Cache 加入计划", "unchecked label")
    require(SelectionLabelPolicy.title(name: "Cache", isSelected: true, isProtected: false) == "从计划移除 Cache", "checked label")
    require(SelectionLabelPolicy.title(name: "Secret", isSelected: false, isProtected: true) == "Secret 始终保护", "protected label")

- [ ] **Step 2: Implement SelectionLabelPolicy; rename and recompose 恢复记录 and 设置**

    public enum SelectionLabelPolicy {
        public static func title(name: String, isSelected: Bool, isProtected: Bool) -> String {
            isProtected ? "\(name) 始终保护" : isSelected ? "从计划移除 \(name)" : "将 \(name) 加入计划"
        }
    }

- [ ] **Step 3: Implement selected/protected checkbox labels**

    candidate.risk == .blocked
        ? "\(candidate.displayName) 始终保护"
        : isSelected
            ? "从计划移除 \(candidate.displayName)"
            : "将 \(candidate.displayName) 加入计划"

- [ ] **Step 4: Run copy search and build**

    rg -n '智能清理|磁盘空间|开发工具|Agent 工作空间|操作历史|设置与权限|旧预览入口' Sources/CleanerApp
    ./Scripts/build-app.sh

- [ ] **Step 5: Commit**

    git add Sources/CleanerApp Sources/CoreContractChecks
    git commit -m "feat: finish task-centered utility pages"

### Task 7: Full acceptance and documentation

**Files:**
- Modify: docs/superpowers/specs/2026-08-24-task-centered-app-layout-design.md
- Create: docs/superpowers/verification/2026-08-24-task-centered-app-layout.md
- Screenshots: /Users/bytedance/.codex/visualizations/2026/08/24/01a032f6-a9c4-7e12-9e87-e48b62098fbe/task-centered-acceptance/

- [ ] **Step 1: Run automated evidence**

    git diff --check
    ./Scripts/build-app.sh
    rg -n '智能清理|磁盘空间|开发工具|Agent 工作空间|操作历史|设置与权限|旧预览入口' Sources/CleanerApp

- [ ] **Step 2: Inspect seven destinations, three strategies, two Agent views, app filtering/highlight, contextual actions, and AX labels with Computer Use**

- [ ] **Step 3: Capture and inspect one fresh screenshot per destination plus Cleanup Center deep/manual, Agent assets, and uninstall plan**

- [ ] **Step 4: Write requirement-by-requirement verification, including evidence limits and confirmation that no cleanup/uninstall/permission/restore action ran**

- [ ] **Step 5: Commit**

    git add docs/superpowers
    git commit -m "docs: verify task-centered app layout"
