---
type: Pattern
title: "Skill and Agent Registry"
description: "Distribute versioned coding-agent skills and subagents through a provider-neutral kit repository"
timestamp: 2026-06-12T15:47:13-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-skill-and-agent-registry
tags: [cli, agents, skills, registry, kit, distribution]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-06-12T15:47:13-07:00
    scope: catalog-metadata
    outcome: approved
---

# Pattern: Skill & Agent Registry (Kit)

**A distributable registry for installing AI skills and subagents locally or globally from a GitHub repository.**

## Problem

Your CLI launches AI coding sessions (`mori agent assist`, etc.) with context-rich system prompts. You also author reusable **skills** (slash-command prompts) and **subagents** (specialized autonomous agents) that help end-users work with your ecosystem. But these artifacts live in your source repo alongside developer-only tooling, and users have no way to discover, install, update, or remove them independently from binary releases.

You need:

1. A **separation** between developer-only skills (tied to the source repo) and end-user skills (distributed to users).
2. A **distribution channel** — users shouldn't need to clone your source repo.
3. **Scoped installation** — some skills should be available across all projects (global), others only in a specific project (local).
4. A **lifecycle** — install, update, uninstall, and status inspection.

## Solution

Create a **separate GitHub repository** (`<project>-kit`) as the skill/agent registry. Add a **`<project> kit`** CLI command that clones the registry to a local cache and copies content to Claude Code's `--add-dir` directories at user or project scope.

```
┌──────────────┐     git clone      ┌─────────────────────┐
│  GitHub repo │────────────────────▶│ Local cache          │
│  <proj>-kit  │     --depth 1      │ ~/.cache/<proj>/kit/ │
└──────────────┘                    └──────────┬──────────┘
                                               │ copy files
                              ┌────────────────┼────────────────┐
                              ▼                                 ▼
                   ┌─────────────────────┐         ┌──────────────────────┐
                   │ User scope (global)  │         │ Project scope (local) │
                   │ ~/.config/<proj>/    │         │ ./<proj>/agents/      │
                   │   agents/.claude/    │         │   .claude/            │
                   │     skills/<name>/   │         │     skills/<name>/    │
                   │     agents/<name>.md │         │     agents/<name>.md  │
                   └─────────────────────┘         └──────────────────────┘
                              │                                 │
                              └────────────┬────────────────────┘
                                           ▼
                                 ┌───────────────────┐
                                 │ AI Session         │
                                 │ claude --add-dir … │
                                 └───────────────────┘
```

## Key Components

### 1. The Kit Repository (GitHub)

A standalone GitHub repository with a flat, predictable structure:

```
<project>-kit/
├── kit.json                    # Machine-readable manifest
├── README.md                   # Human-readable index
├── skills/
│   ├── automation-config/
│   │   └── SKILL.md            # Claude Code skill format
│   ├── mori-config/
│   │   └── SKILL.md
│   └── cookbook-config/
│       └── SKILL.md
└── agents/
    └── <agent-name>.md         # Claude Code subagent format
```

**Why a separate repo:**

- Content evolves independently from binary releases — push a new skill, users get it on next `kit update`.
- Users can contribute via PRs without touching the core codebase.
- No non-Haskell assets bloating the cabal package.
- No database required — pure filesystem + network operations.

### 2. The Manifest (`kit.json`)

A JSON file at the repo root that enumerates all available content:

```json
{
  "version": 2,
  "skills": [
    {
      "name": "automation-config",
      "version": "0.1.0",
      "description": "Author, validate, and debug mori automation configurations",
      "path": "skills/automation-config",
      "files": ["SKILL.md"]
    },
    {
      "name": "mori-config",
      "version": "0.1.0",
      "description": "Author, validate, and edit mori.dhall project configurations",
      "path": "skills/mori-config",
      "files": ["SKILL.md"]
    }
  ],
  "agents": [
    {
      "name": "automation-author",
      "version": "0.1.0",
      "description": "Specialized agent for writing and debugging automation configs",
      "path": "agents/automation-author.md"
    }
  ]
}
```

**Design decisions:**

