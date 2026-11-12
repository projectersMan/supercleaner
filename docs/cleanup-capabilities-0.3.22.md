# SuperCleaner 0.3.22 (96): uniform cleanup rules

## Delivered behavior

1. Cache decisions use uniform capabilities: regeneration evidence, contained links, content exclusions and registered-client references. Classification, planning, execution and cleanup UI do not branch on a software name or developer rule ID. Directory conventions and manifest formats remain rule data for discovery and evidence gathering; those names do not authorize deletion.
2. No software-specific cleanup command is added. Runtime caches lacking regeneration/reference evidence follow the same manual-selection rule regardless of their name. There is no executable-command recipe in the rules and no per-tool cleanup action in the executor. Existing repository-format inspection gathers source-ownership facts; the cleanup decision applies the same protected-source rule.
3. A generic manifest reader identifies referenced/unreferenced runtime artifacts. Rule data describes the registry, manifest fields and artifact naming format. Referenced versions remain manual; unreferenced versions can be recommended. Incomplete reference information remains unknown. Metadata is excluded from cleanup and changed references are rechecked before execution. Tests use unrelated names and a different manifest schema to verify that behavior does not depend on a particular product.
4. Shared containers are not retained merely because they are shared. Inventory checks app and nested-extension shared-group declarations. Confirmed containers without an installed or running owner are recommended and preselected; incomplete ownership evidence remains manual. Empty/absent shared-container roots skip unnecessary declaration inspection. A packaged CLI timeout exposed that missing guard; its regression test and CLI check passed after correction. Batch residue validation shares a fresh inventory; final ownership checks remain.
5. Installer preselection no longer requires Desktop/Documents/Downloads or another personal-folder allowlist. Installers in user project/build folders qualify. The restriction still applies to automatic duplicate-copy and extracted-ZIP recommendations. Protected system/application/runtime locations, package contents and symbolic-link escapes remain excluded. Duplicate and extracted-content proofs are unchanged.
6. Inaccessible items are excluded from system-cleanup candidates, visible lists and capacity totals. A read-only deletion-permission preflight also excludes currently non-deletable items. No trial deletion is used to test permissions. No separate inaccessible-items section or skipped-location overview notice is displayed. Internal access diagnostics remain available to the scanner, and final execution still handles permission changes.
7. Old or malformed candidates carrying incomplete-scan evidence cannot become default selections or enter a deletion plan. The executor independently rejects such a plan before moving files. This prevents a UI filter or stale selection from becoming deletion authority.
8. Session metrics use actual successful result bytes. Recommended rows retain the simplified presentation without redundant low-risk badges.

## Read-only observations

The five reported cache entries were visible in their parent directory and were confirmed to be directories owned by the current user. Attempting to enumerate each from the diagnostic process returned POSIX error 1, Operation not permitted. This demonstrates that discovering a name and reading its contents are separate operations. It does not establish the exact privacy-policy cause for the SuperCleaner GUI process, or prove that deletion is allowed or harmless. These entries were not deleted. Apple documents multiple independent access-control mechanisms in its [file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

At observation time, the four reported third-party shared containers had no owner in an inventory of 95 applications with complete shared declarations. The three reported browser artifacts were still referenced by registered projects. The project build DMG passed the expanded installer scope. These are observations, not permanent authorization; execution rechecks current facts.

## Verification

- Debug suite: 157 tests passed, including generic rule/manifest names, referenced/unknown/unreferenced artifacts, shared containers, project-folder installers, unavailable candidates, permission filtering and rejection of stale/forged selections.
- App model self-check passed, including suppression of denied-location overview notices while preserving internal diagnostics.
- Localization source coverage and placeholder checks passed.
- All destructive test operations were limited to temporary fixtures. No real caches, applications or shared containers were cleaned.
- Final release/DMG results are appended below after packaging. The package is a local ad-hoc signed build, not an Apple-notarized distribution.

## Final package verification

- Release build and all 157 release tests passed; core contracts passed.
- Packaged CLI JSON/read-only/configuration checks and helper identity gate passed.
- Packaged preferences/version, scan-cleanup model, cleanup/restore smoke test and activation-refresh self-checks passed.
- DMG integrity, mounted app version 0.3.22 (96), deep signature verification and both bundled rule copies passed.
- Source model was restored to its original Git LFS pointer after compilation.
- Artifact: `build/SuperCleaner-0.3.22-96.dmg`
- SHA256: `6b41f516c9189266bc2965db3aef2c86535cccafabe5f570d28ff7223adccfb8`
