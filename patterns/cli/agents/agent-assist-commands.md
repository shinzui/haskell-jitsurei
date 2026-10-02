---
type: Pattern
title: "Agent Assist Commands"
description: "Expose live project context through inspectable commands and launch coding sessions with Baikai and baikai-kit"
timestamp: 2026-10-02T13:18:57Z
generated:
  by: human:nadeem
  at: 2026-03-26T14:05:37Z
resource: mori://shinzui/haskell-jitsurei/docs/cli-agent-assist-commands
tags: [cli, agents, context, prompts, automation, assistant, baikai, kit]
status: current
---

# Pattern: Agent Assist Commands

**Dynamically providing project context to AI coding assistants from your CLI.**

## Problem

AI coding assistants (Claude Code, Cursor, etc.) work best when they understand your project's structure, conventions, dependencies, and available tooling. Static documentation (CLAUDE.md, README) helps, but it can't capture live state — the current registry of projects, resolved dependency paths, schema definitions, or user-specific configuration.

## Solution

Build CLI commands that **query live project state** and **assemble a structured system prompt**, then either:

1. **Launch an AI session** through Baikai with the assembled context
2. **Print the prompt** for debugging or piping into other tools (`--debug` flag)

The CLI becomes a context bridge between your project's runtime knowledge and the AI assistant.
Use [Baikai's interactive launchers](mori://shinzui/baikai/docs/interactive-launches)
for terminal sessions and [baikai-kit](skill-and-agent-registry.md) for installed
asset discovery. Keep context assembly in the application and provider argument
construction in Baikai.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  CLI Command │────▶│ Context      │────▶│ System Prompt   │
│  (user runs) │     │ Assembly     │     │ (markdown text) │
└─────────────┘     └──────────────┘     └────────┬────────┘
                           │                       │
                    ┌──────┴──────┐          ┌─────▼─────┐
                    │ Live Data   │          │ AI Session │
                    │ Sources     │          │ (claude)   │
                    ├─────────────┤          └───────────┘
                    │ • Config    │
                    │ • Registry  │
                    │ • Schema    │
                    │ • Deps      │
                    └─────────────┘
```

## Key Components

### 1. The Command Entry Point

A subcommand (e.g., `mycli agent assist`) that:

- Loads project configuration from disk
- Queries databases/registries for live state
- Builds a prompt string
- Launches the AI tool as a subprocess (or prints the prompt in debug mode)

```
mycli agent assist          # Launch Claude with project context
mycli agent assist --debug  # Print the system prompt instead
mycli agent bootstrap       # Launch Claude for project setup workflow
```

The `--debug` flag is essential — it lets you inspect, iterate on, and test prompts without starting an AI session.

### 2. Context Assembly

Gather data from multiple sources and render it into a single markdown prompt:

| Source | What it provides | Example |
|--------|-----------------|---------|
| Project config file | Name, language, type, conventions | `mori.dhall`, `package.json` |
| Schema catalog | Type definitions the AI needs to write valid config | Dhall types, JSON Schema |
| Registry/database | Known projects, packages, dependency graph | "These projects exist and can be referenced" |
| Dependency resolver | Resolved paths to dependency source code | "rei is at /home/user/projects/rei" |
| Filesystem | Current working directory, project root | Anchors relative paths |

### 3. Prompt Structure

The assembled prompt follows a consistent markdown structure:

```markdown
# {Tool Name} Project Context

You are assisting with the {project} project, a {description}.

## Project Identity
- Name: {name}
- Language: {language}
- Root: {path}

## Package Structure
- {package}/ — {description}

## Key Conventions
- {convention 1}
- {convention 2}

## Available CLI Commands
- mycli {cmd} — {description}

## Resolved Dependencies
- {dep} → {path}
  Packages: {pkg1} ({path1}), {pkg2} ({path2})
```

Key prompt design principles:
- **Structured sections** with markdown headers — AI models parse these well
- **Concrete values** not abstractions — resolved paths, actual names, real commands
- **Actionable references** — commands the AI can run, files it can read
- **Minimal but sufficient** — every token costs context window space

### 4. Provider-specific launch policy

Resolve provider, model, and effort using
[Per-Command Agent Configuration](per-command-agent-config.md). Express launch
policy through `InteractiveSafety`: `ClaudeAllowedTools` for Claude or
`CodexSandbox` with an explicit approval policy for Codex. The launchers refuse
a policy the selected provider cannot express before starting a process.
Handle that `Left`; do not turn refusal into an unrestricted retry.

### 5. AI Session Launch

Build a request through `interactiveLaunchRequest`, attach kit assets, and
dispatch to `launchClaudeInteractive` or `launchCodexInteractive`:

```haskell
import Baikai.Interactive qualified as Interactive
import Baikai.Kit qualified as Kit
import Data.Text (Text)

assistRequest
  :: Kit.KitConfig
  -> Interactive.InteractiveProvider
  -> Interactive.InteractiveSafety
  -> Text
  -> Text
  -> IO Interactive.InteractiveLaunchRequest
assistRequest kitConfig provider launchSafety context prompt = do
  let request = (Interactive.interactiveLaunchRequest prompt)
        { Interactive.systemPrompt = Just context
        , Interactive.safety = launchSafety
        }
  case provider of
    Interactive.InteractiveClaude -> do
      dirs <- Kit.agentDirsForSession kitConfig
      pure request { Interactive.extraDirs = dirs }
    Interactive.InteractiveCodex -> do
      args <- Kit.codexSessionArgs kitConfig
      pure request { Interactive.extraArgs = args }
```

The Codex branch's `codexSessionArgs` requires the visibility implementation
described in the kit pattern's [version boundary](skill-and-agent-registry.md#version-boundary).
It is required on every Codex launch to re-enable tool-only kit skills;
`--add-dir` alone grants access without loading them. Use the same kit config
and project-root resolver for install and launch.

`systemPrompt` is a Baikai request field with provider-specific semantics:
Claude's interactive builder renders `--system-prompt`, while Codex includes
the context before the user prompt. If preserving Claude's default instructions
by appending is an application requirement, inspect the current launcher and
use its supported argument escape hatch deliberately; do not assume the neutral
field means `--append-system-prompt`.

Baikai owns process launch and the `--` separator before a positional prompt,
including the greedy-Claude-option workaround previously kept in a standalone
pattern. Use its pure command builders to inspect the result. Interactive
launchers return a render refusal or a launch result carrying the exit code;
propagate the child exit code at the application's boundary.

For a single returned response use `completeRequest`/`streamRequest`. For an
unattended coding task that edits a workspace, use
[Baikai's agent-run surface](mori://shinzui/baikai/docs/unattended-agent-runs).
Those workflows have separate request and policy types.

## Variants

### Assist (development context)

For day-to-day development work on an existing project. The prompt includes:

- Full project identity and structure
- Build system details and conventions
- Resolved dependency locations (so the AI can read dependency source code)
- Available CLI commands
- Schema tools for config editing

### Bootstrap (guided setup)

For creating a new project from scratch. The prompt includes:

- Step-by-step workflow instructions ("guide the user through these steps")
- Schema reference (so the AI can write valid config)
- Registry snapshot (so the AI can suggest existing projects as dependencies)
- Best practices and examples
- Pre-seeded values from CLI flags (skip questions the user already answered)

```
mycli agent bootstrap --namespace acme --name widget
# AI skips asking for namespace/name, proceeds to next step
```

### Context (JSON output)

For programmatic consumption — outputs structured JSON instead of launching a session:

```
mycli agent context developer
# Outputs: { "role": "developer", "project": "...", "includePaths": [...], ... }
```

This enables integration with other tools, editors, or custom AI workflows.

## Implementation Checklist

For CLI authors wanting to add agent assist commands:

1. **Identify your live data sources** — what does your CLI know at runtime that static docs don't capture? (registry state, resolved paths, schema types, config values)

2. **Build a context assembly function** — takes config + queried data, returns a markdown string. Keep it pure (easy to test, easy to `--debug`).

3. **Design prompt sections** — structured markdown with headers. Include:
   - Project identity (name, language, type)
   - File/package structure
   - Coding conventions specific to this project
   - Available CLI commands the AI should use
   - Resolved dependencies with paths
   - Schema/type references if the AI needs to write config

4. **Add a `--debug` flag** — prints the prompt to stdout instead of launching a session. Essential for iteration.

5. **Select launch policy** — express the command's policy through the chosen provider's Baikai safety type.

6. **Support pre-seeding** — accept CLI flags that skip interactive questions (e.g., `--namespace`, `--name`). Encode these as conditional sections in the prompt.

7. **Wire the Baikai launcher** — attach kit directories or Codex session arguments, handle render refusals, and propagate exit codes.

8. **Add a JSON variant** — `agent context <role>` for programmatic access to the same data.

## Scaling Prompts with File-Embed and Template Substitution

As prompt complexity grows, embedding large markdown templates as Haskell string literals becomes unwieldy. The **file-embed + substitution** pattern separates prompt authoring from code:

1. **Write prompts as standalone `.md` files** with `{{variable}}` placeholders
2. **Embed them at compile time** using `file-embed`'s Template Haskell splices
3. **Substitute variables** at runtime with a simple `foldl' Text.replace` pass

This keeps prompts readable, diffable, and editable by non-Haskell contributors while still compiling them into the binary.

### Prompt Template Files

Store templates alongside the module that uses them:

```
src/MyApp/Agent/prompts/
├── assist.md
├── bootstrap.md
├── coach.md
└── review.md
```

Each file is plain markdown with `{{placeholder}}` markers for dynamic values:

```markdown
# Project Assistant

You are assisting with the {{project_name}} project.

**Current time:** {{local_time}} ({{timezone}})

## Active Tasks ({{task_count}} total)
{{tasks}}

## Available Commands
- mycli build — Build the project
- mycli test — Run tests
```

### Compile-Time Embedding

Use `Data.FileEmbed.embedStringFile` to bake templates into the binary at compile time — no runtime file I/O, no missing-file errors in production:

```haskell
{-# LANGUAGE TemplateHaskell #-}

import Data.FileEmbed (embedStringFile)

defaultAssistPrompt :: Text
defaultAssistPrompt = $(embedStringFile "src/MyApp/Agent/prompts/assist.md")

defaultBootstrapPrompt :: Text
defaultBootstrapPrompt = $(embedStringFile "src/MyApp/Agent/prompts/bootstrap.md")
```

The path is relative to the package root (where the `.cabal` file lives). Add `file-embed` to `build-depends`.

### Runtime Substitution

A simple `foldl'` over `Text.replace` handles variable substitution — no template engine needed:

```haskell
substituteVariables :: Text -> [(Text, Text)] -> Text
substituteVariables template vars =
  foldl' (\t (key, val) -> T.replace key val t) template vars
```

Build the substitution list from your live data:

```haskell
buildPrompt :: ProjectConfig -> IO Text
buildPrompt cfg = do
  now <- getCurrentTime
  tasks <- queryActiveTasks
  let vars =
        [ ("{{project_name}}", cfg ^. #name)
        , ("{{local_time}}", formatTime now)
        , ("{{timezone}}", cfg ^. #timezone)
        , ("{{task_count}}", T.pack (show (length tasks)))
        , ("{{tasks}}", formatTasks tasks)
        ]
  pure $ substituteVariables defaultAssistPrompt vars
```

### Structured Variables Record

For prompts with many placeholders, define a record instead of a raw list. This catches missing variables at compile time:

```haskell
data PromptVariables = PromptVariables
  { projectName :: !Text
  , localTime :: !Text
  , timezone :: !Text
  , taskCount :: !Int
  , tasks :: !Text
  , blockers :: !Text
  , customVars :: !(Map Text Text)  -- escape hatch for extensibility
  }
  deriving stock (Generic)

toSubstitutions :: PromptVariables -> [(Text, Text)]
toSubstitutions vars =
  [ ("{{project_name}}", vars ^. #projectName)
  , ("{{local_time}}", vars ^. #localTime)
  , ("{{timezone}}", vars ^. #timezone)
  , ("{{task_count}}", T.pack (show (vars ^. #taskCount)))
  , ("{{tasks}}", vars ^. #tasks)
  , ("{{blockers}}", vars ^. #blockers)
  ]
  ++ [("{{" <> k <> "}}", v) | (k, v) <- Map.toList (vars ^. #customVars)]
```

### Workspace Overrides (Optional)

For user-customizable prompts, add a two-track loading pattern: try loading from a workspace directory first, fall back to the compiled-in default:

```haskell
loadPrompt :: FilePath -> Text -> Text -> IO Text
loadPrompt workspaceDir templateName builtinDefault = do
  let filePath = workspaceDir </> "prompts" </> T.unpack templateName <> ".md"
  exists <- doesFileExist filePath
  if exists
    then TIO.readFile filePath
    else pure builtinDefault
```

This lets power users customize prompts without recompiling, while the embedded defaults ensure the tool always works out of the box.

### Why Not a Real Template Engine?

The `{{variable}}` + `Text.replace` approach is deliberately simple:

- **No logic in templates** — all computation happens in formatters *before* substitution. Templates are "dumb" text with holes.
- **No dependencies** — no mustache/inja/jinja parser to maintain.
- **Deterministic** — rendering is a pure function of (template, variables). No I/O during substitution.
- **Good enough** — prompt templates don't need conditionals or loops. If a section should be omitted, the formatter returns `""` for that variable.

If you later need computed values (dates, counters), add a **helper registry** pattern where `{{date.iso}}` or `{{time.hm}}` are resolved by registered functions rather than static lookups.

### Contrast: Inline vs. File-Embed

| Approach | Pros | Cons |
|----------|------|------|
| **Inline Haskell strings** | Single file, no TH, direct string interpolation | Hard to read/edit large prompts, noisy diffs |
| **File-embed templates** | Clean separation, markdown tooling works, non-Haskell contributors can edit | TH compile dependency, paths must stay in sync |

Both are valid. Start inline for short prompts (< 50 lines). Move to file-embed when prompts grow large or when you want non-developers to iterate on prompt wording.

## Design Considerations

**Prompt size vs. completeness**: Every token in the system prompt reduces the AI's working context. Include what's necessary, link to files for the rest. For example, include a command reference but let the AI `cat` full docs on demand.

**Freshness**: The prompt is assembled at launch time. If registry state changes mid-session, the prompt is stale. For most workflows this is fine — sessions are short-lived.

**Schema rendering**: If your project uses a schema language (Dhall, JSON Schema, Protobuf), build a compact "agent-optimized" renderer that produces a concise type reference. A full schema dump wastes context; a curated summary gives the AI what it needs.

**Multiple roles**: If your project has different agent roles (developer, reviewer, ops), let the config declare them with include/exclude path patterns, and build role-specific context.

## Example: Live context from Mori

The command family in [Mori](mori://shinzui/mori) illustrates the context surfaces:

- `mori agent assist` — launches Claude with full project context (config, conventions, deps, schema tools)
- `mori agent bootstrap` — launches Claude to guide new project setup (workflow steps, schema reference, registry snapshot, examples)
- `mori agent context <role>` — outputs JSON context for a configured agent role (paths, deps, standards, cookbooks)

Keep durable dependency references in generated context as canonical `mori://`
URIs alongside any runtime-resolved local paths. The prompt remains useful across
machines, while local paths let the current session read source directly.
