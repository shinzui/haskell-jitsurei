---
type: Pattern
title: "Shell Completion Generation"
description: "Generate Bash, Zsh, and Fish completions from optparse-applicative parsers"
timestamp: 2026-03-12T11:33:00-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-shell-completions
tags: [cli, completions, bash, zsh, fish, optparse-applicative]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-03-12T11:33:00-07:00
    scope: catalog-metadata
    outcome: approved
---

# Shell Completion Generation

A pattern for generating Bash, Zsh, and Fish completion scripts that delegate to optparse-applicative's built-in completion protocol. Completions are derived automatically from the parser definitions — no manual command registry needed.

## Architecture

```
Completions/
├── Bash.hs        -- Bash script generator (plain protocol)
├── Zsh.hs         -- Zsh script generator (enriched protocol)
├── Fish.hs        -- Fish script generator (enriched protocol)
├── Handler.hs     -- Routes to the right generator
├── Parser.hs      -- optparse-applicative subparser
└── Completions.hs -- Re-export module
```

The CLI exposes a `completions` subcommand that outputs shell scripts to stdout:

```bash
myapp completions bash > ~/.local/share/bash-completion/completions/myapp
myapp completions zsh  > ~/.zfunc/_myapp    # or eval "$(myapp completions zsh)"
myapp completions fish > ~/.config/fish/completions/myapp.fish
```

## How It Works

The generated scripts delegate completion to the binary itself at runtime. When the user presses Tab, the shell invokes `myapp --bash-completion-index N --bash-completion-word ...` with the current command line. optparse-applicative walks its parser tree and returns matching completions.

This means **all commands, subcommands, and flags are completed automatically** from the parser definitions. Adding a new command to the parser is all that's needed — no separate command registry to maintain.

### Plain vs Enriched Protocol

optparse-applicative offers two completion protocols:

| Protocol | Flag | Output format | Use case |
|----------|------|---------------|----------|
| Plain | `--bash-completion-index` | One word per line | Bash (no description support) |
| Enriched | `--bash-completion-enriched` | `word\tdescription` per line | Zsh, Fish (show descriptions) |

## 1. Bash Generator

Bash does not support completion descriptions natively, so it uses the **plain protocol**.

```haskell
generateBashCompletion :: Text
generateBashCompletion =
  T.unlines
    [ "_myapp_completions() {",
      "    local CMDLINE",
      "    local IFS=$'\\n'",
      "    CMDLINE=(--bash-completion-index $COMP_CWORD)",
      "",
      "    for arg in ${COMP_WORDS[@]}; do",
      "        CMDLINE=(${CMDLINE[@]} --bash-completion-word \"$arg\")",
      "    done",
      "",
      "    COMPREPLY=( $(myapp \"${CMDLINE[@]}\" 2>/dev/null) )",
      "}",
      "",
      "complete -o filenames -F _myapp_completions myapp"
    ]
```

**How it works:**
- Passes `$COMP_CWORD` (cursor position) and `$COMP_WORDS` (current tokens) to the binary
- The binary returns matching completions, one per line
- `complete -o filenames` enables fallback file completion when no matches are found

## 2. Zsh Generator

Zsh uses the **enriched protocol** to show descriptions alongside completions via `_describe`.

```haskell
generateZshCompletion :: Text
generateZshCompletion =
  T.unlines
    [ "#compdef myapp",
      "",
      "_myapp() {",
      "    local -a completions",
      "    local CMDLINE",
      "    local IFS=$'\\n'",
      "",
      "    CMDLINE=(--bash-completion-enriched --bash-completion-index $((CURRENT - 1)))",
      "",
      "    for arg in ${words[@]}; do",
      "        CMDLINE=(${CMDLINE[@]} --bash-completion-word \"$arg\")",
      "    done",
      "",
      "    local line",
      "    for line in $(myapp \"${CMDLINE[@]}\" 2>/dev/null); do",
      "        local word=${line%%$'\\t'*}",
      "        local desc=${line#*$'\\t'}",
      "        if [[ \"$word\" != \"$desc\" ]]; then",
      "            completions+=(\"${word//:/\\\\:}:${desc}\")",
      "        else",
      "            completions+=(\"$word\")",
      "        fi",
      "    done",
      "",
      "    if [[ ${#completions[@]} -gt 0 ]]; then",
      "        _describe 'myapp' completions",
      "    fi",
      "}",
      "",
      "_myapp"
    ]
```

