# Precision Discovery and Progressive Review Design

**Date:** 2026-08-25  
**Status:** Approved for implementation
**Scope:** Scan entry, application discovery, large-file drill-down, Agent environment classification, and expandable cleanup-plan review

## Precedence

This specification refines and supersedes the toolbar, application-discovery, large-file, Agent-environment, and cleanup-selection interaction rules in `2026-08-24-task-centered-app-layout-design.md`. The earlier navigation structure and safety invariants remain in force where this document does not replace them.

## Problem

The task-centered layout is now understandable, but four surfaces still expose results too coarsely or without enough context:

1. A toolbar-only scan symbol appears as a magnifier with a plus and does not explain its purpose.
2. Application search can leave only two visible results without saying that the complete application inventory is merely filtered. Application discovery also stops at the first directory level.
3. Large-file scanning reports top-level directory occupancy, but users cannot see which concrete files create that occupancy.
4. Agent results flatten tens of thousands of files and infer semantics from broad filename substrings. The UI does not organize resources by platform, scope, type, or activity.
5. Recommended and deep cleanup show category totals but do not let users inspect or exclude individual items without switching to manual selection.

The refinement must provide progressive disclosure without turning safe defaults into a long confirmation questionnaire.

## Design Principles

- The Overview owns the single primary full-system scan entry; every result page consumes the same versioned report.
- A module refresh is secondary, available only after a completed full scan, and uses a visible text label.
- A filtered result always shows both the visible count and total count.
- Directories are navigation and aggregation containers; concrete files are the primary large-file review units.
- Semantic classification requires path-boundary and lifecycle evidence, not a loose filename substring.
- Recommended and deep strategies remain usable without review, but every selected category and item is inspectable and reversible.
- Checking an item means inclusion in the current plan, not user certification that the item is safe.
- Protected assets are summarized at useful grouping boundaries instead of flooding the interface with individual files.

## 1. Full-System Scan Entry and Shared Report

Remove `ScanToolbar` and the trailing magnifier-plus toolbar item from the global shell. The native sidebar toggle remains the only global toolbar control. The Overview is the authoritative entry for the first full-system scan, so users never have to guess which page should produce the data consumed elsewhere.

### Overview before the first scan

The first-screen hero contains one large primary button: `开始完整扫描`. Supporting text states that the operation is read-only and covers:

- general cleanup candidates: application caches, logs, temporary files, installers, and developer caches;
- installed application inventory and uninstall protection state;
- concrete large files and directory occupancy in the configured user roots;
- Agent environments, including platform, scope, resource type, lifecycle, and protection classification;
- access coverage, unavailable roots, and ruleset version.

The copy must not claim that every byte on the startup disk is inspected. It says that the app scans all supported and safely accessible locations. The scan does not read document contents, upload data, or perform cleanup.

### Shared report model

One orchestrated read-only scan produces one versioned `SystemScanReport`:

```text
SystemScanReport
  generationID
  startedAt
  completedAt
  rulesetVersion
  moduleStatus: general | applications | largeFiles | agentEnvironment | coverage
  cleanupCandidates
  applicationInventory
  diskUsageRoots
  agentAssets
  coverageSummary
```

Modules run independently under the same generation. The Overview shows a stable progress list for `通用清理`, `应用`, `大文件`, and `Agent 环境`, with per-module waiting, scanning, completed, limited, or failed states. A failed or inaccessible module does not erase successful modules, but an incomplete generation is never silently presented as a fully current report.

Starting a new full scan creates a new generation while retaining the previous completed report. Cancelling leaves that previous report active, labels it with its original completion time, and performs zero writes. When no previous report exists, cancellation returns to the pre-scan state.

### Overview after scanning

Completion stays on the Overview rather than automatically navigating elsewhere. The hero becomes a result hub showing reclaimable bytes, application count, large-file count, Agent cleanup-unit count, completion time, and coverage warnings. Its primary next action is `查看推荐方案`; secondary result cards open `应用卸载`, `大文件`, or `Agent 环境` using the same `generationID`.

The Overview then exposes `重新完整扫描` as a secondary action. Starting it clearly warns that the current report remains usable until the replacement finishes.

### Result-page behavior

