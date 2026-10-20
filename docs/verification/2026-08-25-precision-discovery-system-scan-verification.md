# Precision Discovery and System Scan Verification

Date: 2026-08-25

## Automated verification

- `Scripts/build-app.sh`: PASS
  - `CoreContractChecks`: PASS
  - `CleanerApp` release build: PASS
  - `CleanerHelper` release build: PASS
  - App and helper signing: PASS
- `Scripts/verify-app.sh`: PASS
  - App bundle structure: PASS
  - Designated Requirement: PASS
  - Cleanup and restore smoke flow: PASS
- `git diff --check`: PASS
- Stale global-scan copy search: PASS; no user-facing instruction still points to a removed toolbar scan action.

`swift test` is not used in this environment because the installed Command Line Tools SDK does not provide a compatible XCTest runtime. The executable `CoreContractChecks` target covers the core scan, navigation, cleanup selection, Agent safety, planning, execution, restore, helper, and commercial-policy contracts.

## Interactive verification completed

- Overview presents the single prominent `开始完整扫描` entry point.
- The removed global magnifier-plus scan affordance is absent.
- Cleanup Center before a scan presents a clear return-to-Overview action.
- Starting a scan transitions all four modules to scanning state.
- Cancelling a scan returns to the prior stable state without committing partial results.
- No cleanup execution was initiated during UI verification.

## Performance correction verified by contracts and build

- Replaced the stateful filesystem actor bottleneck with stateless, sendable filesystem operations so the four discovery modules can progress concurrently.
- Bounded application, large-file, general-size, and Agent discovery work.
- Application and large-file budget limits remain visible through coverage state.
- Agent discovery now reports a limited module state and explanatory message when its budget is reached instead of silently truncating results.
- Materialized the combined, deduplicated, sorted candidate snapshot once per report generation instead of rebuilding it on every SwiftUI state read.
- Added a candidate ID index for direct lookup.
- Navigation to Overview, Applications, Recovery, and Settings no longer traverses cleanup candidates to reconcile an unused review focus.

## Final interactive performance pass

- Latest build relaunched after signing.
- A complete scan finished in approximately 10.2 seconds on the verification machine and committed one shared result generation.
- Result totals shown after the scan: 95 applications, 8 concrete large files, and 5,000 Agent assets with the budget limitation disclosed.
- Overview-to-Applications and Applications-to-Agent navigation completed and rendered the destination state.
- Switching Agent Environment from recommendations to the 5,000-item structured asset view completed and rendered grouped results.
- The Computer Use driver adds an approximately one-second stabilization wait to UI actions, so its wall-clock action values are not treated as direct product latency measurements. The functional comparison verifies that the destination state changes without the previous repeated candidate reconstruction.
- No cleanup execution was initiated during the performance pass.
