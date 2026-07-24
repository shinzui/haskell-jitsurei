---
type: Pattern
title: "Stdin Integration for CLI Commands"
description: "Resolve CLI text input through arguments, piped stdin, files, editors, and prompts"
timestamp: 2026-03-09T08:00:34-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-stdin-integration
tags: [cli, stdin, piping, editor, input]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-03-09T08:00:34-07:00
    scope: catalog-metadata
    outcome: approved
---

# Stdin Integration for CLI Commands

A pattern for accepting input from both positional arguments and piped stdin, with fallback chains to editors or interactive prompts. Plays nicely with fzf integration (see `fzf-integration.md`).

## Core Utility Module

A small module detects whether stdin is piped and implements the argument/stdin fallback:

```haskell
module Cli.Stdin
  ( getTextInput,
    isStdinPiped,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.IO (hIsTerminalDevice, stdin)

-- | True when stdin is piped (not a terminal)
isStdinPiped :: IO Bool
isStdinPiped = not <$> hIsTerminalDevice stdin

-- | Get text from CLI argument or piped stdin.
--   Argument wins. If no argument and stdin is piped, reads it.
--   Returns Nothing when interactive (no argument, no pipe).
getTextInput :: Maybe Text -> IO (Maybe Text)
getTextInput (Just arg) = pure $ Just arg
getTextInput Nothing = do
  piped <- isStdinPiped
  if piped
    then do
      content <- TIO.getContents
      let trimmed = T.strip content
      if T.null trimmed
        then pure Nothing
        else pure $ Just trimmed
    else pure Nothing
```

Key design:
- **Argument takes priority** — if the user passes a value on the command line, stdin is never read
- **Auto-detect piped input** — no `--stdin` flag needed for simple text arguments
- **Empty pipe = Nothing** — whitespace-only stdin is treated as absent
- **Interactive = Nothing** — when stdin is a terminal, returns immediately so the caller can fall back to an editor or prompt

## Pattern 1: Optional Positional Argument + Stdin

The most common pattern. A command takes an optional positional argument; if absent, reads from stdin; if neither, prints an error.

### Parser

```haskell
data RecordData = RecordData
  { description :: !(Maybe Text)
  , ...
  }

recordParser :: Parser RecordData
recordParser = RecordData
  <$> optional (strArgument
        (metavar "DESCRIPTION" <> help "Description (or pipe from stdin)"))
  <*> ...
```

The argument is `optional` — `Nothing` when omitted.

### Handler

```haskell
import Cli.Stdin (getTextInput)

handleRecord :: RecordData -> IO ()
handleRecord RecordData{description} = do
  mDescription <- getTextInput description
  case mDescription of
    Nothing -> putStrLn "Error: Description required (provide as argument or pipe from stdin)"
    Just desc -> doRecord desc
```

### Usage

```bash
# Positional argument
myapp action record "Finished the API"

# Piped from stdin
echo "Finished the API" | myapp action record

# From a file
myapp action record < notes.txt

# Error: interactive terminal, no argument
myapp action record
# → Error: Description required (provide as argument or pipe from stdin)
```

This pattern is used across many commands: `action record`, `outcome record`, `blocker declare`, `reminder create`, `intention create`, `habit declare-blocker`, and others.

## Pattern 2: Explicit `--stdin` Flag with Input Source ADT

For commands with richer input sources (editor, file, content flag, stdin), use a sum type to represent the source and an explicit `--stdin` flag.

### Types

```haskell
data GuidanceInput
  = GuidanceFromEditor        -- Open in $EDITOR (default)
  | GuidanceFromContent !Text -- Direct content via --content
  | GuidanceFromFile !FilePath -- Read from file via --file
  | GuidanceFromStdin         -- Read from stdin via --stdin
```

### Parser

```haskell
guidanceInputParser :: Parser GuidanceInput
guidanceInputParser =
  contentOption <|> fileOption <|> stdinOption <|> pure GuidanceFromEditor
  where
    contentOption =
      GuidanceFromContent
        <$> strOption (long "content" <> short 'c' <> metavar "TEXT"
              <> help "Set content directly")
    fileOption =
      GuidanceFromFile
        <$> strOption (long "file" <> short 'f' <> metavar "PATH"
              <> help "Read content from file")
    stdinOption =
      flag' GuidanceFromStdin
        (long "stdin" <> help "Read content from stdin")
```

