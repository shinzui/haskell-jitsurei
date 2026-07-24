---
type: Pattern
title: "CLI Help Topics with file-embed"
description: "Ship standalone Markdown help topics inside an optparse-applicative executable"
timestamp: 2026-04-25T14:04:29-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-help-topics
tags: [cli, help, file-embed, optparse-applicative, markdown]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-04-25T14:04:29-07:00
    scope: catalog-metadata
    outcome: approved
---

# CLI Help Topics with file-embed

A pattern for adding a `help <topic>` subcommand to an optparse-applicative CLI, where each topic's content lives in a standalone Markdown file embedded at compile time.

## Structure

```
my-cli/
├── help/                    # Topic content files
│   ├── config.md
│   ├── time.md
│   └── ...
└── src/Cli/Commands/Help.hs # Topic registry, parser, handler
```

## Dependencies

- **file-embed** — `embedStringFile` bakes file contents into the binary at compile time
- **optparse-applicative** — parser for `help [TOPIC]`

## Implementation

### 1. Topic registry

A `HelpTopic` record pairs a name, one-line description, and the embedded content. All topics are collected in a single list that drives the parser, list display, and lookup.

```haskell
{-# LANGUAGE TemplateHaskell #-}

import Data.FileEmbed (embedStringFile)

data HelpTopic = HelpTopic
  { topicName        :: !Text
  , topicDescription :: !Text
  , topicContent     :: !Text
  }

helpTopics :: [HelpTopic]
helpTopics =
  [ HelpTopic "time"   "Understanding time formats" timeTopicContent
  , HelpTopic "config" "Configuration reference"    configTopicContent
  ]

timeTopicContent :: Text
timeTopicContent = $(embedStringFile "help/time.md")

configTopicContent :: Text
configTopicContent = $(embedStringFile "help/config.md")
```

`embedStringFile` paths are relative to the package root (where the `.cabal` file lives). The embedded string satisfies `IsString a => a`, so it works directly as `Text`.

### 2. Command type and parser

```haskell
data HelpCommand
  = ListTopics
  | ShowTopic !Text

helpCommandParser :: Parser HelpCommand
helpCommandParser =
  showTopicParser <|> pure ListTopics

showTopicParser :: Parser HelpCommand
showTopicParser =
  ShowTopic
    <$> strArgument
      ( metavar "TOPIC"
          <> help ("Help topic: " <> T.unpack topicList)
      )
  where
    topicList = T.intercalate ", " (map topicName helpTopics)
```

When no argument is given, `pure ListTopics` wins via `<|>` and the handler prints the topic index. The available topic names appear in `--help` output automatically.

### 3. Handler

```haskell
handleHelpCommand :: HelpCommand -> IO ()
handleHelpCommand = \case
  ListTopics      -> listTopics
  ShowTopic name  -> showTopic name

listTopics :: IO ()
listTopics = do
  TIO.putStrLn "HELP TOPICS\n"
  forM_ helpTopics $ \t ->
    TIO.putStrLn $ "  " <> topicName t <> "  " <> topicDescription t
  TIO.putStrLn "\nUse 'app help <topic>' for details."

showTopic :: Text -> IO ()
showTopic name =
  case find (\t -> topicName t == T.toLower name) helpTopics of
    Just t  -> TIO.putStrLn (topicContent t)
    Nothing -> do
      TIO.putStrLn $ "Unknown topic: " <> name
      TIO.putStrLn $ "Available: " <> T.intercalate ", " (map topicName helpTopics)
```

Lookup is case-insensitive via `T.toLower`.

### 4. Register the subcommand

In the main CLI parser, wire it up like any other subcommand:

```haskell
helpCmd :: Mod CommandFields Command
helpCmd =
  command "help"
    (info (Help <$> helpCommandParser <**> helper)
          (progDesc "Show help for commands and topics"))
```

### 5. Topic file format

Topic files are plain text with ALL-CAPS section headers (no Markdown rendering, just printed directly to the terminal):

```
TIME FORMATS

Rei uses relative and absolute time formats for the --at flag.

RELATIVE TIME

  "2 hours ago"       Two hours before now
  "yesterday"         Yesterday at current time

EXAMPLES

  Record completing an action 2 hours ago:
    myapp action complete --at "2 hours ago"
```

Use 2-space indentation for content under each section.

## Adding a new topic

1. Create `help/my-topic.md` with the content
2. Add an embedding binding in Help.hs:
   ```haskell
   myTopicContent :: Text
   myTopicContent = $(embedStringFile "help/my-topic.md")
   ```