| Field | Purpose |
|-------|---------|
| `version` (top-level) | Manifest schema version. `1` = no per-entry versions; `2` = entries carry a `version` field. Bumping signals a breaking schema change so the CLI can detect incompatible manifests and degrade gracefully. |
| `skills[].version`, `agents[].version` | Author-managed semver string for *each item*. Bumped by the kit author on every content change. Parsed as `Maybe Text` so v1 manifests (and untagged entries) still load. See [Versioning Strategy](#versioning-strategy). |
| `skills[].path` | Relative path to the skill directory in the repo |
| `skills[].files` | Explicit file list — avoids hidden-file surprises, supports multi-file skills |
| `agents[].path` | Relative path to the single agent markdown file |

The manifest is the source of truth for `kit list`. It is parsed via `FromJSON` with no custom instances — field names match JSON keys exactly. Per-entry `version` must be declared `Maybe Text` so legacy v1 manifests still parse cleanly.

### 3. Skill Format (Claude Code)

Each skill is a directory containing at minimum a `SKILL.md` with YAML frontmatter:

```yaml
---
name: automation-config
version: "0.1.0"
description: >
  Help author, validate, and debug mori automation configurations.
  TRIGGER when: user wants to create or edit automation rules.
argument-hint: [create|debug|explain]
user-invocable: true
---

# Automation Config Skill

You are helping the user author, validate, and debug an automation configuration...

## Top-level structure
...

## Examples
...
```

Key frontmatter fields:

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Becomes the `/name` slash command |
| `version` | yes (v2+) | Semver string. Must match the entry's `version` in `kit.json` so authors only have one place to inspect to know what's published. Bumped on every content change. |
| `description` | yes | Shown in skill listings, used by Claude for auto-triggering |
| `user-invocable` | yes | Set `true` for slash-command skills |
| `argument-hint` | no | Tab-completion hint for arguments |

### 4. Subagent Format (Claude Code)

Each subagent is a single markdown file in `agents/`:

```yaml
---
name: automation-author
description: Specialized agent for writing and debugging automation configs
model: sonnet
tools: [Bash, Read, Edit, Grep, Glob]
---

# Automation Author Agent

You specialize in writing and debugging automation configurations...
```

Key frontmatter fields:

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Agent identifier |
| `description` | yes | When Claude decides to spawn this agent |
| `model` | no | Model override (sonnet, opus, haiku) |
| `tools` | no | Allowlist of tools the agent can use |
| `disallowedTools` | no | Denylist of tools |
| `permissionMode` | no | How permission prompts are handled |
| `skills` | no | Skills to preload into the agent |
| `background` | no | Always run in background? |
| `isolation` | no | Isolation mode (e.g., "worktree") |

### 5. The CLI Command

A single command with five subcommands covering the full lifecycle:

```bash
mycli kit list                          # Show available skills and agents
mycli kit install <name>                # Install to user scope (global)
mycli kit install <name> --project      # Install to project scope (local)
mycli kit update                        # Pull latest, re-install all
mycli kit update <name>                 # Pull latest, re-install one
mycli kit uninstall <name>              # Remove from user scope
mycli kit uninstall <name> --project    # Remove from project scope
mycli kit status                        # NAME / TYPE / SCOPE / INSTALLED / LATEST / STATE
```

`kit status` is the user-visible payoff of versioning. For every (item, scope)
pair it prints one row classified as `up-to-date`, `outdated` (versions
differ), `dirty` (versions match but upstream content drifted since install),
or `unknown` (no per-install sidecar, no upstream entry, or no usable cache).
See [Versioning Strategy](#versioning-strategy) for the full state machine.

**No database required.** The kit command is purely filesystem + git operations, which means it works without any connection string or database setup. This lowers the barrier for new users.

### 6. Installation Scopes

| Scope | Directory | Use case |
|-------|-----------|----------|
| **User** (default) | `~/.config/<project>/agents/` | Skills available across all projects |
| **Project** | `./<project>/agents/` (in project root) | Skills scoped to a single project, can be version-controlled |

Within each scope directory, Claude Code's `--add-dir` discovery expects:
- Skills at `.claude/skills/<name>/SKILL.md`
- Agents at `.claude/agents/<name>.md`

So the full installed path for a user-scope skill is:
```
~/.config/<project>/agents/.claude/skills/automation-config/SKILL.md
```

> **Multi-provider note.** The paths above are Claude Code's layout. If your
> CLI can also launch **Codex** (OpenAI's CLI) sessions, Codex discovers skills
> and agents from entirely different roots and does *not* read `.claude/...`.
> Installing into both layouts is a self-contained extension of this pattern —
> see [Provider-Neutral Kits (Claude Code + Codex)](#provider-neutral-kits-claude-code--codex).

### 7. The Cache Layer

The kit repo is shallow-cloned to `~/.cache/<project>/kit/` on first use. Subsequent operations run `git pull --ff-only` to update.

**Graceful degradation:** If git clone/pull fails but `kit.json` exists in the cache, the command continues with cached data and prints a warning. This means offline usage works after the first successful fetch.

**Cache is disposable:** Users can safely delete `~/.cache/<project>/kit/` — it will be re-cloned on next use.

## Implementation

### Data Types

```haskell
-- Subcommand dispatch
data KitCommand
  = KitList
  | KitInstall !KitInstallOpts
  | KitUpdate !KitUpdateOpts
  | KitUninstall !KitUninstallOpts
  | KitStatus
  deriving stock (Show)

data KitInstallOpts = KitInstallOpts
  { itemName :: !Text
  , projectScope :: !Bool
  }
  deriving stock (Generic, Show)

data KitUpdateOpts = KitUpdateOpts
  { itemName :: !(Maybe Text)
  }
  deriving stock (Generic, Show)

data KitUninstallOpts = KitUninstallOpts
  { itemName :: !Text
  , projectScope :: !Bool
  }
  deriving stock (Generic, Show)

data KitScope = UserScope | ProjectScope
  deriving stock (Show)

-- Manifest (parsed from kit.json)
data KitManifest = KitManifest
  { version :: !Int          -- 1 = no per-entry versions; 2 = entries carry `version`
  , skills :: ![SkillEntry]
  , agents :: ![AgentEntry]
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data SkillEntry = SkillEntry
  { name :: !Text
  , description :: !Text
  , version :: !(Maybe Text) -- semver bumped by the author on every content change
  , path :: !Text          -- relative path in repo (e.g., "skills/foo")
  , files :: ![Text]       -- files to copy (e.g., ["SKILL.md"])
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data AgentEntry = AgentEntry
  { name :: !Text
  , description :: !Text
  , version :: !(Maybe Text)
  , path :: !Text          -- relative path to the .md file
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

-- Per-install metadata file (.kit.json sidecar) written next to each
-- installed item. Recovered at status time to compare the install-time
-- snapshot against current upstream.
data SidecarMeta = SidecarMeta
  { name :: !Text
  , kind :: !Text          -- "skill" | "agent"
  , version :: !(Maybe Text) -- the upstream version at install time (may be null)
  , hash :: !Text          -- "sha256:<hex>" of upstream files at install time
  , installedAt :: !Text   -- ISO-8601 UTC, second precision
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

-- The status state a (item, scope) pair classifies into.
data KitState
  = KitUpToDate            -- versions and content hash both match
  | KitOutdated            -- upstream version differs from sidecar
  | KitDirty               -- versions match but upstream content drifted
  | KitUnknown             -- no sidecar, no upstream entry, or no cache
  deriving stock (Eq, Show)
```

> **Note on field naming.** `SidecarMeta`, `SkillEntry`, and `AgentEntry` all
> share field names like `name` and `version`. Enable `DuplicateRecordFields`
> and define small accessor wrappers (e.g. `skillVersionOf :: SkillEntry ->
> Maybe Text`) so call sites stay unambiguous without forcing
> `OverloadedRecordDot` everywhere.

### Key Functions

```haskell
-- Cache management
kitCacheDir :: IO FilePath
kitCacheDir = do
  home <- getHomeDirectory
  pure (home </> ".cache" </> "<project>" </> "kit")

-- Clone or pull the kit repo
ensureKitRepo :: IO FilePath
ensureKitRepo = do
  cacheDir <- kitCacheDir
  exists <- doesDirectoryExist (cacheDir </> ".git")
  if exists
    then pullKitRepo cacheDir >> pure cacheDir
    else do
      createDirectoryIfMissing True cacheDir
      (exitCode, _, errOut) <-
        readProcessWithExitCode "git"
          ["clone", "--depth", "1", kitRepoUrl, cacheDir] ""
      case exitCode of
        ExitSuccess -> pure cacheDir
        ExitFailure _ -> do
          -- Graceful degradation: use cached manifest if available
          manifestExists <- doesFileExist (cacheDir </> "kit.json")
          if manifestExists
            then hPutStrLn stderr ("Warning: git clone failed, using cache. " <> errOut)
                 >> pure cacheDir
            else hPutStrLn stderr ("Error: " <> errOut) >> exitFailure

-- Resolve target directory based on scope
resolveTargetDir :: KitScope -> IO FilePath
resolveTargetDir UserScope = do
  home <- getHomeDirectory
  pure (home </> ".config" </> "<project>" </> "agents")
resolveTargetDir ProjectScope = do
  cwd <- getCurrentDirectory
  pure (cwd </> ".<project>" </> "agents")

-- Install: copy files from cache to target, then write the sidecar
doInstall :: FilePath -> KitItem -> KitScope -> IO ()
doInstall repoDir item@(KitSkillItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let targetDir = targetBase </> ".claude" </> "skills" </> T.unpack (name entry)
      sourceDir = repoDir </> T.unpack (path entry)
  createDirectoryIfMissing True targetDir
  mapM_ (copySkillFile repoDir entry targetDir) (files entry)
  -- Hash the upstream files at install time and write the sidecar
  hashStr <- computeKitHash sourceDir (files entry)
  writeSidecar item targetBase hashStr
doInstall repoDir item@(KitAgentItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let agentDir = targetBase </> ".claude" </> "agents"
      srcRel = T.unpack (path entry)
      sourceDir = repoDir </> takeDirectory srcRel
      onlyFile = T.pack (takeFileName srcRel)
  createDirectoryIfMissing True agentDir
  copyFile (repoDir </> srcRel) (agentDir </> takeFileName srcRel)
  hashStr <- computeKitHash sourceDir [onlyFile]
  writeSidecar item targetBase hashStr
```

> **Critical:** for agents, `computeKitHash` must be called with the
> *directory* containing the file as the base and the *basename* as the
> single relative path — not with the cache root and the full relative
> path. The algorithm folds the relative-path bytes into the digest, so
> `computeKitHash cacheDir ["agents/foo.md"]` and
> `computeKitHash (cacheDir </> "agents") ["foo.md"]` yield different
> hashes for identical content. The status-time hash code MUST use the
> same split or every installed agent will be reported `dirty`. Pin both
> sides with a fixture test.

### Versioning + Outdated Detection

```haskell
-- Deterministic content hash. Sorts file paths lexicographically and
-- length-prefixes each file's content so trivial reorderings or
-- concatenations cannot collide. Output is "sha256:<hex>".
computeKitHash :: FilePath -> [Text] -> IO Text
computeKitHash baseDir relFiles = do
  let sorted = sort relFiles
  parts <- mapM (readOne baseDir) sorted
  let digest = Hash.hash (BS.concat parts) :: Digest SHA256
      hex    = TE.decodeUtf8 (convertToBase Base16 digest)
  pure ("sha256:" <> hex)
  where
    readOne dir rel = do
      content <- BS.readFile (dir </> T.unpack rel)
      let pathBytes = TE.encodeUtf8 rel
          lenBytes  = LBS.toStrict (runPut (putWord64be (fromIntegral (BS.length content))))
      pure $ BS.concat [pathBytes, BS.singleton 0, lenBytes, content, BS.singleton 0]

-- Where the sidecar lives for an installed item.
sidecarPath :: KitItem -> FilePath -> FilePath
sidecarPath (KitSkillItem e) base =
  base </> ".claude" </> "skills" </> T.unpack (name e) </> ".kit.json"
sidecarPath (KitAgentItem e) base =
  base </> ".claude" </> "agents" </> T.unpack (name e) <> ".kit.json"

writeSidecar :: KitItem -> FilePath -> Text -> IO ()
readSidecar  :: FilePath -> IO (Maybe SidecarMeta)

-- Pure classification. Precedence: unknown > outdated > dirty > up-to-date.
--
--   * No sidecar              => Unknown   (no anchor for comparison)
--   * No upstream entry       => Unknown   (removed upstream)
--   * Upstream version differs from sidecar version => Outdated
--   * Upstream hash differs from sidecar hash       => Dirty
--   * Otherwise               => UpToDate
classify
  :: Maybe SidecarMeta -> Maybe KitItem -> Maybe Text -> KitState
classify Nothing _ _              = KitUnknown
classify (Just _) Nothing _       = KitUnknown
classify (Just sm) (Just it) mHash =
  case itemVersion it of
    Just latest
      | sidecarMetaVersion sm /= Just latest -> KitOutdated
    _ -> case mHash of
           Just up | up /= sidecarMetaHash sm -> KitDirty
           _ -> KitUpToDate

-- Testable core. Production caller passes both scopes in one call:
--
--   rows <- collectStatus cacheDir [(userDir, "user"), (projectDir, "project")]
--
-- Each (item, scope) pair becomes one row, classified independently from
-- its own sidecar at its own target base. Take a list of (base, label)
-- pairs explicitly so tests can drive any combination of fake scopes
-- through the same code path.
collectStatus :: FilePath -> [(FilePath, Text)] -> IO [StatusRow]
```

A few load-bearing choices worth lifting out:

- **Hash the upstream bytes at install time, not the destination bytes.**
  Hashing the destination would tautologically equal the install-time
  snapshot forever, defeating drift detection.
- **One sidecar per (item, scope).** Treat user and project scopes as
  fully independent peers — never read one scope's sidecar against the
  other scope's row. Add a dual-scope fixture test that flips one scope
  while asserting the other stays unchanged.
- **Refresh the cache on `kit status`.** A status command that doesn't
  pull would happily report `up-to-date` against a stale cache. Reuse
  `ensureKitRepo` so the existing network-failure fallback (warn on
  stderr, use cached data) carries over. When neither pull nor cache
  yields a usable `kit.json`, return `""` as the cache directory and let
  every row degrade to `LATEST = -`, `STATE = unknown`.

### Wiring Into the CLI

The kit command is wired into the main CLI dispatch **outside the database pool section**, since it requires no database:

```haskell
-- In Cli.hs command ADT:
data Command
  = ...
  | Kit !KitCommand
  deriving stock (Show)

-- In parser:
command "kit" (info (Kit <$> kitCommandParser)
  (progDesc "Manage Claude Code skills and subagents"))

-- In dispatch (no-database section):
Kit kitCmd -> runKit kitCmd
```

### Agent Session Integration

The installed skills and agents are discovered at session launch via `--add-dir`:

```haskell
-- Discover agent directories (both scopes)
agentDirsForSession :: IO [FilePath]
agentDirsForSession = do
  home <- getHomeDirectory
  cwd <- getCurrentDirectory
  let userAgentDir    = home </> ".config" </> "<project>" </> "agents"
      projectAgentDir = cwd </> ".<project>" </> "agents"
  filterM doesDirectoryExist [userAgentDir, projectAgentDir]

-- Pass to claude via --add-dir
buildClaudeArgs :: [FilePath] -> [String] -> String -> [String]
buildClaudeArgs addDirs allowedTools promptStr =
  ["--permission-mode", "acceptEdits"]
    ++ concatMap (\d -> ["--add-dir", d]) addDirs
    ++ "--allowedTools" : allowedTools
    ++ ["--append-system-prompt", promptStr]
```

Claude Code automatically discovers `.claude/skills/` and `.claude/agents/` within each `--add-dir` directory.

### Dependencies

The base command needs only what most CLIs already have:

| Module | Purpose |
|--------|---------|
| `System.Process` | Running `git clone` and `git pull` |
| `System.Directory` | Directory creation, existence checks, file copying |
| `Data.Aeson` | Parsing `kit.json` (already a dependency) |
| `Options.Applicative` | Command parsing (already a dependency) |

Versioning adds three more, all already present in most Haskell CLI stacks:

| Module | Purpose |
|--------|---------|
| `Crypto.Hash` (`crypton`) | SHA-256 digest for the content hash |
| `Data.Binary.Put` (`binary`) | Big-endian length prefix in the hash framing |
| `Data.ByteArray.Encoding` (`memory` / `ram`) | Hex-encode the digest output |

On GHC 9.12+, both `binary` and the byte-array encoding package must be
declared as direct dependencies even though they ship as boot libraries;
the resolver will otherwise pick incompatible versions transitively. If
`Crypto.Hash.hash` collides with the `hash` field of `SidecarMeta` (it
does under `DuplicateRecordFields`), `import Crypto.Hash qualified as Hash`
at the call site is the simplest fix.

## Provider-Neutral Kits (Claude Code + Codex)

Everything above assumes one consumer: **Claude Code**, which discovers
`.claude/skills/` and `.claude/agents/` inside any `--add-dir` directory. The moment
your CLI can also launch **Codex** (OpenAI's CLI) interactive sessions, that assumption
breaks — and it breaks *silently*. Codex does not read `.claude/...` at all, and passing
the directory with `--add-dir` does not help: in Codex, `--add-dir` only marks a
directory **writable** in the sandbox; it is not a discovery mechanism. So a user who
runs `<project> kit install foo` and then starts a Codex session gets *none* of their
installed kit content, with no error. The kit feature is quietly Claude-only.

The fix lives entirely in **installation**, not in the session launcher. Make `kit
install`/`update`/`uninstall`/`status` write **both** provider layouts. The launcher is
unchanged — it still passes the agent base dirs to both CLIs via `--add-dir` (harmless
for Codex), and Codex finds its content through its own native roots.

### How Codex discovers skills and agents

Confirmed against the official Codex docs ([skills](https://developers.openai.com/codex/skills),
[subagents](https://developers.openai.com/codex/subagents)), Codex uses different roots
*and a different agent file format* than Claude Code:

| Asset | Claude Code | Codex |
|-------|-------------|-------|
| **Skill** | `.claude/skills/<name>/SKILL.md` | `.agents/skills/<name>/SKILL.md` |
| **Agent** | `.claude/agents/<name>.md` (Markdown) | `.codex/agents/<name>.toml` (**TOML**) |
| Skill discovery root | any `--add-dir` directory | `.agents/skills` scanned from CWD up to the repo root; plus `$HOME/.agents/skills` |
| Agent discovery root | `.claude/agents` under an `--add-dir` directory | `.codex/agents/` (project) or `~/.codex/agents/` (user) |

Two consequences shape the design:

1. **Codex skills are a directory copy (same `SKILL.md`), but Codex agents need a format
   conversion.** Claude agents are Markdown with YAML frontmatter; Codex custom agents
   are standalone TOML files with `name`, `description`, and `developer_instructions`
   keys. The kit's agent Markdown body becomes the `developer_instructions` value.
2. **Codex content does not live under your `<project>` agent base dir.** Claude content
   sits below `~/.config/<project>/agents/` (user) or `./<project>/agents/` (project)
   because that is what you mount with `--add-dir`. Codex scans *its own* roots, so Codex
   content must land at the **working-tree root** (`.agents/skills`, `.codex/agents`) for
   project scope and under **`$HOME`** (`$HOME/.agents/skills`, `$HOME/.codex/agents`) for
   user scope — never below the `<project>` agent base.

### The path-layout module

Rather than scatter `.claude` / `.agents` / `.codex` string literals across the handler,
put every provider-native path in one module. The cleanest version of this is a tiny
library that, given a provider and an item name, returns the relative tail — and a
renderer that turns a kit agent into Codex TOML. (In the reference fleet this is
`Baikai.AgentAssets`, a shared dependency reused verbatim by every CLI that has a kit; if
you have no such shared library, the helper below is self-contained.)

```haskell
data KitProviderLayout = ClaudeLayout | CodexLayout
  deriving stock (Eq, Ord, Show)

allKitProviderLayouts :: [KitProviderLayout]
allKitProviderLayouts = [ClaudeLayout, CodexLayout]

providerLabel :: KitProviderLayout -> Text
providerLabel ClaudeLayout = "claude"
providerLabel CodexLayout  = "codex"

-- Relative tail of an installed skill directory, below a provider base dir.
skillRelDir :: KitProviderLayout -> Text -> FilePath
skillRelDir ClaudeLayout n = ".claude" </> "skills" </> T.unpack n
skillRelDir CodexLayout  n = ".agents" </> "skills" </> T.unpack n

-- Relative path of an installed agent file, below a provider base dir.
-- Note the extension differs: Markdown for Claude, TOML for Codex.
agentRelFile :: KitProviderLayout -> Text -> FilePath
agentRelFile ClaudeLayout n = ".claude" </> "agents" </> T.unpack n <> ".md"
agentRelFile CodexLayout  n = ".codex"  </> "agents" </> T.unpack n <> ".toml"

-- Render the minimal TOML a Codex custom agent expects. The kit agent's
-- Markdown body becomes developer_instructions (a triple-quoted block).
codexAgentToml :: Text -> Text -> Text -> Text
codexAgentToml agentName desc instructions =
  T.unlines
    [ "name = " <> tomlString agentName
    , "description = " <> tomlString desc
    , "developer_instructions = " <> tomlMultiline instructions
    ]
  where
    tomlString t = "\"" <> T.concatMap esc t <> "\""
    esc '"'  = "\\\""; esc '\\' = "\\\\"; esc '\n' = "\\n"
    esc '\r' = "\\r";  esc '\t' = "\\t";  esc c = T.singleton c
    tomlMultiline t = "\"\"\"\n" <> T.replace "\"\"\"" "\\\"\\\"\\\"" t <> "\n\"\"\""
```

### Per-provider base-dir resolution

The one subtlety that catches people: the **base dir is provider-dependent**. Claude
keeps the existing `<project>` agent base; Codex uses the working tree / `$HOME` directly.

```haskell
-- Claude: the <project> agent base (unchanged from the single-provider design).
-- Codex:  its own native roots — CWD for project scope, $HOME for user scope.
resolveProviderTargetDir :: KitProviderLayout -> KitScope -> IO FilePath
resolveProviderTargetDir ClaudeLayout scope        = resolveTargetDir scope
resolveProviderTargetDir CodexLayout  UserScope    = getHomeDirectory
resolveProviderTargetDir CodexLayout  ProjectScope = getCurrentDirectory
```

So a project-scope skill `foo` lands at **both**:

```
./<project>/agents/.claude/skills/foo/SKILL.md     # Claude (below the agent base)
./.agents/skills/foo/SKILL.md                      # Codex (working-tree root)
```

and a project-scope agent `bar` lands at **both**:

```
./<project>/agents/.claude/agents/bar.md           # Claude Markdown
./.codex/agents/bar.toml                           # Codex TOML (converted)
```

### Layout-aware install

`doInstall` loops over every provider layout. Skills copy identically into both skill
roots; agents copy the Markdown for Claude and write converted TOML for Codex.

```haskell
doInstall :: FilePath -> KitItem -> KitScope -> IO ()
doInstall repoDir (KitSkillItem entry) scope =
  forM_ allKitProviderLayouts $ \layout -> do
    base <- resolveProviderTargetDir layout scope
    let targetDir = base </> skillRelDir layout (name entry)
    createDirectoryIfMissing True targetDir
    mapM_ (copySkillFile repoDir entry targetDir) (files entry)
doInstall repoDir (KitAgentItem entry) scope =
  forM_ allKitProviderLayouts $ \layout -> do
    base <- resolveProviderTargetDir layout scope
    let dstFile = base </> agentRelFile layout (name entry)
        srcFile = repoDir </> T.unpack (path entry)
    createDirectoryIfMissing True (takeDirectory dstFile)
    case layout of
      ClaudeLayout -> copyFile srcFile dstFile           -- Markdown as-is
      CodexLayout  -> do                                  -- convert to TOML
        body <- TIO.readFile srcFile
        TIO.writeFile dstFile (codexAgentToml (name entry) (description entry) body)
```

### Symmetric lifecycle: uninstall, update, status

The other operations loop over the same provider list so they stay symmetric:

- **`isInstalled`** returns true if *any* provider layout has the item — otherwise
  `update` would never repair a missing Codex copy.
- **`uninstall`** removes every provider copy for the item+scope, and the message must
  not imply only one provider was touched.
- **`update`** needs no structural change: it re-runs `doInstall`, which now writes both
  layouts, so a partial install (e.g. only the Claude copy) is repaired automatically.
- **`status`** scans both layouts per scope and reports provider coverage. The smallest
  readable shape is one row per item with a `PROVIDERS` cell (`claude,codex`); if you
  already ship per-item versioning (the [sidecar](#the-sidecar) design above), classify
  each provider copy independently — write one `.kit.json` sidecar per provider copy and
  emit one status row per (item, scope, provider) so a drifted Codex copy can't hide
  behind an up-to-date Claude one.

```bash
$ <project> kit status
NAME              TYPE   PROVIDERS     SCOPE
automation-config skill  claude,codex  user
automation-author agent  claude,codex  project
```

### What stays the same

The session launcher and `agentDirsForSession` are **untouched**. They already pass the
`<project>` agent base dirs to both Claude and Codex via `--add-dir`. That remains correct:
Claude uses those dirs to discover `.claude/...`, and for Codex the flag is a harmless
writability grant while discovery happens through `.agents` / `.codex`. API-only providers
(an Anthropic Messages or OpenAI Chat Completions backend, with no local CLI) load no local
skills or agents at all, so they are out of scope for kit installation entirely.

### Why a shared asset module pays off

The path table, the format-per-provider rule, and the TOML renderer are identical across
every CLI in a fleet that ships kits. Factoring them into one dependency (the reference
fleet uses `Baikai.AgentAssets`) means: a CLI adopting Codex support adds the dependency
to its `kit` command, writes a ~40-line `KitPaths` wrapper, and loops its handler over
`allKitProviderLayouts` — no new path logic, no risk of two CLIs disagreeing about where
Codex looks. When Codex changes a discovery root, one module updates and the whole fleet
follows.

## GitHub Setup

### Creating the Kit Repository

```bash
# 1. Create the repo structure
mkdir <project>-kit && cd <project>-kit
git init
mkdir -p skills agents

# 2. Create the manifest
cat > kit.json << 'EOF'
{
  "version": 2,
  "skills": [],
  "agents": []
}
EOF

# 3. Create a README
cat > README.md << 'EOF'
# <project>-kit

Claude Code skills and subagents for <project> end-users.

## Installation

```bash
<project> kit install <skill-name>   # install a skill
<project> kit list                   # see all available content
<project> kit status                 # see what's installed
<project> kit update                 # pull latest versions
```
EOF

# 4. Push to GitHub
gh repo create <org>/<project>-kit --public --source=. --push
```

### Adding a New Skill

```bash
cd <project>-kit

# 1. Create the skill directory and file
mkdir -p skills/my-new-skill
cat > skills/my-new-skill/SKILL.md << 'EOF'
---
name: my-new-skill
version: "0.1.0"
description: >
  What this skill does and when to trigger it.
argument-hint: [optional args]
user-invocable: true
---

# My New Skill

Instructions for the AI assistant...
EOF

# 2. Add to kit.json manifest
# Add an entry to the "skills" array:
#   {
#     "name": "my-new-skill",
#     "version": "0.1.0",
#     "description": "What this skill does",
#     "path": "skills/my-new-skill",
#     "files": ["SKILL.md"]
#   }

# 3. Commit and push
git add skills/my-new-skill/SKILL.md kit.json
git commit -m "Add my-new-skill skill (v0.1.0)"
git push
```

Users get the new skill on their next `kit update`. On every later
content change, bump the same `version` field in *both* `SKILL.md` and
`kit.json` — see [Versioning Strategy](#versioning-strategy).

### Adding a New Subagent

```bash
cd <project>-kit

# 1. Create the agent file
cat > agents/my-agent.md << 'EOF'
---
name: my-agent
version: "0.1.0"
description: Specialized agent for a specific task
model: sonnet
tools: [Bash, Read, Edit, Grep, Glob]
---

# My Agent

You specialize in...
EOF

# 2. Add to kit.json manifest
# Add an entry to the "agents" array:
#   {
#     "name": "my-agent",
#     "version": "0.1.0",
#     "description": "Specialized agent for a specific task",
#     "path": "agents/my-agent.md"
#   }

# 3. Commit and push
git add agents/my-agent.md kit.json
git commit -m "Add my-agent subagent (v0.1.0)"
git push
```

### Repository Visibility

- **Public repos** work with unauthenticated `git clone` — no extra setup needed.
- **Private repos** require the user to have git credentials configured (SSH key or credential helper). The kit command uses the system `git` binary, so any credential setup that works for `git clone` will work for `mori kit`.

### Versioning Strategy

The kit uses **two complementary signals** to tell a user whether what
they have installed is still what the kit publishes. Neither alone is
sufficient.

| Signal | Lives in | Maintained by | Catches |
|--------|----------|---------------|---------|
| Author-managed semver | `kit.json` and each `SKILL.md` frontmatter | Skill author bumps on every content change | The author shipped an intentional new version |
| Content hash | A per-install sidecar (`.kit.json`) written at install time | Computed automatically by `kit install` | Author edited content without bumping the version |

`kit status` consumes both signals through a single pure function
(`classify` in the implementation above) and reduces them to one of four
tokens:

| State | Meaning | What the user should do |
|-------|---------|------------------------|
| `up-to-date` | Installed version equals upstream version, and the upstream content hash matches the sidecar | Nothing |
| `outdated` | Installed version differs from a known upstream version | Run `kit update <name>` |
| `dirty` | Versions match (or upstream has no version yet) but the upstream content hash has changed | Re-install to refresh the snapshot |
| `unknown` | No sidecar (legacy install), no upstream entry (removed upstream), or no usable cache | Re-install if it's a legacy install; otherwise investigate |

**Precedence:** `unknown > outdated > dirty > up-to-date`. `unknown` always
wins because no comparison can anchor; among rows where a comparison is
possible, a deliberate version bump (`outdated`) is more actionable than
a content-only drift (`dirty`).

#### The two-version contract

Both `kit.json` *and* each item's frontmatter (e.g. `SKILL.md`'s YAML
header) carry the same `version` string. The CLI reads `kit.json`; humans
read the frontmatter when browsing the source repo. Authors must bump
*both* in the same commit; CI in the kit repo should fail a PR where
the two disagree. Use semver:

- Patch bump (`0.1.0 → 0.1.1`) for prose edits, typo fixes, clarification.
- Minor bump (`0.1.0 → 0.2.0`) for new sections, new examples, behavioral changes that remain backwards-compatible from a user's perspective.
- Major bump (`0.1.0 → 1.0.0`) for renames, removed sections, or workflow changes that meaningfully alter the user-facing surface.

#### The sidecar

`kit install` writes a `.kit.json` file next to each installed item.
For a skill at `<base>/.claude/skills/<name>/`, the sidecar lives at
`<base>/.claude/skills/<name>/.kit.json`. For an agent at
`<base>/.claude/agents/<name>.md`, the sidecar lives at
`<base>/.claude/agents/<name>.kit.json` (a sibling file, not inside a
directory).

The sidecar records the upstream `version` at install time, a
SHA-256 hash of the *upstream source bytes* at install time, and an
ISO-8601 UTC timestamp. Two design choices are load-bearing:

- **Hash the upstream files, not the destination files.** Hashing the
  destination would make the install-time hash equal whatever was just
  copied — drift detection would be a tautology.
- **The hash framing must be byte-stable across platforms.** Sort the
  file list, length-prefix each file, and separate fields with NUL
  bytes. See `computeKitHash` in the [Implementation](#implementation)
  section. Pin the algorithm with a unit test that asserts a known
  byte input produces a known hex digest — every caller (install,
  status, future tools) must produce the same output for identical
  upstream content.

#### Schema evolution

The top-level `version` field of `kit.json` is a separate axis. Bumping
it (e.g. `1 → 2` when introducing per-entry `version`) signals a breaking
schema change. The CLI declares per-entry `version` as `Maybe Text` so
v1 manifests parse cleanly and degrade — every row computed against a
v1 entry simply has `LATEST = -` and falls into the hash branch of
classification.

#### What this design does *not* catch

The content hash recorded in the sidecar is the hash of the *upstream*
source files at install time, not the destination files. Comparing it
against a fresh hash of the upstream therefore measures upstream drift,
not *local* drift — if a user manually edits their installed copy, the
status command will not detect it. Surfacing local edits would require a
second hash check against the destination tree and a fifth state token
(e.g. `local-edit`) or splitting `dirty` into `dirty-upstream` and
`dirty-local`. Treat that as a separate enhancement, not part of the
core pattern.

## Operational Properties

| Property | Behavior |
|----------|----------|
| **Idempotent install** | Re-installing overwrites with the latest cached version and rewrites the sidecar |
| **Idempotent uninstall** | Uninstalling something not installed prints a message, doesn't fail. Sidecar is removed alongside the item |
| **Idempotent update** | `git pull --ff-only` + re-copy of changed files + sidecar refresh |
| **Drift visibility** | `kit status` reports per-item state (`up-to-date`/`outdated`/`dirty`/`unknown`) against the live manifest |
| **Offline resilience** | Falls back to cached manifest if the remote is unreachable; when even the cache is missing, every row degrades to `unknown` |
| **No database** | All operations are filesystem + git; no connection string needed |
| **Disposable cache** | `~/.cache/<project>/kit/` can be deleted and will be re-cloned |
| **Disposable sidecar** | Deleting a `.kit.json` flips that row to `unknown`; re-installing brings it back |
| **Shallow clone** | Uses `--depth 1` to minimize bandwidth and disk usage |

## End-to-End Flow

```
1. User runs:  mycli kit install automation-config

2. CLI clones (or pulls) the kit repo to ~/.cache/<project>/kit/

3. CLI reads kit.json, finds "automation-config" in the skills array

4. CLI copies skills/automation-config/SKILL.md to:
   ~/.config/<project>/agents/.claude/skills/automation-config/SKILL.md
   …and writes a sibling sidecar:
   ~/.config/<project>/agents/.claude/skills/automation-config/.kit.json
   { name, kind, version (from manifest), hash (of upstream files), installedAt }

5. User runs:  mycli agent assist

6. CLI calls agentDirsForSession, which finds:
   ~/.config/<project>/agents/   (exists)

7. CLI builds:  claude --add-dir ~/.config/<project>/agents/ ...

8. Claude Code discovers .claude/skills/automation-config/SKILL.md
   inside the add-dir and makes /automation-config available as a
   slash command in the session
```

For a **multi-provider** kit (see [Provider-Neutral Kits](#provider-neutral-kits-claude-code--codex)),
step 4 also writes `./.agents/skills/automation-config/SKILL.md` (project scope) or
`$HOME/.agents/skills/...` (user scope), and a Codex session started in step 5 discovers
it through Codex's native `.agents/skills` scan rather than through `--add-dir`.

## When to Use This Pattern

- You distribute an AI-augmented CLI and want to ship reusable skills/agents separately from binary releases.
- You want users to install skills globally (shared across projects) or locally (scoped to one project).
- You want a lightweight distribution mechanism — no package manager, no database, just git + filesystem.
- Your skills/agents evolve faster than your binary releases and you want independent update cadence.

## When NOT to Use This Pattern

- If you only have 1-2 skills that ship with the binary, just embed them in your source repo.
- If skills require runtime code generation or depend on CLI version, they may need tighter coupling than a separate repo provides.
- If you need access control per-skill (some users get skill A but not skill B), you'll need a more sophisticated registry than a single git repo.

## Reference Implementation

**Single-provider (Claude Code) + versioning:**

- **Kit repo:** [mori-kit](https://github.com/shinzui/mori-kit)
- **CLI command:** `mori-cli/src/Mori/Command/Kit.hs` (~490 lines)
- **Agent session integration:** `mori-cli/src/Mori/Command/Agent.hs` (`agentDirsForSession`, `buildClaudeArgs`)
- **Help topic:** `mori-cli/help/kit.md`
- **Design doc:** `docs/plans/distributable-claude-skills.md`

**Multi-provider (Claude Code + Codex):**

- **Shared asset module:** `Baikai.AgentAssets` (in the `baikai` package) — owns the
  provider-native path layouts (`skillTargetPath`, `agentTargetPath`, `agentAssetFormat`)
  and the Codex custom-agent TOML renderer (`codexCustomAgentToml`, `CodexCustomAgent`).
- **Seihou:** `seihou-cli/src/Seihou/CLI/KitPaths.hs` (the `KitProviderLayout` wrapper over
  `Baikai.AgentAssets`) and `seihou-cli/src-exe/Seihou/CLI/Kit.hs` (`resolveProviderTargetDir`,
  provider-looped install/uninstall/status); design doc
  `seihou docs/plans/40-support-codex-kit-skills-and-agents.md`.
- **Rei:** `rei-cli/src/Rei/Cli/Commands/Kit/` (`Paths.hs` + `Handler.hs`); design doc
  `rei docs/plans/129-install-codex-native-kit-skills-and-agents.md` (under MasterPlan 13,
  the provider-neutral LLM initiative).
