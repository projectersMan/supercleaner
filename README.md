# SuperCleaner

**The first known macOS system cleaner to include dedicated AI agent workspace cleanup.** SuperCleaner helps you reclaim disk space while keeping cleanup visible, reviewable, and recoverable.

The Cleanup Center headline is **Reclaim your Mac. Clear the AI clutter.** In Simplified Chinese, it reads **释放 Mac 空间，清理 AI 冗余。**, highlighting disk cleanup and AI resource management.

Before a module has been scanned, its right-hand information area stays blank. Once scanning starts, status and results appear. Each Cleanup Center row reflects its module's current selection: **Recommended Cleanup**, **Manually Selected**, or **Selected** for a mix, with item count and size. Returning from a module updates this information immediately. A separate **Cleaned This Session** line shows that module's successful cleanup total; all six module totals add up to the top-right session total. Selecting items does not increase cleaned totals. Rescanning preserves session totals, while failures, skipped items, and repeated receipts add nothing. Manual selections remain outside **Clean All Recommended** unless already eligible under that module's recommendation policy. Cleaned sizes are logical bytes processed; actual available disk space remains in the sidebar.

## Features

- Scan caches, logs, temporary files, installers, developer artifacts, historical uninstall remnants, and duplicate large files.
- Review evidence and safety status before cleanup. Duplicate Large Files, Agent capability analysis, and Project Artifacts preselect eligible items for your confirmation. Application uninstallations and local AI models require manual selection.
- Plan application uninstallations with related files and installation ownership checks.
- Find project artifacts such as `node_modules`, `target`, `.build`, `build`, `dist`, and project DMG installers, without restricting selection based on running status.
- Review local AI models and download caches by provider, with shared files preserved as needed and every cleanup choice made manually.
- Read the current volume's total, used, and available capacity separately from scan results and cleanup totals. Capacity refreshes every minute and when returning to the app, using a background read that only updates the sidebar.
- Discover Codex, Claude, Cursor, Trae, and other AI agent environments. Inspect Skills, MCP configurations, sessions, caches, and worktrees with protections for sensitive data.
- Quarantine eligible items for recovery, keep an operation history, and protect paths you choose.

## Get started

SuperCleaner requires macOS 13 or later and Swift 6. Clone the repository and build the app:

```bash
git clone https://github.com/projectersMan/supercleaner.git
cd supercleaner
./Scripts/build-app.sh
open build/SuperCleaner.app
```

Each run of `build-app.sh` automatically increments the patch version and build number in [Version.json](Version.json) once before compilation. For an explicitly requested release, pass `--version <version>` to that script; the target must be greater than the current configured version. Subsequent ordinary builds resume patch increments. Separate verification and DMG creation reuse the assigned version.

After building, create and verify the matching versioned DMG:

```bash
version=$(python3 Scripts/version.py resolve | head -n 1)
./Scripts/create-dmg.sh "$PWD/build/SuperCleaner.app" "$PWD/build/SuperCleaner-$version.dmg"
python3 Scripts/check-artifacts.py
```

The configured version is recorded in [Version.json](Version.json). The application bundle [SuperCleaner.app](build/SuperCleaner.app) and versioned DMG are generated in `build/`. Local packaging is not automatically installed or published. See the consolidated [documentation](docs/README.md), [build and verification guide](docs/development.md), and [historical releases](docs/history.md).

The Cleanup Center fits into one page with no vertical scrolling. Three compact safety cards sit below the title. The scan button stays aligned with the title text, with elapsed time to its right; session cleanup totals and the larger **Empty Trash…** button stay on the right. Disk capacity appears below **Tools** at the bottom of the sidebar, using a drive icon and **Disk Space** title above a capacity bar and available space. The sidebar and default cleanup footer share the same opaque system-based background, avoiding tint differences from transparent materials. Six scope rows remain visible. Click any scope row to open its page, including while waiting or scanning. Each active module page has its own Cancel Scan button; Resume Scan reruns only that canceled module and keeps results from the others. This is a module restart, not a filesystem traversal checkpoint. The sidebar and titlebar use the native unified toolbar layout, with the actual build SDK recorded separately from the minimum macOS version.

