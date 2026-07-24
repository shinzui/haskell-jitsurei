---
type: Gotcha
title: "Invoking the claude CLI as a Subprocess"
description: "Avoid prompt swallowing, hangs, and regressions when a Haskell CLI invokes Claude Code"
timestamp: 2026-05-15T09:45:12-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-claude-cli-pitfalls
tags: [cli, agents, claude, subprocess, add-dir, testing]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-05-15T09:45:12-07:00
    scope: catalog-metadata
    outcome: approved
---

# Pitfalls: Invoking the `claude` CLI as a Subprocess

**Known traps when a Haskell CLI shells out to `claude -p` (Claude Code's
non-interactive mode). Save yourself the multi-hour debug.**

This is a living list. Each entry names the trap, the failure mode, and
the fix. Tested against `claude` v2.1.140; older versions may differ.

---

## 1. `--add-dir` Greedily Eats the Positional Prompt (No `--` Terminator)

### Symptom

You build an argv that ends with the user prompt as a positional
argument, like:

```
claude -p --output-format json
       --append-system-prompt <SKILL.md>
       --model haiku
       --add-dir /path/to/kit
       --add-dir /path/to/kit/.agents
       <USER_PROMPT>
```

Two failure modes depending on prompt size:

- **Small prompt:** `claude` exits with `Error: Input must be provided
  either through stdin or as a prompt argument when using --print`.
- **Large prompt** (multi-KB markdown / JSON, e.g. a plan file):
  `claude` **hangs indefinitely** — zero stdout, zero stderr, ~zero
  CPU. `lsof` shows the HTTP client thread parked but no active TCP
  connections. The request to the API is never sent.

### Cause

`claude`'s argument parser treats `--add-dir` as a **variadic / greedy
multi-value option**. Without an explicit `--` separator, the *last*
`--add-dir` consumes every following non-flag token as additional
allowed-directory paths — including your positional user prompt.

After that, `--print` mode has no positional input left:

- A short prompt is interpreted as a (silly but short) path; validation
  fails and you get the "Input must be provided" error.
- A multi-KB prompt is handed to whatever path-validation routine
  `claude` runs on `--add-dir` values. With a 40 KB pseudo-path that
  routine silently never returns. Net effect: hang.

### Fix

**Insert `"--"` between your last flag and the positional prompt.**

```haskell
let args =
      [ "-p"
      , "--output-format", "json"
      , "--append-system-prompt", systemPrompt
      ]
        <> maybe [] (\m -> ["--model", m]) mModel
        <> concat [["--add-dir", d] | d <- addDirs]
        <> extraArgs
        <> ["--", userPrompt]   -- ← terminator before positional prompt
```

The `--` tells the parser "no more flags follow"; the next token is
unambiguously the positional prompt regardless of how `--add-dir` is
declared internally.

### Alternative: feed the prompt via stdin

If you don't want to depend on `--`'s parsing semantics, drop the
positional argument entirely and pipe the prompt in:

```haskell
import System.Process.Typed

let pc = proc "claude" args      -- args without the trailing prompt
        & setStdin (byteStringInput (encodeUtf8 userPrompt))
        & setStdout byteStringOutput
runProcess pc
```

`claude -p` reads from stdin when no positional prompt is supplied.
Stdin is also the only sane channel for prompts approaching `ARG_MAX`
(256 KB on macOS, ~2 MB on Linux); cmdline overflow surfaces as
`E2BIG` from `execve`, which the typed-process layer converts to an
unhelpful exception.

### Why a comment is mandatory

A future reader who sees `["--", userPrompt]` will be tempted to delete
the `"--"` as cruft. They'll then ship a regression that's invisible
to unit tests (which usually stub the subprocess) and only surfaces on
a real run with a real prompt. **Leave a one-line comment naming the
greedy `--add-dir` behaviour** so the workaround survives refactors:

```haskell
-- `claude -p` parses --add-dir as variadic; without `--` it greedily
-- eats the positional prompt as another add-dir path, leaving -p with
-- no input (errors on short prompts, hangs on large ones).
<> ["--", userPrompt]
```

### How to confirm in your own repro

If you suspect a hang has the same shape, capture the actual argv
`claude` was invoked with by wrapping the binary:

```bash
mkdir -p /tmp/claude-wrap
cat > /tmp/claude-wrap/claude <<'EOF'
#!/usr/bin/env bash
ts=$(date +%s); log=/tmp/claude-wrap/call-$ts
{ echo "ARGV_COUNT=$#"; for a in "$@"; do echo "LEN=${#a}"; done; } > "$log.meta"
i=1; for a in "$@"; do printf '%s' "$a" > "$log.argv.$i"; i=$((i+1)); done
exec /path/to/real/claude "$@"
EOF
chmod +x /tmp/claude-wrap/claude
PATH=/tmp/claude-wrap:$PATH yourcli your-command
```

Then replay the captured args directly to `claude` to confirm the hang
reproduces outside your CLI. If inserting `"--"` before the positional
arg flips the result from hang → success, you've hit this trap.

### Tests don't catch this

The bug is in the *cmdline contract* between your CLI and `claude`,
not in your code's logic. Unit tests that stub `roRunProcess` /
`createProcess` see only the argv your code produced — they cannot
observe how `claude`'s parser will interpret it. Coverage for this
class of bug requires either:

- An integration test that actually spawns `claude` (slow, requires
  auth, hits the API), or
- A contract assertion: "the argv mina builds for `claude -p` ends
  with `[\"--\", prompt]`." Cheap, catches regressions on the same
  surface.

The latter is what to add when you fix this; an example:

```haskell
it "terminates argv with `--` before the positional prompt" $ do
  argv <- captureArgv $ runCachedSkill skill tid "hello" [] opts
  argv `shouldSatisfy` (\xs -> length xs >= 2
                            && xs !! (length xs - 2) == "--"
                            && last xs == "hello")
```