The `<|>` chain with `pure GuidanceFromEditor` as the final fallback means: if no flag is provided, default to opening an editor.

### Handler

```haskell
handleGuidance :: GuidanceInput -> IO ()
handleGuidance = \case
  GuidanceFromEditor       -> launchEditor tempContent >>= writeContent
  GuidanceFromContent text -> writeContent text
  GuidanceFromFile path    -> TIO.readFile path >>= writeContent
  GuidanceFromStdin        -> TIO.getContents >>= writeContent
```

### Usage

```bash
# Open in $EDITOR (default)
myapp guidance set

# Direct content
myapp guidance set --content "Focus on error handling"

# From file
myapp guidance set --file guidance.md

# From stdin
echo "Focus on error handling" | myapp guidance set --stdin
cat guidance.md | myapp guidance set --stdin
```

### When to use this vs Pattern 1

| Criteria | Pattern 1 (auto-detect) | Pattern 2 (explicit flag) |
|----------|------------------------|--------------------------|
| Input is a short string (title, description) | Yes | No |
| Multiple input sources (editor, file, content) | No | Yes |
| Input may be multi-line (prose, markdown) | Either | Preferred |
| Need to distinguish "no input" from "empty stdin" | No | Yes |

## Pattern 3: Auto-Detect with Default Fallback

A hybrid where stdin is auto-detected without a flag, but a default value is used when interactive:

```haskell
handleImproveGuidance :: Maybe Text -> IO ()
handleImproveGuidance mInstructions = do
  instructions <- case mInstructions of
    Just instrs -> pure instrs
    Nothing -> do
      isTerminal <- hIsTerminalDevice stdin
      if isTerminal
        then pure defaultInstructions  -- use a sensible default
        else do
          content <- TIO.getContents
          let trimmed = T.strip content
          pure $ if T.null trimmed then defaultInstructions else trimmed
  improveWith instructions
```

Useful when the command can always proceed — it just does something smarter with explicit input.

## Interaction with FZF

Stdin piping and fzf interactive selection coexist because fzf reads user input from `/dev/tty`, not stdin. The sequence in a typical command:

```
1. getTextInput checks hIsTerminalDevice stdin
   - If piped: reads stdin content, fzf still works (uses /dev/tty)
   - If terminal: returns Nothing, stdin is available for fzf

2. FZF selector writes candidates to fzf's stdin via CreatePipe
   - fzf's stdin is the pipe (candidate list), not the process stdin
   - fzf reads keystrokes from /dev/tty directly

3. Both can be used in the same command:
   echo "Fix the bug" | myapp action record
   # description comes from stdin pipe
   # intention selection uses fzf (reads from /dev/tty)
```

The `FzfConfig` tracks this at startup:

```haskell
isFzfAvailable :: FzfConfig -> Bool
isFzfAvailable cfg = fzfAvailable cfg && (stdinIsTerminal cfg || ttyAvailable cfg)
```

Even when `stdinIsTerminal` is `False` (piped), fzf works if `ttyAvailable` is `True`.

## Resolution Order Summary

Commands follow a consistent priority chain. The exact chain depends on the command, but follows this general shape:

```
1. Explicit CLI argument / flag     (highest priority)
2. Piped stdin                      (auto-detected or --stdin flag)
3. Interactive fallback             (editor, fzf picker, prompt, or default)
4. Error                            (if no input and no fallback)
```

For entity ID resolution, the chain is:

```
1. --id flag with explicit ID text  → parse directly
2. No ID + database available       → fzf interactive picker
3. No ID + no database              → error
```

## Stdin Reading: `getContents` vs `hGetContents`

Both work, with a subtle difference:

```haskell
-- Reads all of stdin as Text (preferred for Text pipelines)
content <- TIO.getContents

-- Reads all of stdin as String, then packs (used in some older handlers)
content <- pack <$> hGetContents stdin
```

Prefer `TIO.getContents` to avoid the intermediate `String` allocation.

Both are lazy reads. In practice this is fine because:
- Piped stdin is finite (the writing process closes its end)
- The content is forced immediately by `T.strip` or similar