All six scope pages use the same centered spinner and status text while their own module is waiting or scanning, including rescans with previous results. Completed modules show their results while other modules continue scanning.

**System Cleanup** puts all **Recommended Cleanup** items together in one expanded section, with **Deep Cleanup** collapsed below. Inside each recommendation section, **System** and individual application names sit at the same level, with no extra Applications parent. Expand System or an application to review its items. Items without an identified application owner stay under System. Ordinary app caches and typed logs regain their earlier cleanup recommendations; shared caches, offline content, and WeChat chat files still require individual selection; **Uninstall Apps** remains a separate page.

**Clean All Recommended** uses every currently selected item across all six categories, including manually selected applications, local models, files, and project artifacts. The footer total and execution plan use the same selection; deselecting an item removes it. Cleanup Center rows show Recommended Selected, Manually Selected, or mixed selection totals and a separate session cleanup total. A green checkmark indicates scan completion. Search and list filters do not remove hidden selections from this plan. Overlapping paths are consolidated before counting and execution.

**Empty Trash…** first asks you to confirm permanent deletion, then asks Finder to empty the system Trash. macOS may request permission to control Finder. The app refreshes disk capacity and waits for that read to finish before completing the operation. Successful emptying acknowledges the cleanup total captured when it started, so closing or quitting does not repeat the reminder for that total. Canceling or failing keeps the reminder; later cleanup can trigger it again. Your saved **Don't remind again** preference is preserved.

The **Uninstall Apps** page prepares application rows as needed. Opening it with no selections avoids preparing the entire uninstall batch; safety checks and running-app protection remain in effect.

Uninstall validation no longer shares a 15-second allowance across associated items. Unchanged installation receipt contents are reused, while ownership, references, running status, file identity, and protection checks remain live. Application ownership validation has no fixed 60-second cutoff; Stop can end the wait without allowing a late validation result to move files. Finalization distinguishes saving recovery records, updating Dock icons, preparing Trash, moving items, and refreshing results; stages without measurable item progress use an activity indicator and elapsed time.

After **Empty Trash** succeeds, its button stays disabled for the current session until another cleanup adds items (including zero-byte items). An already empty Trash completes successfully; a Finder error is treated as success only if a separate check confirms the Trash is empty. Ollama model recovery snapshots use the transaction's internal path checks, so the protected SuperCleaner support directory no longer blocks legitimate model cleanup or recovery. Shared model files are included once when every referencing model/tag is selected. The executor removes the selected manifests first, then rechecks remaining references immediately before moving each shared file. A failed model removal or newly added reference keeps the required file protected.

## Architecture and scan scopes

The SwiftUI app uses [CleanerCore](Sources/CleanerCore) for discovery, safety checks, cleanup plans, execution, and recovery. The optional [CleanerHelper](Sources/CleanerHelper) handles authorized application operations. Browsing pages or returning to the app does not send privileged file operations; see the [Helper lifecycle and activation audit](docs/helper-activation-audit.md). The standalone `supercleaner` command has been retired and is no longer embedded in the app; [CoreContractChecks](Sources/CoreContractChecks) remains a development verification tool.

| Scope | Contents and selection |
| --- | --- |
| System Cleanup | Caches, logs, installers, and verified historical app remnants; eligible items can be suggested for cleanup. |
| Applications | Installed apps and their related items; uninstall selection is manual. |
| Duplicate Large Files | Large files, verified identical copies, extracted ZIPs, and eligible installers. |
| Agent Environment | Skills, MCP configurations, sessions, caches, and worktrees; capability analysis can suggest eligible items. |
| Local AI Models | Model and dataset storage grouped by provider; no default selection. |
| Project Artifacts | Dependencies, build output, and project DMGs grouped by source project; preselection is controlled in Settings (on unless explicitly disabled), including Git-tracked artifacts. |

