# Codex and Claude Code: MCP and skill filesystem rules

Research date: 2026-10-15 (Asia/Shanghai)

Scope: local macOS/user/project filesystem locations and discovery rules for OpenAI Codex and Anthropic Claude Code. Sources are limited to current first-party documentation and first-party GitHub repositories. Paths beginning with `~` resolve to the macOS user's home directory (normally `/Users/<user>`).

## Executive summary

| Product | Facility | User/personal location | Project location | Important discovery/precedence rule |
|---|---|---|---|---|
| Codex | MCP | `$CODEX_HOME/config.toml`, default `~/.codex/config.toml` | `.codex/config.toml` at each active layer from project root to CWD | CLI/desktop/IDE share the layers; project layers load only for trusted projects; closest project file wins |
| Codex | Skills (current documented convention) | `$HOME/.agents/skills/<name>/SKILL.md` | `.agents/skills/<name>/SKILL.md` at each directory from project root through CWD | All ancestor skill roots in that interval are scanned; same-name skills are not merged |
| Codex | Skills (compatibility/current implementation) | `$CODEX_HOME/skills/<name>/SKILL.md` (explicitly deprecated in source); bundled skills at `$CODEX_HOME/skills/.system/` | Each active project `.codex/` config layer also contributes `.codex/skills/` | This behavior is in current `openai/codex` source but is not all surfaced on the current skills documentation page |
| Claude Code | MCP local | `~/.claude.json`, nested under the current project's absolute path | Not a project file; this is private per-project state in the user file | `local` is the default scope and outranks project and user |
| Claude Code | MCP project | — | `<project-root>/.mcp.json` | Intended for version control; interactive sessions require approval |
| Claude Code | MCP user | `~/.claude.json` top-level user scope | — | Available to all local projects; lower priority than local and project |
| Claude Code | Skills | `~/.claude/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md`, including nested directories | Startup scans CWD and ancestors to repository root; descendants load on first file access; personal beats project on a name collision |

## OpenAI Codex

### Configuration and MCP

1. `CODEX_HOME` is Codex's local-state root and defaults to `~/.codex`. The normal user configuration is therefore `$CODEX_HOME/config.toml`, normally `~/.codex/config.toml`. The same state root can also contain `auth.json` (when file-based credential storage is selected), `history.jsonl`, logs, and caches. [OpenAI: Advanced configuration, “Config and state locations”](https://developers.openai.com/codex/config-advanced#config-and-state-locations)

