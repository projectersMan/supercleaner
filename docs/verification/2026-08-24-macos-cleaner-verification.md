# SuperCleaner V1 Verification

Date: 2026-08-24  
Historical branch: interaction-safety-workbench
Local artifact: `build/SuperCleaner.app`

> This record preserves evidence from the 2026-08-24 milestone. Statements about the former preview stage have been reconciled with the current direct-confirmation and execution-time revalidation flow.

## Verdict

The native user-space product loop was independently built for this milestone: discovery, evidence classification, review, immutable planning, identity revalidation, recoverable execution, audit history, restore, Agent Workspace analysis, app uninstall planning, permissions, packaging, signing, and fixture-only smoke execution. Signed-rule storage and the privileged Helper were separately built and tested support components; they were not connected to the App runtime.

One production release gate remains external to source implementation:

1. Apple XCTest and production Developer ID/notarization require a matching full Xcode installation. The current machine has Swift 6.3.3 paired with a Swift 6.3.2 macOS 26.5 SDK and no XCTest framework. The deterministic `CoreContractChecks` executable supplies current-machine behavioral evidence; `build-app.sh` automatically runs XCTest when full Xcode is selected.

The local GUI inspection is recorded below. Developer ID/notarization are commercial release gates, not blockers for the locally runnable App requested for this Mac.

## Requirement Matrix

| Requirement | Implementation evidence | Behavioral/runtime evidence | Verdict |
|---|---|---|---|
| Independent native implementation | `Package.swift`; Swift-only `Sources`; no Mole dependency/import; `docs/rule-sources.md` | `rg` finds Mole only in README independence statement | Proven |
| Universal cleanup | `GeneralScanners.swift` cache/log/installer/developer/large scanners | `ScannerContract`; recursive directory occupancy fixture | Proven |
| Agent Workspace highlight | `AgentScanners.swift`; `AgentWorkspaceView.swift` | `AgentScannerContract` protects Skills, MCP, prompts, credentials, sessions and roots | Proven |
| Agent task/cache semantics | Completed-task evidence required for safe sandbox cache; model/package caches review | finished sandbox safe; session review; unknown worktree blocked | Proven, conservative |
| Application discovery/uninstall review | `ApplicationScanner.swift`; `ApplicationsView.swift` | exact Bundle ID collision contract; shared/user data blocked; running IDs from `NSWorkspace` | Proven |
| Three safety states | `RiskLevel`; `PlanItem`; `RiskBadge`; `CandidateRow` | safe selected, review opt-in, blocked cannot be forced | Proven |
| Explainability | Candidate `Evidence`; inspector; source/category/status | All scanner contracts attach evidence; UI compiler gate | Proven |
| Focused review workbench | native `List(selection:)`; independent plan checkbox; shared review workspace | GUI proves row highlight changes only the inspector while the checkbox remains a separate AX control | Proven |
| Review filters | query, risk, selected-only filters; hidden-selection disclosure | GUI search narrows candidates, reconciles focus, and discloses selected items hidden by filters | Proven |
| Protected path boundaries | `PathPolicy.swift` literal + physical validation | traversal/control/root/Agent/symlink/application-scope contracts | Proven |
| TOCTOU defense | exact `FileIdentity` in plan and execution revalidation | changed identity produces zero mutation | Proven |
| Active-use defense | scan active paths and execution-time `NSWorkspace` closure | running application paths blocked; directories never safe by age alone | Proven for application-owned paths; Agent unknown activity remains conservative review/blocked |
| Immutable plan | versions, expiry, action, evidence SHA-256, exact candidate identity | blocked/unknown selections rejected; expired/rule-changed plan zero-write | Proven |
| Non-mutating confirmation | confirmation reviews the immutable plan without changing files | UI confirmation precedes execution; selection changes require a new plan | Proven |
| Execution-time revalidation | `CleanupExecutor` checks plan expiry, rule version, path policy, activity and file identity | rejected or skipped items do not move; real execution does not trust earlier UI state | Proven |
| Recoverable execution | `CleanupExecutor`; app-owned quarantine | actual fixture move, verification, history and restore through App `--smoke-test` | Proven |
| Cancellation | App execution task + executor between-item cancellation | cancelled items recorded `skippedCancelled`; receipt partial | Proven |
| Restore conflict safety | sibling Recovery destination | conflict contract proves original is not overwritten | Proven |
| Atomic history | same-directory temp, synchronize, atomic replace | interrupted commit preserves old history and accepts later commit | Proven |
| Signed rules | Ed25519 signed envelope persisted; every read/rollback revalidates | invalid signature and locally modified valid JSON both rejected | Proven |
| Rule provenance | expanded schema; bundled JSON; `docs/rule-sources.md` | real bundled file loads and every rule has source/fixture | Store proven independently; not wired into scanning |
| Permission degradation | `PermissionStatusService`; contextual settings button | limited mode retains cache scanning and explains affected categories | Proven |
| Typed privileged boundary | finite `HelperOperation`; capability token; XPC; Security caller verification | wrong path, identity, expiry, replay contracts; helper release build | Skeleton proven independently; App installation/connection/call path absent |
| No arbitrary shell | no `Process`, shell, or command-string API in Sources | repository search | Proven |
| Licensing safety rights | signed offline claims; `CommercialFeature.isSafetyRight` | expired trial blocks new cleanup but permits history/restore/helper removal/export | Proven |
| Signed updates | signature, HTTPS host allow-list, version/OS/downgrade/hash validation | tamper, downgrade, artifact mismatch contracts | Proven |
| Native interaction states | eight destinations, focused inspector, filters, final confirmation, progress/cancel, history/restore | SwiftUI release compilation and read-only native GUI acceptance | Proven |
| Runnable `.app` | `Scripts/build-app.sh`; Info.plist; embedded rules/helper | release builds; ad-hoc signature valid; smoke passes | Proven |
| Permanent deletion safety | no permanent-delete filesystem API or UI action | move failure contract proves no trash/delete fallback | Proven |

