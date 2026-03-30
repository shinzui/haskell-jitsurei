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
  "version": 1,
  "skills": [
    {
      "name": "automation-config",
      "description": "Author, validate, and debug mori automation configurations",
      "path": "skills/automation-config",
      "files": ["SKILL.md"]
    },
    {
      "name": "mori-config",
      "description": "Author, validate, and edit mori.dhall project configurations",
      "path": "skills/mori-config",
      "files": ["SKILL.md"]
    }
  ],
  "agents": [
    {
      "name": "automation-author",
      "description": "Specialized agent for writing and debugging automation configs",
      "path": "agents/automation-author.md"
    }
  ]
}
```

**Design decisions:**

| Field | Purpose |
|-------|---------|
| `version` | Manifest schema version, for forward compatibility |
| `skills[].path` | Relative path to the skill directory in the repo |
| `skills[].files` | Explicit file list — avoids hidden-file surprises, supports multi-file skills |
| `agents[].path` | Relative path to the single agent markdown file |

The manifest is the source of truth for `kit list`. It is parsed via `FromJSON` with no custom instances — field names match JSON keys exactly.

### 3. Skill Format (Claude Code)

Each skill is a directory containing at minimum a `SKILL.md` with YAML frontmatter:

```yaml
---
name: automation-config
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
mycli kit status                        # Show installed items with scope
```

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
  { version :: !Int
  , skills :: ![SkillEntry]
  , agents :: ![AgentEntry]
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data SkillEntry = SkillEntry
  { name :: !Text
  , description :: !Text
  , path :: !Text          -- relative path in repo (e.g., "skills/foo")
  , files :: ![Text]       -- files to copy (e.g., ["SKILL.md"])
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data AgentEntry = AgentEntry
  { name :: !Text
  , description :: !Text
  , path :: !Text          -- relative path to the .md file
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)
```

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

-- Install: copy files from cache to target
doInstall :: FilePath -> KitItem -> KitScope -> IO ()
doInstall repoDir (KitSkillItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let targetDir = targetBase </> ".claude" </> "skills" </> T.unpack (name entry)
  createDirectoryIfMissing True targetDir
  mapM_ (copySkillFile repoDir entry targetDir) (files entry)
doInstall repoDir (KitAgentItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let agentDir = targetBase </> ".claude" </> "agents"
  createDirectoryIfMissing True agentDir
  copyFile (repoDir </> T.unpack (path entry))
           (agentDir </> takeFileName (T.unpack (path entry)))
```

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

No new library dependencies. Uses only:

| Module | Purpose |
|--------|---------|
| `System.Process` | Running `git clone` and `git pull` |
| `System.Directory` | Directory creation, existence checks, file copying |
| `Data.Aeson` | Parsing `kit.json` (already a dependency) |
| `Options.Applicative` | Command parsing (already a dependency) |

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
  "version": 1,
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
#     "description": "What this skill does",
#     "path": "skills/my-new-skill",
#     "files": ["SKILL.md"]
#   }

# 3. Commit and push
git add skills/my-new-skill/SKILL.md kit.json
git commit -m "Add my-new-skill skill"
git push
```

Users get the new skill on their next `kit update`.

### Adding a New Subagent

```bash
cd <project>-kit

# 1. Create the agent file
cat > agents/my-agent.md << 'EOF'
---
name: my-agent
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
#     "description": "Specialized agent for a specific task",
#     "path": "agents/my-agent.md"
#   }

# 3. Commit and push
git add agents/my-agent.md kit.json
git commit -m "Add my-agent subagent"
git push
```

### Repository Visibility

- **Public repos** work with unauthenticated `git clone` — no extra setup needed.
- **Private repos** require the user to have git credentials configured (SSH key or credential helper). The kit command uses the system `git` binary, so any credential setup that works for `git clone` will work for `mori kit`.

### Versioning Strategy

The manifest has a `version` field for forward compatibility. The current convention:

- **Version 1:** The format described in this document.
- Bumping the version allows the CLI to detect incompatible manifests and print an upgrade message.
- Content itself is unversioned — `kit update` always installs the latest from the default branch.

## Operational Properties

| Property | Behavior |
|----------|----------|
| **Idempotent install** | Re-installing overwrites with the latest cached version |
| **Idempotent uninstall** | Uninstalling something not installed prints a message, doesn't fail |
| **Idempotent update** | `git pull --ff-only` + re-copy of changed files |
| **Offline resilience** | Falls back to cached manifest if GitHub is unreachable |
| **No database** | All operations are filesystem + git; no connection string needed |
| **Disposable cache** | `~/.cache/<project>/kit/` can be deleted and will be re-cloned |
| **Shallow clone** | Uses `--depth 1` to minimize bandwidth and disk usage |

## End-to-End Flow

```
1. User runs:  mycli kit install automation-config

2. CLI clones (or pulls) the kit repo to ~/.cache/<project>/kit/

3. CLI reads kit.json, finds "automation-config" in the skills array

4. CLI copies skills/automation-config/SKILL.md to:
   ~/.config/<project>/agents/.claude/skills/automation-config/SKILL.md

5. User runs:  mycli agent assist

6. CLI calls agentDirsForSession, which finds:
   ~/.config/<project>/agents/   (exists)

7. CLI builds:  claude --add-dir ~/.config/<project>/agents/ ...

8. Claude Code discovers .claude/skills/automation-config/SKILL.md
   inside the add-dir and makes /automation-config available as a
   slash command in the session
```

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

- **Kit repo:** [mori-kit](https://github.com/shinzui/mori-kit)
- **CLI command:** `mori-cli/src/Mori/Command/Kit.hs` (~490 lines)
- **Agent session integration:** `mori-cli/src/Mori/Command/Agent.hs` (`agentDirsForSession`, `buildClaudeArgs`)
- **Help topic:** `mori-cli/help/kit.md`
- **Design doc:** `docs/plans/distributable-claude-skills.md`
