---
type: Pattern
title: "Agent Assist Commands"
description: "Expose live project context to coding agents through inspectable CLI commands"
timestamp: 2026-03-26T07:05:37-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-agent-assist-commands
tags: [cli, agents, context, prompts, automation, assistant]
status: current
---

# Pattern: Agent Assist Commands

**Dynamically providing project context to AI coding assistants from your CLI.**

## Problem

AI coding assistants (Claude Code, Cursor, etc.) work best when they understand your project's structure, conventions, dependencies, and available tooling. Static documentation (CLAUDE.md, README) helps, but it can't capture live state — the current registry of projects, resolved dependency paths, schema definitions, or user-specific configuration.

## Solution

Build CLI commands that **query live project state** and **assemble a structured system prompt**, then either:

1. **Launch an AI session** with that prompt injected (`--append-system-prompt`)
2. **Print the prompt** for debugging or piping into other tools (`--debug` flag)

The CLI becomes a context bridge between your project's runtime knowledge and the AI assistant.

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

### 4. Tool Permissions (Allowlists)

When launching an AI session, scope the tools it can use. Different commands warrant different permission sets:

```
# Bootstrap: needs to create files, run init commands
allowedTools = ["Write", "Bash(mycli init)", "Bash(mycli validate)", ...]

# Assist: needs build tools, git, broader access
allowedTools = ["Edit", "Bash(cabal build *)", "Bash(git *)", ...]
```

This is defense-in-depth — the AI session gets only the tools relevant to its task.

### 5. AI Session Launch

Spawn the AI CLI as a subprocess with the assembled prompt:

```
claude --permission-mode acceptEdits \
       --allowedTools "Read" "Edit" "Write" "Bash(mycli *)" \
       --append-system-prompt "{prompt}"
```

Key details:
- Use `--append-system-prompt` (not `--system-prompt`) to add context without replacing the AI's base instructions
- Forward Ctrl-C to the subprocess (`delegate_ctlc` / signal forwarding)
- Propagate the subprocess exit code

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

5. **Scope tool permissions** — define allowlists per command variant. Only grant what's needed.

6. **Support pre-seeding** — accept CLI flags that skip interactive questions (e.g., `--namespace`, `--name`). Encode these as conditional sections in the prompt.

7. **Wire up the subprocess** — launch the AI CLI with `--append-system-prompt`, forward signals, propagate exit codes.

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
| **Inline Haskell strings** (mori) | Single file, no TH, direct string interpolation | Hard to read/edit large prompts, noisy diffs |
| **File-embed templates** (rei) | Clean separation, markdown tooling works, non-Haskell contributors can edit | TH compile dependency, paths must stay in sync |

Both are valid. Start inline for short prompts (< 50 lines). Move to file-embed when prompts grow large or when you want non-developers to iterate on prompt wording.

## Design Considerations

**Prompt size vs. completeness**: Every token in the system prompt reduces the AI's working context. Include what's necessary, link to files for the rest. For example, include a command reference but let the AI `cat` full docs on demand.

**Freshness**: The prompt is assembled at launch time. If registry state changes mid-session, the prompt is stale. For most workflows this is fine — sessions are short-lived.

**Schema rendering**: If your project uses a schema language (Dhall, JSON Schema, Protobuf), build a compact "agent-optimized" renderer that produces a concise type reference. A full schema dump wastes context; a curated summary gives the AI what it needs.

**Multiple roles**: If your project has different agent roles (developer, reviewer, ops), let the config declare them with include/exclude path patterns, and build role-specific context.

## Example: Mori's Implementation

Mori implements this pattern across three commands:

- `mori agent assist` — launches Claude with full project context (config, conventions, deps, schema tools)
- `mori agent bootstrap` — launches Claude to guide new project setup (workflow steps, schema reference, registry snapshot, examples)
- `mori agent context <role>` — outputs JSON context for a configured agent role (paths, deps, standards, cookbooks)

The context assembly queries a PostgreSQL registry for project/package data, loads Dhall configuration from disk, resolves dependency paths through the registry, and renders a structured schema catalog — all assembled into a single system prompt that gives Claude deep understanding of the project it's working in.