The data flow is **read-only scan → candidates with paths, evidence, and coverage → selection → reviewed plan → live safety checks → cleanup receipt and recovery**. Local AI Models and Project Artifacts use this same execution and recovery flow; project defaults appear in Cleanup Center only when their Settings option is enabled; local model choices remain manual and excluded from Clean All Defaults.

**Project Artifacts** has **All / Protected / Selected** scopes. Settings includes **Preselect project build artifacts (including Git-tracked items)**, initially off. When enabled, eligible artifacts are checked after scanning and appear in Cleanup Center; the page opens in Selected, or All if nothing is selected. Turning it off removes automatic choices and preserves manual choices, while excluding projects from Clean All Defaults. Git-tracked items can be selected manually when other safety checks pass. Running or unknown activity does not restrict project selection or deletion. Unknown Git state, credentials, unmanaged nested repositories within a directory, incomplete inspection, and protected paths still prevent cleanup.

**Local AI Models** opens in **Cleanable**, or **All** when that scope is empty, and always starts unselected. Cleanable indicates that safety checks permit manual selection, not that the model is unneeded. Both resource pages follow the app and large-file review layout: a search field, scope filters, sorting and counts above a full-width grouped list. **Select All** applies to eligible visible items. Filters wrap on narrower windows and preserve selections. Expand a provider or project, then right-click an item to open it in Finder or permanently protect its path. Navigation and unrelated scan updates retain your choices; rescanning that resource module reapplies its defaults.

**Local AI Models** checks ten common locations for seven providers. Hugging Face repositories stay together; LM Studio is grouped by model; Ollama lists each model by name and tag and supports individual selection. Shared files used by retained models are preserved; cleanup totals count each removable file once. Models do not detect or display running status, and tool processes do not restrict manual deletion. Each retained Ollama model has independent APFS recovery snapshots, so permanently cleaning a later batch cannot break an earlier model's recovery. Unknown manifest layouts or filesystems without clone support cannot be cleaned through this flow. Keras is limited to model and dataset subdirectories, and GPT4All discovery is limited to recognized model files. Custom model storage outside these locations is not discovered by this module.

| Provider | Locations under your home directory |
| --- | --- |
| Hugging Face | `.cache/huggingface/hub` |
| LM Studio | `.lmstudio/models`, `.cache/lm-studio/models` |
| Ollama | `.ollama/models` |
| PyTorch | `.cache/torch/hub/checkpoints` |
| Whisper | `.cache/whisper` |
| Keras | `.keras/models`, `.keras/datasets` |
| GPT4All | `Library/Application Support/nomic.ai/GPT4All`, `.cache/gpt4all` |

Credentials, unreadable content, unsafe paths, or incomplete inspection keep affected resources protected. Candidate paths and their ancestors must not be symbolic links. Links inside a selected repository or library move with it; their targets are neither traversed nor counted again. Files and directories are checked again immediately before moving; identity changes or failed safety checks stop cleanup of that item. Cleanup may require downloading models again later.

**Project Artifacts** means dependencies or generated output belonging to a source project, identified by a project manifest such as `package.json`, `Cargo.toml`, `Package.swift`, or `pyproject.toml`. Examples include JavaScript dependencies in `node_modules`, Rust output in `target`, Swift output in `.build`, and generated `build` or `dist` directories. A familiar directory name alone is insufficient evidence. Open **Settings → Project Scan Folders** to add multiple source roots, remove entries, and **Save Scan Folders** or **Discard Changes**. The list shows three rows and scrolls internally for additional folders; every saved entry is scanned. Removing an entry only changes the scan scope. Saving refreshes only Project Artifacts when scan results exist; otherwise it saves the scope for the next scan. Both resource pages omit header action buttons; start scans from Cleanup Center. The default roots cover common project locations and supported Agent worktree containers.