## Fresh Verification Evidence

`./Scripts/build-app.sh`:

- release `CoreContractChecks`: pass
- release `CleanerApp`: pass
- release `CleanerHelper`: pass
- nested helper and app ad-hoc signing: pass

`./Scripts/verify-app.sh`:

- standard bundle layout: pass
- `LSMinimumSystemVersion = 13.0`: pass
- embedded `Rules/base-rules.json`: pass
- embedded helper: pass
- `codesign --verify --deep --strict`: pass
- App `--smoke-test`: `PASS: smoke cleanup and restore`

The smoke test creates a UUID-scoped directory under the system temporary directory, writes one fixture cache file, scans its identity, builds a plan, moves it to a fixture quarantine, writes/reads an operation receipt, restores it, verifies the original path, and removes only that temporary root.

## Toolchain Evidence

- Compiler: Apple Swift 6.3.3.
- Default SDK: macOS 26.5 built with Swift 6.3.2; incompatible with the installed compiler.
- Compatible local build SDK: macOS 15.5.
- CLT has `Testing.framework` built for the new standard library but no matching standard library/XCTest, so `swift test` is not a trustworthy executable gate on this installation.
- XCTest sources are present for a matching full-Xcode CI/release machine. The build script detects full Xcode and enables that gate automatically.

## GUI Acceptance Record

Status: **Passed on 2026-08-24.**

Observed in the locally built `SuperCleaner.app`:

- The native window launched without a crash.
- The sidebar exposed all eight destinations: Overview, Smart Cleanup, Applications, Disk Space, Developer Tools, Agent Workspace, History, and Settings.
- Smart Cleanup explained the three interaction states: green/default selected, orange/user confirmation, and gray/locked protection.
- Agent Workspace remained a highlighted specialist destination without replacing universal cleanup. Its empty state explicitly covered Codex, Claude, Cursor, MCP, Skills/knowledge, configuration, and Git worktree assets.
- History stated that history and restore remain available regardless of trial or subscription state.
- A read-only scan automatically opened Smart Cleanup and selected the first visible row for inspection.
- Clicking a different row moved native highlight and updated the inspector without changing plan selection.
- The plan checkbox appeared as a separate accessibility element with a specific add-to-plan label; protected checkboxes were disabled.
- Search reduced the visible candidate set, reconciled the focused inspector, and disclosed selected items hidden by filters.
- The non-mutating review surfaced the selected plan before the final confirmation flow.
- Final confirmation showed item count, estimated space, source/path scope, and the five execution-time revalidation checks.
- Changing plan selection invalidated the pending plan, removed confirmation actions, and required rebuilding the plan.
- No cleanup, permission change, helper installation, restore, or final quarantine action was triggered.
- Screenshots were stored outside the repository because the inspector intentionally displays local paths; they are not part of source control.

## Production Release Gates

These are intentionally not represented as locally completed:

- replace example bundle identifiers and requirements;
- full Xcode archive and Hardened Runtime;
- Developer ID Application/Installer signing;
- `SMAppService` registration/removal on a signed build;
- notarization, stapling and Gatekeeper verification on a clean Mac;
- English localization and human review of destructive copy;
- external security, privacy and intellectual-property review.
