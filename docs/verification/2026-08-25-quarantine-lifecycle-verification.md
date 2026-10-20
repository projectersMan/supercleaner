# Quarantine Lifecycle Verification

Date: 2026-08-25

## Product semantics

- Plan confirmation is non-mutating; accepted plans enter real execution, which independently revalidates every item before quarantine.
- Quarantine moves content into the app-owned quarantine directory. It is recoverable and still consumes disk space.
- Restore moves quarantined content back to its original path. If that path is occupied, a sibling recovery path is used and nothing is overwritten.
- Permanent deletion removes only content currently owned by a specific quarantine receipt. It is irreversible and is the action that releases the quarantined storage.

## Safety contracts

- Restore and permanent deletion reject paths outside the app-owned quarantine root.
- Restore and permanent deletion also require the quarantine plan ID and candidate ID encoded in the destination path to match the receipt.
- A forged receipt cannot move or delete another quarantine batch.
- Restore validates the destination against the path policy before moving content.
- Permanent deletion requires a second destructive confirmation in the UI.
- Failed restore or deletion items remain quarantined and can be retried.

## History and feedback

- Successful restore and permanent deletion results replace the corresponding quarantined lifecycle state in the atomic history store.
- The recovery page shows in-progress, success, partial, conflict, and failure messages inline.
- Completed items no longer retain an active Restore or Permanent Delete button.
- Each record distinguishes quarantined bytes, restored items, and permanently deleted bytes.

## Verification

- Core lifecycle contracts: PASS
- History replacement and interrupted-write preservation: PASS
- Release app build: PASS
- App and helper signing: PASS
- Recovery page layout and action availability inspected with the existing history record.
- No real restore or permanent deletion action was executed during UI inspection.