- `清理中心` never owns an initial scan action. Without a completed report it shows `尚未扫描` and a primary `返回概览开始扫描`. Recommended, deep, and manual strategies are projections of the same report, not separate scanners.
- `大文件` and `Agent 环境` also show `尚未扫描` with `返回概览开始扫描` before the first report. Afterward, each may offer a secondary `刷新本模块`; this updates only that module under a new report generation and explicitly marks other modules as coming from the previous scan time until the user performs another full scan.
- `应用卸载` receives its initial inventory from the full scan. It may retain `刷新应用` as a secondary inventory-only refresh after a completed report.
- Every result page displays the active report completion time and any coverage limitation. No page fabricates sample results or presents stale results as current.

Any full or module rescan changes the report `generationID`. Existing selection overrides and execution plans bound to an older generation are invalidated. The app explains this once in context instead of failing later during execution.

## 2. Application Discovery and Inventory Clarity

### Discovery

Application discovery recursively walks standard application roots to a bounded depth while treating every `.app` bundle as an atomic result and never descending into its contents:

- `/Applications`
- `~/Applications`
- `/System/Applications`
- `/System/Applications/Utilities`

The walk has a maximum depth of 4 and a maximum directory-entry budget. It ignores symbolic-link loops, deduplicates standardized bundle paths, and retains separate installations when the same bundle identifier exists at different paths.

Unreadable roots do not erase successful results. The inventory records a coverage summary containing roots scanned, roots unavailable, and the total unique applications found.

The initial inventory is collected as the `applications` module of the shared full-system report. `刷新应用` uses the same discovery contract and advances the active report generation rather than maintaining an unrelated hidden cache.

### UI

The application toolbar displays `显示 N / 共 M 个应用`. When a search or scope filter is active, a visible `清除筛选` action appears. Entering the page after a new launch shows all applications.

The selected application remains synchronized with the visible list. If filtering hides the selected application, focus moves to the first visible result. An empty filter result explains that the inventory still exists and offers `清除筛选`.

The list remains a native selected list with application name, bundle identifier, running state, and protection state. Application uninstall planning remains isolated from the general cleanup plan.

## 3. Large-File Discovery and Drill-Down

### Scan model

Introduce a disk-usage tree distinct from cleanup candidates:

```text
DiskUsageNode
  id: standardized path
  url
  kind: file | directory
  ownBytes
  recursiveBytes
  childCount
  modifiedAt
  isReadable
  children: unloaded | loaded([DiskUsageNode]) | unavailable(reason)
```

Default roots are `Downloads`, `Desktop`, `Documents`, and `Movies`. The scanner:

- calculates directory occupancy with cancellation, depth, and entry budgets;
- records concrete files at or above 100 MB;
- keeps directory nodes as expandable navigation containers even when no direct cleanup action exists;
- sorts children by recursive size descending;
- skips symbolic links and reports unreadable branches without following them;
- never marks a large item safe based on size alone.

The initial tree is collected as the `largeFiles` module of the shared full-system report. `刷新本模块` reruns this same scan contract and preserves the other completed module payloads with explicit older timestamps.

`CleanupCandidate` objects are created only for concrete files the user explicitly selects. A directory may be inspected and expanded but is not directly selected in this phase. This prevents a single checkbox from silently including an unknown subtree.

### UI

Use a three-part layout:

1. A compact summary: scanned roots, total analyzed size, and number of large files.
2. A native hierarchical list using disclosure triangles. Single click selects a row; double click or disclosure expands a directory.
3. An inspector showing exact path, file or folder type, own/recursive size, modified date, child count, and safety explanation.

File rows have checkboxes. Directory rows have disclosure controls but no cleanup checkbox. Search matches both visible tree nodes and concrete large files. A breadcrumb appears when the user drills into a directory.

## 4. Agent Environment Taxonomy

### Structured asset record

Introduce an Agent-specific record rather than encoding every concept only through `CleanupCategory`:

```text
AgentAssetRecord
  candidate
  provider: codex | claude | cursor | trae | genericMCP | git | shared
  scope: global | project | shared
  resourceKind
  activity: active | recent | completed | unknown
  cleanupEligibility: recommended | deep | retained | protected
  cleanupUnitURL
```

Resource kinds:

- runtime temporary output
- completed-task cache
- build cache
- package cache
- model cache
- session/history
- sandbox/workspace
- Skill
- MCP definition
- configuration
- credential
- prompt/instruction/knowledge
- source code
- Git worktree
- unknown

### Provider roots

Provider adapters own non-overlapping roots:

- Codex: `~/.codex`
- Claude: `~/.claude`
- Cursor: `~/.cursor` and Cursor application-support roots
- Trae: `~/.trae`, Trae/Trae CN application-support roots when present
- Generic MCP: `~/.config/mcp`
- Git worktrees: recognized project worktree metadata
- Shared/global: `~/.agents` and explicitly shared resources

A standardized path is emitted once. Shared roots are never re-labelled as Codex, Claude, Cursor, or Trae merely because multiple platforms reference them.

The initial Agent inventory is collected as the `agentEnvironment` module of the shared full-system report. An Agent-only refresh advances the report generation while preserving and timestamping unchanged modules.

### Classification

Classification uses exact path components and known directory roles. A filename containing `model` is not sufficient to classify a file as a model cache.

Recommended cleanup requires all of the following:

- the path is inside a known reproducible cache or runtime-output root;
- the asset is inactive;
- file identity is verifiable and not a symbolic link;
- completed-task or age evidence exists where the resource type requires it;
- the cleanup unit excludes configuration, knowledge, credentials, source code, sessions, Skills, MCP definitions, and worktree roots.

Model and package caches default to deep cleanup because they can be regenerated but may have significant download cost. Active, recent, unknown, or user-authored assets remain retained or protected.

Cleanup recommendations operate on meaningful cleanup units such as one completed sandbox cache or one package-cache directory, not thousands of internal files.

### UI

Both Agent views use the hierarchy `平台 → 范围 → 资源类型`.

- `清理建议` initially expands groups that contain recommended or deep-clean units. Each group shows item count and bytes and supports group selection when every child is selectable.
- `环境资产` shows all groups, defaults to collapsed protected groups, and supports provider, scope, resource-kind, and recommendation filters.
- Provider summary chips show Codex, Claude, Cursor, Trae, shared/global, and other detected platforms.
- Active assets display `运行中` and cannot be selected.
- The inspector explains provider, scope, resource type, lifecycle evidence, cleanup unit, retained siblings, and restore behavior.

## 5. Cleanup Center Progressive Review

Remove the visible `方案` label to the left of the segmented control. The control retains an accessibility label of `清理方案`.

Recommended and deep strategies use the same progressive review workspace:

- The hero shows the strategy total and cost statement.
- `计划包含` is a disclosure list of cleanup categories.
- Each category row shows a tri-state checkbox, category name, selected/eligible item count, and selected bytes.
- Expanding a category reveals concrete candidates with native checkboxes, path/evidence summary, size, and recommendation.
- Clicking a concrete item focuses the inspector without changing its checkbox.
- Protected and retained summaries are separate disclosure sections and are never selected.

### Selection semantics

Recommended and deep strategies remain default-selected. Users do not need to open or confirm every category.

The internal state is strategy plus overrides:

```text
CleanupStrategySelectionState
  strategy: recommended | deep | manual
  selectedIDs
  excludedBaseIDs
```

- Choosing recommended or deep rebuilds the eligible base set and clears prior overrides.
- Unchecking an item or category records an exclusion but keeps the current strategy visible.
- A modified strategy displays `已调整` and the current selected total.
- Rechecking restores the item to the strategy base set.
- Manual selection permits arbitrary selectable candidates and remains the only mode that can add retained items.
- Blocked items can never enter `selectedIDs`.
- Any selection change invalidates the pending plan.

The final safety checkpoint is one explicit confirmation of the resulting immutable plan. Real execution then repeats path, identity, activity, rule-version, and expiry checks; there is no repetitive per-item confirmation dialog.

## 6. Interaction and Accessibility

- Disclosure rows expose expanded/collapsed state to accessibility APIs.
- Category checkboxes expose `全部选择`, `部分选择`, or `未选择` through value and label.
- Directory rows announce that they can be expanded and do not imply cleanup selection.
- File rows announce the next checkbox action and exact size.
- Provider, scope, and resource-kind filters are keyboard reachable.
- Search results announce visible and total counts.
- Focus and selection remain separate across cleanup, large files, applications, and Agent assets.
- No essential action is represented by an unlabeled icon-only button.