Review each project's evidence before choosing an artifact. Git-tracked artifacts can be selected manually after other checks pass; optional preselection is controlled in Settings. Unmanaged nested repositories inside a directory, credentials, unknown Git state, and incomplete checks remain protected. Project running status is neither detected nor displayed, and does not block selection or deletion. Git-ignored content is not proof that it is disposable. Removing dependencies or output can require a new install or build, and generated folders can still contain files you need.

Project Artifacts lists a cleanable build folder once and omits separate DMG rows already covered by that folder. DMGs at the project root remain separate; a protected parent folder does not hide an individually cleanable DMG. Search, Select All and the default queue use the same represented items, while raw scan records retain ownership and validation evidence.

Project artifact checks distinguish public-key PEM files from private or ambiguous key material. Public-key-only PEM files do not lock the directory. SwiftPM dependency checkouts recorded as remote source-control checkouts in the build workspace state do not lock `.build`; unrecorded or edited repositories remain protected. These checks are repeated before cleanup.

The sidebar capacity bar reads the filesystem containing your home directory. It shows used capacity in the bar and currently available space underneath, and refreshes on startup, scanning, cleanup, recovery, and Empty Trash; it also refreshes every minute and when the app becomes active again. An unsuccessful read shows an error instead of zero capacity. Available capacity does not include estimated purgeable space. Scan sizes and **Cleaned This Session** are logical file bytes; moving content to Trash or Recovery does not establish how much physical disk space was released.

**Duplicate Large Files** opens in **All Large Files** (the left option), with **Duplicate Large Files** on the right. **By directory** is the default: Recommended Cleanup appears first, followed by full-path headings with matching files directly beneath them. Directory groups adapt to shared path structure: cohesive branches separate when their common prefix justifies a heading, sparse siblings stay together, and single-child paths compress. There is no group-count or directory-depth limit; independent home branches remain separate. Search preserves group paths; checkbox changes do not move files between groups. Click a directory heading or its arrow to collapse or expand it. The group checkbox selects its visible, readable, selectable files; a partial check becomes fully selected, and a full check clears the group. Search-hidden items and other groups retain their choices. Recommended Cleanup supports the same controls. Right-click any directory heading to access Expand All and Collapse All. The filter bar has one Select All control and one selectable/total count, without a duplicate total-file count. See the [grouping rules](docs/history.md). The same scan preselects one copy per verified identical group, ZIPs verified against sibling folders, and eligible large installer files (`.dmg`, `.pkg`, `.mpkg`, `.xip`, `.iso`). Protected, active, and retained files are excluded from installer preselection. A matching sibling folder must have a total logical file size at least as large as both the current threshold and the ZIP. Individual members can be any size, and every member must match. Review the reason and any retained path before confirming cleanup. See the [scan and cleanup workflow](docs/history.md).

To change installer preselection, go to **Settings → Duplicate Large Files → Preselect large installer files**. It is on by default. Changes apply the next time you scan or refresh large files. Installers remain available for manual selection, and verified duplicate and extracted ZIP defaults still apply.

Agent environment scans use the bundled Google EmbeddingGemma 2 model to analyze directional capability containment: Skill against other Skills, and MCP against other MCP configurations. Skills and MCP use the same default 85% threshold, configurable in Settings. When the union of capabilities provided by other items of the same type reaches that threshold, eligible items are preselected. Existing file protections remain in force, covering items are retained, and deletion still requires your manual confirmation.

**Agent Environment** automatically opens in **Selected** when the current Skill/MCP type and platform have selected items, and **All** when that list is empty. Until you choose a display filter yourself, this follows later preselection and type/platform changes. A manually chosen **All** or **Selected** remains in effect, including an empty Selected list. **Duplicate Large Files** already defaults to **All Large Files** and now provides a tri-state **Select All** control for readable, selectable files visible under the active search and All/Duplicate scope.