3. Append to the `helpTopics` list:
   ```haskell
   HelpTopic "my-topic" "Short description" myTopicContent
   ```
4. Rebuild — `embedStringFile` runs at compile time, so a rebuild is required for new/changed files

No `.cabal` changes needed; `file-embed` reads the file directly from disk during compilation.

## FZF interactive selection with preview

When the topic list grows large, replace the plain listing with an FZF fuzzy finder that previews guide content as the user navigates.

### Dependencies

- The FZF integration module (e.g. `Cli.Fzf`) providing `runFzf`, `Candidate`, `FzfResult`, `detectFzfConfig`, `isFzfAvailable`, and option builders

### Pattern

Change `ListTopics` to detect FZF availability and either launch the picker or fall back to the plain list:

```haskell
import Cli.Fzf (Candidate (..), FzfResult (..), detectFzfConfig, isFzfAvailable,
                 runFzf, withHeader, withPreview, withPrompt)

handleHelpCommand :: HelpCommand -> IO ()
handleHelpCommand = \case
  ListTopics     -> selectOrListTopics
  ShowTopic name -> showTopic name

selectOrListTopics :: IO ()
selectOrListTopics = do
  cfg <- detectFzfConfig
  if isFzfAvailable cfg
    then selectTopicWithFzf cfg
    else listTopics
  where
    selectTopicWithFzf cfg = do
      let candidates = map formatTopicCandidate helpTopics
          opts =
            withPrompt "Help topic> "
              <> withHeader "Select a guide (type to filter)"
              <> withPreview "myapp help {2}"
      result <- runFzf cfg opts candidates
      case result of
        FzfSelected topic -> TIO.putStrLn (topicContent topic)
        FzfNoMatch        -> TIO.putStrLn "No matching topics."
        FzfCancelled      -> pure ()
        FzfError _        -> listTopics  -- graceful fallback

    formatTopicCandidate topic =
      Candidate
        { candidateDisplay = padRight 30 (topicName topic) <> topicDescription topic
        , candidateValue   = topic
        }

    padRight n t = t <> T.replicate (max 0 (n - T.length t)) " "
```

### How the preview works

The preview command `myapp help {2}` invokes the CLI itself to render the selected topic. FZF's default AWK-style field splitting makes `{2}` resolve to just the topic name (the first word after the hidden index column), so `myapp help time` runs in the preview pane.

This is self-referential: the binary already knows how to render any topic via `ShowTopic`, so no temp files or shell tricks are needed.

### Key details

- **Fallback on error** — `FzfError` falls back to the plain listing so the command never fails
- **Padding** — `padRight` aligns descriptions into a readable column
- **`{2}` field extraction** — The FZF index-based approach prefixes each line with `0\tDisplay text`. With AWK-style splitting, field 1 is the index, field 2 is the topic name (first word), and the rest is the description

### Bypassing FZF with `--list`

When FZF is the default for bare `help`, add a `--list` flag so users can still get the plain topic listing:

```haskell
data HelpCommand
  = ListTopics
  | SelectTopics
  | ShowTopic !Text

helpCommandParser :: Parser HelpCommand
helpCommandParser =
  listFlag <|> showTopicParser <|> pure SelectTopics
  where
    listFlag =
      flag' ListTopics
        ( long "list"
            <> short 'l'
            <> help "List all topics without interactive selection"
        )
```

Then split the handler so `ListTopics` always prints the plain list and `SelectTopics` goes through the FZF-or-fallback path:

```haskell
handleHelpCommand :: HelpCommand -> IO ()
handleHelpCommand = \case
  ListTopics     -> listTopics
  SelectTopics   -> selectOrListTopics
  ShowTopic name -> showTopic name
```

This way `myapp help` launches FZF when available, but `myapp help --list` always prints the full topic index — useful in scripts or when piping output.

## Build caveat

Cabal does not track embedded files as dependencies. If you edit a `.md` file without touching the `.hs` file, Cabal may skip recompilation. Force it with:

```bash
# Touch the Haskell source to trigger rebuild
touch src/Cli/Commands/Help.hs
cabal build
```

Or delete the relevant build artifact and rebuild.

## See also

- [help-width.md](./help-width.md) — make `help <topic>` output adapt to the terminal width: a `--width N` flag, ioctl-based auto-detect with a sensible cap, byte-stable verbatim output when piped, and the indent-aware paragraph wrap algorithm. Includes a writeup of the `ansi-terminal getTerminalSize` trap.
