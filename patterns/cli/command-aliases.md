---
type: Pattern
title: "Command Aliases via Config File"
description: "Expand user-defined CLI aliases safely before optparse-applicative parsing"
timestamp: 2026-03-16T21:16:42-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-command-aliases
tags: [cli, aliases, yaml, optparse-applicative, configuration]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-03-16T21:16:42-07:00
    scope: catalog-metadata
    outcome: approved
---

# Command Aliases via Config File

A pattern for user-defined command aliases that expand before optparse-applicative parsing. Users define short aliases in a config file that map to longer command invocations, with built-in command protection to prevent shadowing.

## How It Works

```
rei tw --verbose
      │
      ▼
expandAlias aliasMap ["tw", "--verbose"]
      │
      ▼
["today", "-c", "work", "--actions", "--habits", "--verbose"]
      │
      ▼
optparse-applicative parses as normal
```

Aliases are expanded in a single pass before the argument list reaches the parser. Only the first argument is matched. Extra arguments are appended to the expansion.

## Configuration

Users define aliases in a YAML config file:

```yaml
aliases:
  tw: today -c work --actions --habits
  i: intention
  sh: intention show --full
  ls: intention list --active
  h: habit
```

## Implementation

### 1. Define the alias config type

```haskell
newtype AliasConfig = AliasConfig
  { aliasMap :: Map Text Text
  }
  deriving stock (Generic, Eq, Show)

instance FromJSON AliasConfig where
  parseJSON v = AliasConfig <$> parseJSON v

instance ToJSON AliasConfig where
  toJSON (AliasConfig m) = toJSON m
```

This deserializes the YAML `aliases:` key directly into a `Map Text Text`.

### 2. Define the built-in commands list

Prevent aliases from shadowing real commands:

```haskell
builtinCommands :: [Text]
builtinCommands =
  [ "intention", "action", "habit", "note",
    "help", "version", "alias"
    -- ... all registered subcommands
  ]
```

### 3. Write the expansion function

```haskell
expandAlias :: Map Text Text -> [String] -> [String]
expandAlias aliasMap args = case args of
  [] -> []
  (first : rest) ->
    let firstText = pack first
     in if firstText `elem` builtinCommands
          then args
          else case Map.lookup firstText aliasMap of
            Nothing -> args
            Just expansion ->
              let expandedTokens = map T.unpack $ T.words expansion
               in expandedTokens <> rest
```

Key properties:
- **First-argument only** — only the first CLI argument is checked
- **Single-pass** — no recursive expansion, so `tw` expanding to `today ...` won't re-expand `today`
- **Built-in protection** — built-in commands are never overridden by aliases
- **Argument appending** — remaining arguments are appended after the expansion

### 4. Integrate into the main entry point

Call `expandAlias` on raw args before passing them to the parser:

```haskell
run :: AliasConfig -> IO ()
run aliasConf = do
  rawArgs <- getArgs
  let expandedArgs = expandAlias (aliasMap aliasConf) rawArgs
  (opts, cmd) <-
    handleParseResult $
      execParserPure (prefs showHelpOnEmpty) parserInfo expandedArgs
  -- handle cmd ...
```

The critical detail: use `execParserPure` with the expanded args instead of `execParser` (which reads `getArgs` internally).

### 5. Add a CLI command to list aliases

```haskell
data AliasCommand = AliasList

aliasCommandParser :: Parser AliasCommand
aliasCommandParser =
  subparser
    ( command "list"
        (info (pure AliasList <**> helper)
              (progDesc "List configured aliases"))
    )
    <|> pure AliasList  -- default to list with no subcommand

handleAliasCommand :: AliasConfig -> AliasCommand -> IO ()
handleAliasCommand (AliasConfig aMap) = \case
  AliasList
    | Map.null aMap ->
        TIO.putStrLn "No aliases configured."
    | otherwise -> do
        let maxKeyLen = maximum $ map T.length $ Map.keys aMap
        mapM_
          (\(name, expansion) ->
            TIO.putStrLn $ T.justifyLeft (maxKeyLen + 2) ' ' name <> "= " <> expansion
          )
          (Map.toAscList aMap)
```

Output:

```
$ myapp alias list
h   = habit
i   = intention
ls  = intention list --active
sh  = intention show --full
tw  = today -c work --actions --habits
```

## Design Decisions

- **Config file over CLI registration** — aliases live in user config, not in code. Users can add aliases without recompiling.
- **Pre-parse expansion** — expanding before optparse-applicative sees the args means aliases work with any command structure, including subcommands and flags.
- **No recursive expansion** — keeps behavior predictable. `a -> b` and `b -> c` won't chain; `a` expands to `b ...` and stops.
- **Built-in shadowing prevention** — the built-in commands list must be maintained manually but prevents a misconfigured alias from hiding a real command.

## Guidelines

- Keep the `builtinCommands` list in sync when adding new commands
- Aliases should expand to valid command invocations — there's no validation at config load time
- `T.words` splitting means alias expansions can't contain arguments with spaces
- Consider adding an `alias add` / `alias remove` command if you want CLI-driven alias management