The Agent page keeps the original inventory, paths, checkboxes, grouping, and filters. Each row ranks up to three other items by how much of the current item they cover, with names and paths to distinguish copies. Hover over an individual Top 3 item to see its complete path, including the parts truncated in the list. The combined coverage summary is omitted from the interface. The internal calculation uses all other items, not just the displayed three: 86 distinct descriptions covered out of 100 means 86%, which meets the default 85% threshold. Overlapping coverage is counted once. All extracted capability descriptions are retained; reference lists are excluded and long descriptions are split without a 64-item sampling cap. These are estimates from scanned descriptions, not a count of verified runtime functions. After upgrading from the old analysis policy, use Recalculate all containment to replace old scores.

Regular scans reuse known items and relationships by stable identity without checking for content changes. Only new items are embedded and paired with known items of the same type. Use **Settings → Agent capability analysis → Recalculate all containment** to rescan Agent resources and rebuild all current data, including changed items. Changing the threshold reuses cached results.

The app retains its original macOS 13 requirement. Only Agent capability analysis requires macOS 14 or later on Apple Silicon; its bundled inference process loads the model separately from the app. The approximately 310 MB Q8 model is bundled under Apache License 2.0, so the first scan needs no model download. The local containment index is `~/Library/Application Support/SuperCleaner/agent-containment-index.plist`. MCP configurations use safe server names and any existing local purpose descriptions as capability clues; analysis does not connect to MCP services or read credentials, environment variables, command arguments, or headers. Names alone provide limited capability information. Analysis and preselection follow the same calculation for both types and never delete files automatically.

To run the local build verification:

```bash
./Scripts/verify-app.sh
```

Local builds use ad-hoc signing by default, so each Mac can compile and package the app without sharing a certificate or private key. Rebuilding can require macOS privacy authorization again, even when replacing the app at the same path. To intentionally use a fixed certificate, set `SUPERCLEANER_REQUIRE_STABLE_SIGNING=1` and configure the identity as described in the [build guide](docs/development.md). Production distribution still requires the existing Developer ID and notarization gates.

## How to use

Clicking the SuperCleaner Dock icon reopens the main window after it was closed with the red close button, and restores it if it was minimized. Returning to an existing window does not refresh disk capacity; startup, scanning, cleanup, recovery, and Empty Trash continue to update it.

The app list initially shows Uninstallable. The three scopes are mutually exclusive: macOS system apps appear in Protected regardless of running state; other running apps appear in Running, and other stopped apps appear in Uninstallable. All shows the complete inventory. Third-party apps, including user-installed input methods, are not classified as protected because of static file permissions. In Running, select an app to quit it; after it exits, it moves to Uninstallable, where you can select its uninstall items. Relaunching an app moves it back to Running and clears its uninstall selection. Actual permission denials during uninstall offer the relevant authorization or System Settings guidance. Search follows the selected scope, and an empty filtered result explains how to search the full list.

Application icons use native macOS artwork, resolved through the existing cache for the first rendered row without a placeholder-to-icon task. Embedded helpers with only a generic icon inherit the nearest enclosing application’s icon. Local updates replace `/Applications/SuperCleaner.app`; open that installed copy after an update.

Cleanup Center keeps six clickable scan rows with right-aligned recommendation information and the same hover highlight as the application list. Cancel and Resume remain inside each module page. Finished scans show a green checkmark beside the selection and session cleanup information, while their original coverage and cleanup protections are retained. The three capability cards share the height of the tallest content and align at the top.

The Agent page shows its analysis status directly above the inventory. Each analyzed item shows up to three covering peers and their paths; the combined summary is omitted from the interface. If an upgrade changes the analysis rules, the previous index is not reused: the page explains that **Settings → Recalculate all containment** is required. Eligible default selections appear after analysis finishes; no selections can also be a valid result when coverage is below your threshold or existing file protections apply.

Full scans start directly without a permission setup window. On first launch, an app without verified Full Disk Access shows one short reminder with a System Settings link; an already configured app skips it. The reminder is remembered across restarts and does not represent an authorization grant.

