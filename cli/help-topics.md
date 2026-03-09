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

## Build caveat

Cabal does not track embedded files as dependencies. If you edit a `.md` file without touching the `.hs` file, Cabal may skip recompilation. Force it with:

```bash
# Touch the Haskell source to trigger rebuild
touch src/Cli/Commands/Help.hs
cabal build
```

Or delete the relevant build artifact and rebuild.