**How it works:**
- Uses `--bash-completion-enriched` to get `word\tdescription` pairs
- Parses tab-separated output: `${line%%$'\t'*}` extracts the word, `${line#*$'\t'}` extracts the description
- Escapes colons in words (`${word//:/\\:}`) since Zsh uses `:` as the word/description separator
- Falls back to plain words when no description is present (word equals desc after split)
- Uses `_describe` to display completions with descriptions

## 3. Fish Generator

Fish also uses the **enriched protocol**, parsing tab-separated output into its native description format.

```haskell
generateFishCompletion :: Text
generateFishCompletion =
  T.unlines
    [ "# Disable file completion by default",
      "complete -c myapp -f",
      "",
      "function __myapp_complete",
      "    set -l tokens (commandline -cop)",
      "    set -l current (commandline -ct)",
      "    set -l index (count $tokens)",
      "",
      "    set -l args --bash-completion-enriched --bash-completion-index $index",
      "    for token in $tokens",
      "        set args $args --bash-completion-word $token",
      "    end",
      "    set args $args --bash-completion-word \"$current\"",
      "",
      "    for line in (myapp $args 2>/dev/null)",
      "        # Split on tab: word<TAB>description",
      "        set -l parts (string split \\t -- $line)",
      "        if test (count $parts) -ge 2",
      "            printf '%s\\t%s\\n' $parts[1] $parts[2]",
      "        else",
      "            echo $line",
      "        end",
      "    end",
      "end",
      "",
      "complete -c myapp -a '(__myapp_complete)'"
    ]
```

**How it works:**
- `complete -c myapp -f` disables default file completion
- The `__myapp_complete` function builds the completion query from `commandline` state
- Splits enriched output on tab to extract word and description
- Outputs `word\tdescription` which Fish natively renders as completion with description
- Falls back to plain output when no tab separator is found

## 4. Handler

The handler routes to the appropriate generator — each generator is a pure `Text` value:

```haskell
data CompletionsCommand
  = CompletionsBash
  | CompletionsZsh
  | CompletionsFish

handleCompletionsCommand :: CompletionsCommand -> IO ()
handleCompletionsCommand = \case
  CompletionsBash -> TIO.putStrLn generateBashCompletion
  CompletionsZsh  -> TIO.putStrLn generateZshCompletion
  CompletionsFish -> TIO.putStrLn generateFishCompletion
```

Note that generators take no arguments — there is no command tree to pass in. The scripts delegate all completion logic to the binary at runtime.

## 5. Adding a New Command

Just add the command to your optparse-applicative parser. That's it — completions are derived automatically.

Rebuild and regenerate:
```bash
cabal build
myapp completions bash > ~/.local/share/bash-completion/completions/myapp
```

To get descriptions in Zsh and Fish, add `help` metadata to your parser options:

```haskell
command "archive" (info archiveParser (progDesc "Archive an intention"))
```

The `progDesc` text becomes the description shown in Zsh and Fish completions.

## Why Use optparse-applicative's Built-In Protocol?

| Aspect | Custom generator (old) | Built-in protocol |
|--------|----------------------|-------------------|
| Maintenance | Manual `Commands.hs` must stay in sync with parsers | Automatic — derived from parsers |
| New commands | Must update command registry | Just add to parser |
| Flag completion | Not supported | Automatic |
| Descriptions | Custom per-shell logic | Enriched protocol, parsed per-shell |
| Runtime dependency | Static script, no callbacks | Calls binary for each completion |
| Nesting depth | Explicit (typically 3 levels) | Unlimited — follows parser tree |

The tradeoff is that completions require the binary to be available at runtime (the shell calls it on each Tab press). In practice this is negligible — the binary is fast and the protocol is simple.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Delegate to binary via `--bash-completion-index` | Zero maintenance — completions always match the actual parser |
| Plain protocol for Bash | Bash has no native description display; enriched output would be ignored |
| Enriched protocol for Zsh and Fish | Both shells display descriptions natively (`_describe` / tab format) |
| Parse `word\tdescription` in shell scripts | Keeps Haskell generators simple — each is a static `Text` constant |
| `complete -o filenames` for Bash | Enables file path fallback when the binary returns no matches |
| `complete -c myapp -f` for Fish | Disables default file completion; the binary controls what's offered |
| Escape colons in Zsh words | Zsh uses `:` as the word/description separator in `_describe` |