App scans quietly skip locations that deny read access, without reporting those expected skips as a regional permission warning. Results cover accessible locations; skipped content remains protected from cleanup. System, application, large-file, and Agent app scans and application refresh do not stop at a fixed entry count. Local AI Models and Project Artifacts keep their own inspection budgets; incomplete checks retain protection. Other applicable time and content-size limits still apply, and scans can be canceled. Other failures remain visible. System Settings links remain in the app’s Settings page.

Permissions and the optional helper remain in Settings. The first scan preflights known locations once if Full Disk Access is not available; later scans do not repeat this setup. macOS still enforces access and may request its own confirmation when needed.

The Uninstall Apps search and filter bar uses the same compact spacing and vertical placement as Duplicate Large Files, while retaining scope, sorting, and application counts. Completed application analyses omit the repetitive success badge; protection and incomplete-analysis indicators remain visible.

1. Open SuperCleaner and start a full scan from **Cleanup Center**. Grant macOS permissions when prompted for protected locations.
2. Review findings in **Cleanup Center**, **Uninstall Apps**, **Duplicate Large Files**, **Agent Environment**, **Local AI Models**, or **Project Artifacts**. Historical uninstall remnants appear in **Cleanup Center**: orphaned caches and verified empty residual directories with complete Bundle ID and application-inventory evidence can be suggested for cleanup, while non-empty application-support data stays in suggested retention for review. Select an item to inspect its path, evidence, and safety status.
3. Choose what to include. Eligible system cleanup items, large files, and Agent analysis findings may be preselected for review. Local models open in Cleanable (All if empty) and always start unselected. Projects open in Selected (All if empty); their optional preselection is controlled in Settings and starts off. Cleanable means selectable after safety checks, not that a model is unneeded. Application uninstall requires manual selection. Blocked items cannot be selected.
4. Review the cleanup plan and confirm. SuperCleaner checks selected items again before acting. By default, items move to macOS Trash after safety checks and record saving. Choose a retention period in **Settings** to keep items in Recovery first.
5. Open **Recovery** to review completed operations and restore retained items while they remain available. Recovery and Trash contents are excluded from large-file results and their totals.

When **Cleaned This Session** includes a positive amount that has not been acknowledged, closing the main window or quitting uses the shared **Empty Trash** confirmation and executor. The window-close reminder also offers **Don't remind me again**; this disables automatic close/quit reminders without treating the Trash as emptied. Restore reminders in **Settings → Cleanup Reminders**. Manually clicking **Empty Trash…** always confirms and has no suppression checkbox. When explicitly quitting, **Cancel** keeps the Trash untouched and lets the app quit. Choosing **Empty Trash** waits for the operation, disk refresh and any failure message to finish, then quits even if emptying failed. Closing only the window leaves the app and scans running in the background; Cancel there only cancels emptying. Successful emptying acknowledges its starting total; canceling or failing does not. Emptying Trash does not remove files retained in Recovery.

Scanning does not block **Empty Trash**. The manual button and window-close confirmation can start emptying immediately while existing scans continue; every displayed confirmation has an enabled **Empty Trash** action. If cleanup itself or another exclusive operation is still finishing, the app keeps one pending reminder until that operation ends. No successful cleanup means no automatic reminder. Once the app has committed to a full quit, the ensuing window-close events do not show another reminder.

To uninstall an app, open **Applications**, select it, review its related items, and confirm the plan. Apps managed by Homebrew, Steam, or another installer should be removed through that source. Add paths to the protection list in **Settings** to exclude them from cleanup plans.

## Privacy and safety

- Scanning is read-only. Cleanup requires a reviewed plan and explicit confirmation.
- Selected items are revalidated before execution; eligible items go to quarantine for recovery.
- Agent summaries do not collect sensitive MCP values such as command arguments, environment variables, headers, or tokens.
- Diagnostic reporting is off by default.
- The optional privileged Helper requires explicit setup, system approval, and temporary session authorization. If it is unavailable, SuperCleaner does not silently escalate privileges.
- Licensed under **GNU GPL v3.0 only**. See [LICENSE](LICENSE) for the complete terms.

