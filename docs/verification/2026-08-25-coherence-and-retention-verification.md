# Interaction, Agent Coverage, and Quarantine Retention Verification

Date: 2026-08-25

## Scope

This verification covers the coherent disk-file selection flow, directory row gestures, Agent provider fairness and platform structure, and automatic quarantine retention introduced by the interaction-and-lifecycle plan.

## Automated evidence

- `Scripts/build-app.sh`
  - Core contract executable built and printed `Core contracts passed`.
  - `CleanerApp` and `CleanerHelper` built in release mode.
  - The app and helper were ad-hoc signed.
- `Scripts/verify-app.sh`
  - App bundle structure and macOS 13 minimum version passed.
  - `codesign --verify --deep --strict` passed.
  - The isolated temporary-directory cleanup/restore smoke flow printed `PASS: smoke cleanup and restore`.
- `git diff --check`
  - No whitespace errors.

## Behavior contracts

- Every concrete file shown in the disk tree receives a manual-review cleanup candidate; directories remain navigation-only.
- Disk candidate materialization reuses the identity captured by the directory scan and performs no second identity traversal.
- One directory click selects; two clicks on a non-empty directory select and toggle expansion; files and empty directories never enter a false expanded state.
- Agent providers are traversed round-robin. A wide Codex root cannot starve detected Claude Code and Trae roots.
- Coverage is explicit for every known provider: complete, limited, unavailable, or not detected.
- Platform summaries keep undetected providers visible and preserve per-provider counts.
- Retention schedules persist atomically; manual retention never becomes due; elapsed schedules become due at their exact deadline.
- Automatic maintenance permanently deletes only executor-owned quarantine content, updates the source history receipt, and removes a fully resolved schedule.
- Quarantine countdown presentation distinguishes scheduled and manual retention.

## Local lifecycle observation

Launching the updated app migrated the existing unresolved quarantine receipt to a new `hours24` schedule. Its `scheduledDeletionAt` is exactly 86,400 seconds after the migration `scheduledAt`, so the legacy record was not immediately deleted on first launch.

## UI operation status

- The updated build launched and immediately showed progress after the full-scan button was clicked.
- The scan was cancelled without mutations after a long-running local pass exposed repeated disk identity materialization; that duplication was then removed and covered by a regression contract.
- The small-file inspector wording was corrected to state that only explicit selection adds the file to the cleanup plan.
- Final post-fix click-through of disk checkbox parity, directory double-click, Agent platform cards, and retention menus could not be completed because macOS locked and Computer Use cannot bypass the lock screen.
- No restore, quarantine purge, or permanent-delete UI action was invoked during visual verification.

## Safety boundary

Automatic maintenance runs while the app is alive and catches up on the next launch. It does not silently install a LaunchAgent. Permanent deletion still passes the quarantine-root, plan-ID, and candidate-ID ownership checks in `CleanupExecutor.purge`.