2. Project configuration is `.codex/config.toml`. Codex walks from its detected project root to the current working directory and loads every such file; nearer-to-CWD values take precedence. Project `.codex/` layers are skipped for untrusted projects. [OpenAI: Config basics, “Configuration precedence”](https://developers.openai.com/codex/config-basic#configuration-precedence) and [OpenAI: Advanced configuration, “Project config files”](https://developers.openai.com/codex/config-advanced#project-config-files-codexconfigtoml)

3. On Unix, the optional system layer is `/etc/codex/config.toml`. The current documented order, high to low, is CLI flags/`--config`, project `.codex/config.toml` layers, selected profile file (`~/.codex/<profile>.config.toml`), user config, cloud-managed defaults, `/etc/codex/config.toml`, then built-ins. [OpenAI: Config basics](https://developers.openai.com/codex/config-basic#configuration-precedence)

4. Ordinary Codex MCP declarations live in those `config.toml` layers under `[mcp_servers.<server-name>]`. The default user file is `~/.codex/config.toml`; a trusted project may declare the same shape in `.codex/config.toml`. The ChatGPT desktop app, Codex CLI, and Codex IDE extension share this configuration. [OpenAI: MCP](https://developers.openai.com/codex/mcp#connect-codex-to-an-mcp-server)

5. A project-root `.mcp.json` is **not** the documented ordinary Codex project-MCP file. `.mcp.json` is used in Codex's plugin/package compatibility format, whereas direct local Codex configuration is TOML. Do not conflate this with Claude Code's project `.mcp.json`. [OpenAI: package a plugin](https://developers.openai.com/plugins/build/plugins) and [OpenAI: MCP](https://developers.openai.com/codex/mcp#configure-with-configtoml)

6. MCP OAuth storage is only partly specified publicly. Current docs say stored OAuth credentials are used by default, but do not name a dedicated MCP-token file. They do state that a pre-registered confidential client's secret is written to `mcp_servers.<name>.oauth.client_secret` in `config.toml`, so it must not be committed. General Codex credentials may be in the OS keychain/keyring or `$CODEX_HOME/auth.json`; that general statement does not prove where every MCP OAuth token is stored. [OpenAI: MCP, OAuth client registration](https://developers.openai.com/codex/mcp#oauth-client-registration-and-callbacks) and [OpenAI: Advanced configuration](https://developers.openai.com/codex/config-advanced#config-and-state-locations)

### Skill locations and discovery

The current public convention is:

- Repository: `.agents/skills/<skill-name>/SKILL.md` in every directory from the current working directory upward to the detected repository root.
- User: `$HOME/.agents/skills/<skill-name>/SKILL.md`.
- Admin/system-wide authored skills: `/etc/codex/skills/<skill-name>/SKILL.md`.
- System skills: bundled by OpenAI.
- Skill-directory symlinks are supported. If two skills have the same declared name, Codex does not merge them; both may appear in selectors.

Source: [OpenAI: Build skills, “Where Codex loads local skills”](https://developers.openai.com/codex/skills#where-codex-loads-local-skills).

The current `openai/codex` implementation at commit [`ac9db7d8`](https://github.com/openai/codex/commit/ac9db7d8b556c7c34a73793aed34b1f980a4fe39) confirms and extends that table:

- It loads `$HOME/.agents/skills` separately from `CODEX_HOME`. Therefore changing `CODEX_HOME` does **not**, by itself, relocate the current canonical user root `$HOME/.agents/skills`. [source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/ext/skills/src/host_roots.rs#L95-L113)
- It still loads `$CODEX_HOME/skills` and labels it “Deprecated … kept for backward compatibility.” With the default `CODEX_HOME`, this is `~/.codex/skills`. [source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/ext/skills/src/host_roots.rs#L95-L107)
- Bundled system skills are materialized under `$CODEX_HOME/skills/.system`. [source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/skills/src/lib.rs#L60-L85)
- Every active project config layer contributes its `.codex/skills` directory: the project layer's `config_folder` is its `.codex/` directory, and the skill loader appends `skills`. [config-folder source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/config/src/state.rs#L218-L230), [skill-root source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/ext/skills/src/host_roots.rs#L80-L101)
- Separately, it scans `.agents/skills` in every directory between project root and CWD, inclusive. [source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/ext/skills/src/host_roots.rs#L137-L183)

The official repository's bundled `skill-installer` and `skill-creator` still default to `$CODEX_HOME/skills` even though the runtime source labels that user location deprecated. This is a tooling/documentation transition, not evidence that `$CODEX_HOME/skills` has stopped working. [skill-installer source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/skills/src/assets/samples/skill-installer/SKILL.md#L46-L58), [skill-creator source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/skills/src/assets/samples/skill-creator/SKILL.md#L151-L182)

### Project-root semantics

- Codex's default project-root marker is `.git`. `project_root_markers` can replace that list, and an empty list disables the ancestor search and treats CWD as the root. [OpenAI: Advanced configuration, “Project root detection”](https://developers.openai.com/codex/config-advanced#project-root-detection); the current source default is also `['.git']` ([source](https://github.com/openai/codex/blob/ac9db7d8b556c7c34a73793aed34b1f980a4fe39/codex-rs/config/src/project_root_markers.rs#L5-L49)).
- Both project config discovery and `.agents/skills` ancestor scanning use this project-root concept. Project config layers require trust. The public skills page does not separately state a trust gate for `.agents/skills`; do not infer that every skill root has the exact same trust behavior as `.codex/config.toml` without a runtime-specific test.

### macOS expansion

For a macOS user `alice`, the normal paths are `/Users/alice/.codex/config.toml`, `/Users/alice/.agents/skills/`, and the compatibility root `/Users/alice/.codex/skills/`. Codex uses the Unix system paths `/etc/codex/config.toml` and `/etc/codex/skills/`; the official docs do not define a Codex-specific `~/Library/Application Support/...` replacement for these local CLI/app layers.

## Anthropic Claude Code

### MCP locations, scopes, and precedence

Claude Code defines three ordinary MCP scopes:

| Scope | Storage | Meaning |
|---|---|---|
| `local` (default) | `~/.claude.json`, under `projects[<absolute-project-path>].mcpServers` | Private to the user and current project |
| `project` | `<project-root>/.mcp.json`, top-level `mcpServers` | Shared with the team and normally committed |
| `user` | `~/.claude.json`, user-wide MCP area | Private to the user and available in every project |

Source: [Anthropic: MCP installation scopes](https://code.claude.com/docs/en/mcp#mcp-installation-scopes). The local-scope JSON shape is shown explicitly in the [local-scope section](https://code.claude.com/docs/en/mcp#local-scope), and the project `.mcp.json` shape in the [project-scope section](https://code.claude.com/docs/en/mcp#project-scope).

Current precedence for duplicate servers is:

1. Organization-provided `managedMcpServers` (above the ordinary list).
2. Local scope.
3. Project scope.
4. User scope.
5. Plugin-provided servers.
6. claude.ai connectors.

Claude Code uses the winning server entry whole; it does not merge fields across scopes. The general duplicate rule is name-based for the three ordinary scopes and endpoint-based for plugins/connectors. The desktop Code tab has a documented exception for same-named stdio definitions: top-level user scope in `~/.claude.json` wins over `.mcp.json`. [Anthropic: scope hierarchy and precedence](https://code.claude.com/docs/en/mcp#scope-hierarchy-and-precedence)

Important storage distinctions:

- `~/.claude/settings.json` is the user settings file, `.claude/settings.json` is shared project settings, and `.claude/settings.local.json` is private project-local settings. MCP server definitions belong in `~/.claude.json` or `.mcp.json`, not these general settings files. [Anthropic: settings files](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) and [Anthropic: MCP scopes](https://code.claude.com/docs/en/mcp#mcp-installation-scopes)
- Claude Desktop chat's `claude_desktop_config.json` is separate from Claude Code/Code-tab MCP configuration. The Claude Code surfaces share `~/.claude.json` and `.mcp.json`. [Anthropic: Claude Code Desktop, shared configuration](https://code.claude.com/docs/en/desktop#shared-configuration)
- Project `.mcp.json` requires an interactive approval before use; local scope is stored in the user file but is still tied to a project path. [Anthropic: project scope](https://code.claude.com/docs/en/mcp#project-scope)

### Skill locations and discovery

The current documented locations are:

- Personal: `~/.claude/skills/<skill-name>/SKILL.md`.
- Project: `<project>/.claude/skills/<skill-name>/SKILL.md`.
- Nested project: `<subdir>/.claude/skills/<skill-name>/SKILL.md`.
- Additional directory: `<added-dir>/.claude/skills/<skill-name>/SKILL.md` when supplied by `--add-dir`/`/add-dir`.
- Plugin: `<plugin>/skills/<skill-name>/SKILL.md`, invoked with the plugin namespace.
- Synced claude.ai skills: downloaded into `~/.claude/skills/synced/`; this directory is reserved and managed by syncing.
- Enterprise: `.claude/skills/<skill-name>/SKILL.md` inside the platform's managed-settings directory.

Source: [Anthropic: Skills, “Choose where skills load”](https://code.claude.com/docs/en/skills#choose-where-skills-load) and [“Where synced skills load”](https://code.claude.com/docs/en/skills#where-synced-skills-load).

Discovery details:

- At startup, project skills are loaded from `.claude/skills/` in CWD and every parent up to the repository root.
- A `.claude/skills/` below the startup directory is loaded only after Claude first reads or edits a file there; it then remains available for the session. Added directories load their own `.claude/skills/` immediately.
- In a linked worktree, the upward scan stops at the worktree root; current versions can fall back to the main checkout's root skills when the worktree root has none.
- Name collision priority across enterprise/personal/project is enterprise > personal > project. Root and nested same-name skills both remain available, with a directory-qualified name for the nested copy.
- Skill-directory symlinks are supported and de-duplicated by target.

Source: [Anthropic: monorepos and subdirectories](https://code.claude.com/docs/en/skills#load-skills-in-monorepos-and-subdirectories) and [Anthropic: same-name resolution](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name).

Legacy/alternate skill form: Markdown command files under `.claude/commands/` still work and create the same slash-command surface, but Anthropic calls them the older format and recommends skills for new work. [Anthropic: Skills](https://code.claude.com/docs/en/skills#choose-where-skills-load)

### macOS managed paths

Anthropic defines the macOS managed-settings base as `/Library/Application Support/ClaudeCode/`. Managed files such as `managed-settings.json`, `managed-settings.d/`, and `managed-mcp.json` live there. [Anthropic: Deploy managed settings](https://code.claude.com/docs/en/managed-settings#deploy-a-managed-settings-file)

The skills documentation says enterprise skills live in `.claude/skills/` **inside** the managed-settings directory. Combining those two first-party statements yields the macOS enterprise skill path `/Library/Application Support/ClaudeCode/.claude/skills/<skill-name>/SKILL.md`. This full macOS path is an inference; the docs print the equivalent Linux example (`/etc/claude-code/.claude/skills/...`) but do not print the fully joined macOS example. [Anthropic: remove an enterprise skill](https://code.claude.com/docs/en/skills#remove-a-skill)

### `CLAUDE_CONFIG_DIR` uncertainty

Anthropic documents `CLAUDE_CONFIG_DIR` as overriding the configuration directory (default `~/.claude`) and says settings, session history, and plugins are stored under it. [Anthropic: environment variables](https://code.claude.com/docs/en/env-vars#variables)

However, the current skills and MCP pages continue to specify `~/.claude/skills` and the sibling file `~/.claude.json` literally, and the environment-variable entry does not explicitly say whether it relocates either personal skills or the top-level MCP store. Therefore:

- Treat relocation of `~/.claude/skills` by `CLAUDE_CONFIG_DIR` as undocumented here, not guaranteed by these sources.
- Treat relocation of `~/.claude.json` MCP state by `CLAUDE_CONFIG_DIR` as undocumented here, not guaranteed by these sources.
- Project paths `.claude/skills` and `.mcp.json` are repository-relative and unaffected by a user config-root assumption.

## Known documentation/source mismatches and safe classification

1. **Codex user skills:** current docs designate `$HOME/.agents/skills`; current source still supports `$CODEX_HOME/skills` and explicitly marks it deprecated. Classify `$HOME/.agents/skills` as canonical and `$CODEX_HOME/skills` as compatibility/legacy.
2. **Codex project skills:** current docs emphasize ancestor `.agents/skills`; current source also derives `.codex/skills` from active project config layers. Classify `.agents/skills` as canonical and `.codex/skills` as a supported source-derived alternate whose public documentation is incomplete.
3. **Claude MCP general settings:** MCP uses `~/.claude.json` and project `.mcp.json`, not `settings.json`. Similar-looking paths such as `~/.mcp.json` or `~/.claude/mcp.json` are not canonical in the current official docs.
4. **Claude custom config root:** do not rewrite the skill or MCP paths solely from `CLAUDE_CONFIG_DIR` without checking the installed Claude Code version; the current official pages do not close that gap.

## Implementation-facing path set

For a filesystem scanner that aims to find current and compatible local assets without claiming all are canonical, the evidence supports this macOS set:

```text
# Codex
$HOME/.codex/config.toml
$HOME/.agents/skills/**/SKILL.md
$HOME/.codex/skills/**/SKILL.md                 # compatibility; includes .system
<root..cwd>/.codex/config.toml                  # trusted project config layers
<root..cwd>/.codex/skills/**/SKILL.md           # current source-derived alternate
<root..cwd>/.agents/skills/**/SKILL.md          # canonical project skills
/etc/codex/config.toml
/etc/codex/skills/**/SKILL.md

# Claude Code
$HOME/.claude.json                              # local + user MCP definitions
<project-root>/.mcp.json                        # shared project MCP
$HOME/.claude/skills/**/SKILL.md                # personal + synced subtree
<root..cwd>/.claude/skills/**/SKILL.md          # startup project scan
<descendant>/.claude/skills/**/SKILL.md         # discovered on file access
<project>/.claude/commands/**/*.md              # legacy command/skill form
/Library/Application Support/ClaudeCode/managed-mcp.json
/Library/Application Support/ClaudeCode/.claude/skills/**/SKILL.md  # inferred join
```

The scanner should preserve provenance (canonical, compatibility, legacy, managed, synced) rather than presenting all paths as equivalent.