Agent 默认选择优先保留用户主目录 `.agents` 中的共享源，独立重复副本沿用包含阈值；`.agents` 不代表所有 Agent 自动加载。Skill目录、manifest、MCP配置或其父目录为软链接时，不进入清单、Top 3、覆盖分析或预选；断链也排除。可独立发现的真实目标仍保留，不修改链接或目标。主目录 `.cache` 中通过清理资格检查的 Skill/MCP 无需重叠即可预选，用户明确保留优先；扫描不会自动删除，仍需确认。覆盖排名展示前3名；当前Skill/MCP与覆盖对象分左右两栏，标签、路径与大小紧随左栏描述，不显示Combined Coverage。预选仍累计全部来源。

应用卸载筛选栏与大文件页保持相同字号及上下间距；搜索框固定260 pt，四项筛选固定等分，切换范围时不会挤动控件；窄窗口自动分为两行。移除Refresh Apps按钮。

清理中心全扫描按钮下方显示本轮扫描用时（时:分:秒），从点击全扫描实际启动本轮任务计时，包含必要预访问、六个模块和Agent分析；全部结束后保留最终用时，重新全扫描清零。取消或失败后无任务时冻结，继续被取消模块则从本轮原始起点继续计时。

点击全扫描直接开始，不再打开大权限配置窗口。首次启动且尚未验证完全磁盘访问时，只显示一次简短提醒；已有磁盘访问的用户不显示，提醒记录跨重启保留。设置页继续提供FDA、App管理与可选Helper的系统入口。首次扫描未确认FDA时会在并行扫描前进行一次只读预访问，之后不重复；系统仍对实际访问独立检查。Top 3中的其他Skill位于各平台分组，软链接不作为另一份Skill。

权限状态在首次提醒判定、每次扫描开始和进入/返回设置页时刷新；提醒记录不代替授权结果。依次检查用户和系统专用保护目录，任一个可访问即可确认探测可用；拒绝、缺失和一般错误保持原有分类。App管理显示“执行卸载时由系统确认”，扫描中的拒绝和系统保护仍静默跳过。

Agent 页的 Skill 与 MCP 条目使用与大文件相同的细横线分隔；高亮、鼠标命中和横线使用同一内容边界，避免List行内边距造成错位。分组、两栏信息、悬停颜色和勾选方式保持一致。

Skill 与 MCP 使用相同的覆盖信息右栏：固定360 pt，标题、名称与路径左对齐，百分比独立列对齐；左栏允许随窗口收缩，切换类型不改变右栏起点。MCP每行不再重复显示服务器数量，顶部配置和服务器定义总数保留。权限页的Available仅表示FDA只读探测可用；App管理显示卸载时由系统确认，不以未显示Available推断未授权。

Project-owned DMG files appear under **Project Artifacts**, including installers found in build output; downloaded DMGs outside discovered projects remain under **Duplicate Large Files**. A selected build directory covers its DMG children in the execution total. Git-tracked, protected, or in-use installers remain protected. The two resource pages have no header action buttons; configure project scan folders in Settings and start scans from Cleanup Center.

Project DMG ownership is checked against the saved project roots and manifests before publishing large-file results. Project installers never appear temporarily in the large-file cleanup total; Project Artifacts performs their own content verification and preserves retained-copy constraints.

系统清理已追溯到 0.3.35 的统一手动选择变更：恢复 0.3.30 普通应用缓存与日志的推荐资格，保留共享缓存、离线内容及微信聊天文件的手动限制。两级分组为建议清理/保留 → System/具体应用，默认展开清理、折叠保留。历史依据与回归验证见 [修复记录](docs/history.md)。


Documentation and reusable checks are indexed in [docs/README.md](docs/README.md) and [Tests/README.md](Tests/README.md). Historical plans, duplicated scripts, and validation logs are preserved in one hash-verified [archive](docs/history.md).