## 7. Error Handling and Performance

- Every recursive scanner has depth and entry budgets and checks cancellation regularly.
- Partial results remain visible with a coverage warning when a root is unreadable or a budget is reached.
- Large-file children load lazily after the initial occupancy scan where possible.
- Agent providers scan independently so one failed provider does not erase other results.
- UI groups use stable IDs and native virtualization; protected assets are aggregated rather than eagerly rendering every internal file.
- Scan status names the active module and shows elapsed time. Cancellation preserves the last completed report and performs zero writes.
- The report store commits a generation atomically only after module states and coverage metadata are coherent; partially written generations never replace the last completed report.
- Each module payload carries its own scanned-at timestamp so a module-only refresh cannot imply that all other data was refreshed.

## 8. Safety Invariants

- Scanning and expansion are read-only.
- Symbolic links are never traversed for recursive discovery.
- Directories in the large-file browser are not cleanup candidates in this phase.
- Application user data, shared containers, running apps, and system apps remain protected.
- Agent credentials, Skills, MCP definitions, prompts, knowledge, configuration, source code, active sessions, and worktree roots remain protected.
- Unknown Agent assets are retained, never recommended.
- Execution still revalidates path policy, identity, active state, rule version, and plan expiry.
- Cleanup still moves items to quarantine and restore never overwrites an existing path.

## 9. Verification Contract

Implementation is complete only when all of the following pass:

1. Application contracts prove bounded recursive discovery, atomic `.app` handling, path deduplication, partial-root success, and visible/total filter counts.
2. Large-file contracts prove concrete file discovery, directory hierarchy, byte aggregation, symbolic-link avoidance, lazy child loading, and file-only selection.
3. Agent contracts prove non-overlapping provider ownership, Codex/Claude/Cursor/Trae/shared scopes, exact-role classification, lifecycle eligibility, cleanup-unit grouping, and protection invariants.
4. Cleanup selection contracts prove strategy defaults, category tri-state behavior, per-item exclusions without changing strategy, manual additions, and blocked-state enforcement.
5. Scan-flow contracts prove the global toolbar scan item is absent, the Overview is the only first-scan entry, every result page consumes the same generation, completion stays on Overview, cancellation preserves the previous report, and rescanning invalidates prior selections and pending plans.
6. Empty-state contracts prove Cleanup Center, Large Files, Agent Environment, and Application Uninstall route users back to the Overview when no report exists, with no mock or stale data presented as current.
7. Module-refresh contracts prove timestamps and generation changes are visible and unchanged modules remain explicitly older.
8. `Scripts/build-app.sh` builds core contracts, the release app, and helper.
9. Computer Use verifies the Overview primary scan, per-module progress, result-hub transition, shared report timestamps, application counts and clear-filter behavior, large-file expansion, Agent grouping, category expansion, checkboxes, focus, and action-bar scoping without executing cleanup.
10. Fresh screenshots are captured and inspected at a consistent window size for every changed page and important state.

## 10. Implementation Sequence

The work remains one product refinement but is implemented as six independently testable waves:

1. Remove the global scan toolbar item; introduce the versioned shared report store, Overview full-scan state machine, module progress, and result-page empty states.
2. Expand application discovery and connect its inventory and refresh behavior to the shared report.
3. Introduce the disk-usage tree and large-file drill-down, including module refresh semantics.
4. Replace flattened Agent candidates with structured provider/scope/resource records and grouped cleanup units, including module refresh semantics.
5. Add progressive category/item review to recommended and deep cleanup, bound to the active report generation.
6. Verify cancellation, stale-report labeling, selection invalidation, cross-page safety, and UI regression.

Each wave must keep the full build and existing safety contracts green before the next wave starts.

## Out of Scope

- A full-disk treemap or visualization engine.
- Direct cleanup of a whole directory from the large-file browser.
- Permanent deletion or automatic Trash emptying.
- Cloud accounts or synchronization.
- Automatic mutation of Agent configuration, MCP definitions, Skills, worktrees, or source code.
