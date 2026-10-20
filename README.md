# SuperCleaner

**The first known macOS system cleaner to include dedicated AI agent workspace cleanup.** SuperCleaner brings AI agent environment discovery into a full Mac cleanup workflow, alongside application leftovers, developer build artifacts, caches, and large files. Review what will change, protect important data, and keep eligible cleanup recoverable.

> System cleanup and dedicated AI agent workspace discovery, with review, protection, and recovery built in.

## Features

- **Find space you can reclaim.** Scan common caches, logs, installers, temporary files, developer artifacts, and large files.
- **Review before cleanup.** See why each item was found and whether it is safe, needs review, or is blocked. App, large-file, and agent results are never preselected for deletion.
- **Clean up with recovery in mind.** SuperCleaner rechecks candidates before acting, moves eligible items into its quarantine, and records the operation so you can restore them later.
- **Uninstall applications carefully.** Review an app and its related files together. Installation ownership and management sources are checked so managed apps can be handed back to their original installer.
- **Inspect project build artifacts.** Find folders such as `node_modules`, `target`, `.build`, `build`, and `dist`, grouped by project. Tracked files, active projects, nested repositories, and sensitive material are protected.
- **Clean up with AI agent workspaces in mind.** Discover environments from tools such as Codex, Claude, Cursor, and Trae as part of the same Mac cleanup workflow. Inspect Skills, MCP configurations, sessions, caches, and project worktrees with resource-aware protections; sensitive configuration values are not collected, and protected workspace content is not silently treated as disposable.
- **Keep control of sensitive paths.** Add files or folders to a persistent protection list that is honored during scanning, planning, and execution.
- **Use a read-only CLI.** Query scan results, candidate details, cleanup previews, history, and project artifacts as JSON. The CLI does not delete files.

## Get started

SuperCleaner currently builds from source. You need macOS 13 or later and Swift 6 (Xcode or the Xcode Command Line Tools).

```bash
git clone https://github.com/<your-account>/SuperCleaner.git
cd SuperCleaner
./Scripts/build-app.sh
open build/SuperCleaner.app
```

Replace `<your-account>` with the GitHub account or organization hosting the repository. For a local build check, run:

```bash
./Scripts/verify-app.sh
```

Local builds may use ad-hoc signing when no stable Apple signing identity is available. This is suitable for development on your Mac; it is not a notarized public release. See the [development guide](docs/development.md) for signing, verification, and release requirements.

## How to use

1. **Open SuperCleaner and start a scan** from the Overview. Grant macOS permissions when a scan needs access to protected locations.
2. **Review the results** in Cleanup Center, Applications, Large Files, Agent Environment, or Project Artifacts. Select individual items to inspect their paths, evidence, and safety status.
3. **Choose what to act on.** System cleanup offers a default selection for eligible system candidates. Applications, large files, and agent workspace items require your explicit selection. Blocked items cannot be added to a plan.
4. **Review the plan and confirm.** SuperCleaner revalidates selected files immediately before execution. Eligible items are moved to quarantine rather than being immediately erased.
5. **Restore or manage completed cleanup** from History. Quarantined items can be restored while they remain available; retention and automatic cleanup settings are managed by the app.

To uninstall an application, open **Applications**, select the app, review its associated items, and confirm the uninstall plan. Some apps are managed by Homebrew, Steam, or another installer and should be removed through that source.

To add a protected path, open **Settings** and add the file or folder to the protection list. Protected paths are excluded from cleanup plans.

## Read-only CLI

The CLI is built into the app bundle at `Contents/MacOS/supercleaner`. These commands return JSON using schema version 1:

```bash
APP="build/SuperCleaner.app/Contents/MacOS/supercleaner"

"$APP" scan --module general --json
"$APP" candidates --json
"$APP" preview --module general --path '/absolute/path/to/candidate' --json
"$APP" history --json
"$APP" projects --json
"$APP" project-preview --path '/absolute/path/to/project/node_modules' --json
```

Omit `--module` from `scan` to scan all supported modules. `preview` and `project-preview` only create a plan; they do not modify files. The CLI has no delete command. Errors are written to stderr and return a non-zero exit code.

## Privacy and safety

Scanning is read-only. Cleanup requires an explicit plan and confirmation, and candidates are checked again before execution. Eligible items are quarantined for recovery. Sensitive agent configuration values such as command arguments, environment variables, headers, and tokens are not included in MCP summaries. Diagnostic reporting is off by default.

The optional privileged Helper is not required for ordinary user-level cleanup. It only supports a limited set of application and recovery operations after explicit setup, system approval, and temporary session authorization. If it is unavailable, the app does not silently escalate privileges.

## Project status

The repository includes source, local build and verification scripts, and release preparation tooling. Formal signing, notarization, public distribution, clean-Mac upgrade behavior, and the production Helper flow still require release-environment validation. See the [production release checklist](docs/production-release-checklist.md) before distributing builds.

For architecture and implementation details, see [Architecture](docs/architecture.md), [Development](docs/development.md), and [Cleanup rule sources](docs/rule-sources.md).
