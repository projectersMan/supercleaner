# Interaction and Lifecycle Coherence Design

Date: 2026-08-25
Status: Approved for implementation by the user's request to consolidate and execute the prior changes.

## Goal

Remove contradictory controls and make the three affected workflows coherent:

1. Every visible file checkbox in Disk Space performs the same selection action as the inspector button, and directory rows reliably expand or collapse on double-click.
2. Agent Environment discovers every supported platform fairly and presents a platform-first information architecture rather than allowing Codex to consume the entire scan budget.
3. Quarantined content receives a persisted automatic-deletion deadline, defaulting to 24 hours, with clear countdown, rescheduling, permanent retention, restore cancellation, and safe catch-up processing.

## Disk Space interaction

- A single click selects a row and updates the inspector.
- A double-click on a directory row toggles expansion. A second double-click collapses it.
- The disclosure chevron remains an immediate expand/collapse control.
- A double-click on a file never selects it for cleanup.
- Every readable, policy-valid concrete file displayed in the scanned tree has a cleanup candidate with `review` risk. Size alone never makes the file recommended.
- The row checkbox and inspector action button bind to the same candidate ID and must always show the same selection state.
- Unreadable, active, symbolic-link, or protected files show a protected indicator instead of an actionable checkbox.
- The `>= 100 MB` summary remains a discovery metric, not an eligibility gate for explicit manual selection.

## Agent Environment discovery

Supported platform identities are always visible:

- Codex
- Claude Code
- Cursor
- Trae
- Shared / Global
- Generic MCP
- Git Worktree

The scanner first discovers roots for every adapter. It then traverses detected providers in round-robin order under one global asset budget. No provider can exhaust the budget before the other detected providers receive traversal opportunities.

Each provider exposes coverage:

- `notDetected`: no supported root exists.
- `complete`: all discovered roots completed within budget.
- `limited`: the provider still had queued paths when the global budget ended.
- `unavailable`: roots were detected but could not be read or identified.

The UI is platform-first:

- `All platforms` shows one summary card per supported platform, including zero-result and unavailable states.
- Selecting a platform shows `scope -> resource type -> concrete asset`.
- Cards show asset count, bytes, selectable count, protected count, and coverage.
- View names become `Cleanable content` and `All environment assets`.
- The inspector retains path, lifecycle, eligibility, evidence, and protection boundaries.

## Quarantine retention policy

Available retention choices:

- 24 hours — default
- 2 days
- 3 days
- 1 week
- 1 month (30 days)
- Keep until manually deleted

New quarantine receipts are scheduled using the current default policy at the time the receipt is written. Changing the global default affects future receipts. Each receipt can be rescheduled independently.

The recovery page shows the scheduled permanent-deletion date and a live human-readable countdown. Restoring an item resolves it and therefore cancels its scheduled deletion. Manually deleting it resolves the schedule immediately. Setting a receipt to permanent retention removes its deadline.

Automatic deletion runs:

- when the app starts;
- while the app is running, using a bounded periodic scheduler;
- before the recovery page is presented or refreshed.

If the deadline passes while the app is closed, deletion happens on the next app start. This iteration deliberately does not silently install a persistent login item or LaunchAgent. A signed, user-consented background component can be added later without changing the schedule model.

Every automatic purge uses the same executor safety boundary as manual purge: quarantine root, receipt plan ID, and candidate ID must match. Failures remain quarantined and visible for retry.

## Persistence

`QuarantineScheduleStore` is a separate atomic JSON store keyed by receipt ID. This avoids changing the existing history file format and supports migration of older receipts. Existing unresolved quarantine receipts without a schedule receive the current default policy during bootstrap.

Schedule entries contain:

- receipt ID;
- retention policy;
- scheduled date, or `nil` for permanent retention;
- created/updated timestamps;
- last attempt date and optional failure message.

## Safety and feedback

- Automatic deletion never operates on original paths.
- Restore always wins over a pending schedule because history is reloaded and eligibility is checked immediately before purge.
- Only one recovery lifecycle action may run at a time.
- UI exposes in-progress, completed, deferred, failed, and overdue states.
- No automatic action is described as freeing exact bytes; the UI uses `approximately`, acknowledging APFS snapshots and allocation behavior.

## Verification

- Contract tests cover disk candidate parity, directory interaction state, provider fairness/coverage, retention deadlines, migration, catch-up, restore cancellation, and forged-path rejection.
- Release build, signing, cleanup/restore smoke test, and UI operation checks must pass.
- UI verification may open confirmation sheets and change non-destructive filters, but must not restore or permanently delete the user's real files.
