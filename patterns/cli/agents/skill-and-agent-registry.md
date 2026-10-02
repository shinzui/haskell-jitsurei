---
type: Pattern
title: "Skill and Agent Registry"
description: "Integrate baikai-kit for shared skill and agent installation, visibility, status, updates, and session discovery"
timestamp: 2026-10-02T13:18:57Z
generated:
  by: human:nadeem
  at: 2026-06-12T22:47:13Z
resource: mori://shinzui/haskell-jitsurei/docs/cli-skill-and-agent-registry
tags: [cli, agents, skills, registry, kit, distribution, baikai, visibility]
status: current
---

# Skill and Agent Registry with baikai-kit

Use [baikai-kit](mori://shinzui/baikai/packages/baikai-kit) for a CLI
that distributes skills and subagents from a git-hosted kit. The application
owns its kit content, configuration, presentation, and session launch policy.
The library owns fetching, manifest decoding, provider-native installation,
sidecars, status, update, uninstall, and session discovery. Keep the adapter
small; implement the lifecycle in the shared package rather than copying it
into each tool.

Use [Baikai.AgentAssets](mori://shinzui/baikai/docs/agent-assets) alone
when you need only pure provider path rules or asset rendering.

## Version boundary

Checked on 2026-10-02: Hackage and upstream tags publish `baikai-kit`
`0.3.0.0`. The current upstream source is commit
`2e3d4d1eaf4756894043947f0c266a6a2f6ba0e6` of
[mori://shinzui/baikai](mori://shinzui/baikai), whose changelog marks
`0.4.0.0` **unreleased**. This pattern includes that source's per-item
visibility design. `visibility`, `InstallOptions`, `confirmSharedCodex`,
`codexSessionArgs`, and visibility status fields require that source or a
subsequent release containing it; they are unavailable in published `0.3.0.0`.

Add `baikai` and `baikai-kit` to the consuming package. For the visibility
integration below, pin the required Baikai packages to that verified upstream
commit in `cabal.project`, including the `baikai` and `baikai-kit`
subdirectories. Include `baikai-claude` and `baikai-openai` when the application
launches those providers. Check the package registry and release tags again
before replacing that source pin with a released dependency.

## One configuration for installation and launch

Construct the configuration through `kitConfig`, then update optional fields.
A full `KitConfig` literal must supply every field and breaks when the library
adds one.

```haskell
import Baikai.Interactive (InteractiveProvider (..))
import Baikai.Kit qualified as Kit

myKitConfig :: Kit.KitConfig
myKitConfig =
  (Kit.kitConfig "mytool" "https://github.com/example/mytool-kit.git"
    [InteractiveClaude, InteractiveCodex])
    { Kit.projectRoot = Kit.projectRootByMarkers [".git", ".mytool"]
    }
```

`kitConfig` defaults project scope to the current directory. Most repository
CLIs should supply their project-root resolver so an install from `src/` and a
launch from the repository root find the same assets. `projectRootByMarkers`
chooses the nearest ancestor with any supplied marker, falling back to the
current directory. A tool with its own root rules can supply an `IO FilePath`.
All project operations and session discovery must use the same configuration.

The tool name selects `~/.cache/mytool/kit`,
`~/.config/mytool/agents`, `<root>/.mytool/agents`, and the
`.mytool-kit.json` sidecar name. Provider-native Codex directories are
resolved separately by the library.

## Delegate the command adapter

Embed the library's parser under the application's `kit` command:

```haskell
import Options.Applicative

kitParser :: Parser Kit.KitCommand
kitParser =
  hsubparser
    (command "kit"
      (info (Kit.kitCommandParser myKitConfig <**> helper)
        (progDesc "Manage skills and subagents")))

runKitCommand :: Kit.KitCommand -> IO ()
runKitCommand = Kit.runKit myKitConfig
```

The standard command surface is:

```text
mytool kit list [--json]
mytool kit install [NAME] [--project] [--shared | --tool-only] [--accept-shared-codex]
mytool kit update [NAME] [--force] [--json]
mytool kit uninstall NAME [--project]
mytool kit status [--json]
```

For a picker, set `chooseItem :: Maybe (KitManifest -> IO (Maybe Text))`.
The library loads the manifest and calls the chooser when `install` has no
name; the tool supplies its FZF or other UI. `Nothing` means cancellation.
Without a chooser, omitting the name fails before network access.

For custom presentation or exit codes, call `Kit.runKitCommand` or the
lower-level engine functions. `runKit` alone exits the process on failure;
`runKitCommand` returns `IO (Either KitError ())` while retaining the command's
output behavior. Operations such as `installItem` return `Either KitError a`
and print nothing; `kitStatus` instead returns a `StatusReport` containing
upstream availability. The current install call takes `InstallOptions`:

```haskell
result <- Kit.installItem myKitConfig "review" Kit.ProjectScope
  Kit.defaultInstallOptions
```

`defaultInstallOptions` follows the manifest. Do not duplicate `KitCommand`,
manifest records, cache code, hashing, sidecars, or provider conversion in the
application just to customize an output table.

## Author the kit manifest

Keep end-user assets in a separate kit repository so their releases can evolve
independently of the application binary. A minimal `kit.json` is:

```json
{
  "version": 2,
  "skills": [
    {
      "name": "review",
      "description": "Review a change",
      "version": "0.1.0",
      "path": "skills/review",
      "files": ["SKILL.md"],
      "visibility": "tool-only"
    }
  ],
  "agents": [
    {
      "name": "planner",
      "description": "Plan implementation work",
      "version": "0.1.0",
      "path": "agents/planner.md",
      "visibility": "shared"
    }
  ]
}
```

Manifest versions `1` and `2` decode identically; other versions are refused.
Per-item versions are optional for compatibility. Authors should version their
items on content changes. `files` is required for skills. For an agent without
`files`, `path` names one source file; with `files`, `path` names a directory,
the first file is the body, and remaining files are resources.

The library emits Claude Markdown agents and Codex custom-agent TOML. Multi-file
agent resources live in a sibling directory named after the agent, preventing
resource Markdown from being discovered as another agent. Kit source files
must be plain files: traversal, paths outside the checkout, and symbolic links
in source paths are refused by the installer and upstream hash checks.

## Scope and visibility are independent

`--project` chooses where an item is installed. Visibility chooses which
sessions discover it. The manifest defaults to `tool-only` when the field is
absent; mutually exclusive `--shared` and `--tool-only` flags override it.

| Scope | Tool-only | Shared |
|---|---|---|
| User | The tool's sessions across projects | Every provider session for that user |
| Project | The tool's sessions in that project | Every provider session in that project |

Claude assets stay under the tool's agent base in `.claude/skills` or
`.claude/agents`. Shared installs add owned links in the provider's normal
user or project `.claude` directories. Project links are relative so they
travel with a clone; user links are absolute.

Codex skills live in user or project `.agents/skills`. A tool-only install
adds a disabled `[[skills.config]]` entry for its `SKILL.md` in
`$CODEX_HOME/config.toml` (default `~/.codex/config.toml`). The tool's
launch must re-enable those skills using `codexSessionArgs`, below.
`--add-dir` grants directory access; it does not load Codex skills.

Codex custom agents cannot be isolated per session. A tool-only agent with
Codex enabled is refused before any provider copy is written unless the user
passes `--accept-shared-codex` or the tool's
`confirmSharedCodex :: Maybe (KitItem -> IO Bool)` callback accepts it.
Choosing `--shared` also permits it. Status records both requested tool-only
and effective shared visibility. Already installed agents do not prompt again
on update.

The installer refuses foreign destinations and shared-name conflicts. It owns
only its recorded links and config entries; reused user-owned disabled entries
survive uninstall. Malformed, symlinked, read-only, or conflicting Codex config
is reported for the user to resolve. Keep this ownership logic in the engine.

## Wire session discovery into every launch

Claude launches append the existing tool-specific directories returned by
`agentDirsForSession` to the request's `extraDirs`. Codex launches append
`codexSessionArgs` to the request's `extraArgs`:

```haskell
import Baikai.Interactive qualified as Interactive

withKitAssets
  :: Interactive.InteractiveProvider
  -> Interactive.InteractiveLaunchRequest
  -> IO Interactive.InteractiveLaunchRequest
withKitAssets provider request = case provider of
  Interactive.InteractiveClaude -> do
    dirs <- Kit.agentDirsForSession myKitConfig
    pure request
      { Interactive.extraDirs = Interactive.extraDirs request <> dirs }
  Interactive.InteractiveCodex -> do
    args <- Kit.codexSessionArgs myKitConfig
    pure request
      { Interactive.extraArgs = Interactive.extraArgs request <> args }
```

Apply the Codex step to batch `codex exec` launches too, using the corresponding
request or CLI configuration's extra arguments. A dependency bump alone leaves
tool-only skills hidden. `codexSessionArgs` selects only this tool's sidecars,
canonicalizes and deduplicates paths, and returns no arguments for a Claude-only
configuration. Session discovery does not fetch or install kit content.

## Status, updates, and automation

Status compares each provider copy with the cached manifest, the install-time
upstream hash, the installed-file hash, and recorded visibility. Conditions
can coexist; do not replace them with the old single `dirty` state.

| Condition | Meaning |
|---|---|
| `unknown` | Missing or unreadable sidecar |
| `delisted` | Valid sidecar, item absent from the manifest |
| `refused` | Cached upstream sources fail the source-path checks |
| `outdated` | Upstream version differs |
| `changed-upstream` | Upstream content hash differs, independently of its version |
| `modified` | Installed files were edited or removed |
| `edits-unknown` | Legacy sidecar has no installed-file hash |
| `visibility-broken` | Recorded link or Codex entry is missing, wrong, or conflicting |

No conditions means `up-to-date`. Human output groups matching rows and shows
provider coverage. JSON status keeps one record per item, scope, and provider,
with `conditions`, `requestedVisibility`, and `effectiveVisibility`.

Update reinstalls already installed items and skips local modifications by
default, reporting the skip with exit status 0. `--force` permits overwriting
those edits. Update repairs visibility even when it skips content. An explicit
install visibility flag persists; manifest-driven installs follow changed
manifest defaults. Legacy pre-0.4 installs retain their placement on update;
reinstall explicitly to migrate a legacy shared Codex skill to tool-only.

`status` attempts to refresh through `ensureKitRepo`, then compares local
files. It tolerates an unavailable upstream and still reports installed copies;
it is usable offline, but it is not a network-free command. `list` and
`install` warn and use cached content after a failed refresh, but require a
manifest. `update` fails if its fetch fails. In JSON mode, successful list/status/update emits
one UTF-8 JSON document on stdout; warnings go to stderr. Failures emit no
JSON document. Inspect the `upstream` state on list/status rather than treating
a cached comparison as proof of fresh upstream content.

Use `formatVersion` and `document` to recognize the JSON contract. The library
also exposes `listDocument`, `statusDocument`, and `updateDocument` in
`Baikai.Kit.Json`; consuming tools can use them without executing a CLI.

## Validate the application integration

Test the adapter with an isolated home, Codex config directory, fixture kit,
and throwaway project. Do not use a developer's installed assets for fixtures.
Cover the integration choices the application owns:

- Parse the library command under the application's command tree.
- Install from a nested project directory and confirm status and launch use the
  same resolved root.
- Verify Claude directories and Codex session arguments reach every launch path.
- Check tool-only and shared skill discovery, agent acceptance, visibility repair,
  and preservation of foreign assets and config entries.
- Check local edits are reported and skipped, while an explicit force updates.
- Parse JSON as one document and keep warnings off stdout.

The shared engine's tests own hash algorithms, provider conversion, rollback,
and sidecar invariants. Applications should test their configuration and wiring.

See the authoritative [kit guide](mori://shinzui/baikai/docs/kit),
[agent asset guide](mori://shinzui/baikai/docs/agent-assets), and
[interactive launch guide](mori://shinzui/baikai/docs/interactive-launches).
