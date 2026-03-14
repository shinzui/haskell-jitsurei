# Option Groups for Organized `--help` Output

A pattern for using optparse-applicative's option groups to organize flags into labeled sections in `--help` output. This transforms a flat wall of flags into clearly categorized sections that are much easier to scan.

**Requires optparse-applicative >= 0.19.** The `parserOptionGroup` function was introduced in this version.

## Before vs After

Without option groups, `--help` shows a flat list under "Available options":

```
Available options:
  -f,--format FORMAT       Output format: default, fzf, or json
  --hide-id                Hide intention IDs from output
  --future                 Show only future (deferred) intentions
  --all                    Show both active and future intentions
  -d,--dormant             Show only dormant intentions
  --completed              Show only completed intentions
  -c,--context CONTEXT     Filter by context
  --category CATEGORY_SLUG Filter by category slug
  -s,--search KEYWORD      Search by title
  -h,--help                Show this help text
```

With option groups, flags are organized under labeled headings:

```
Output
  -f,--format FORMAT       Output format: default, fzf, or json
  --hide-id                Hide intention IDs from output

Status
  --future                 Show only future (deferred) intentions
  --all                    Show both active and future intentions
  -d,--dormant             Show only dormant intentions
  --completed              Show only completed intentions

Scope
  -c,--context CONTEXT     Filter by context
  --category CATEGORY_SLUG Filter by category slug
  -s,--search KEYWORD      Search by title

Available options:
  -h,--help                Show this help text
```

## Key Function

```haskell
parserOptionGroup :: String -> Parser a -> Parser a
```

Takes a group label and wraps a parser so that all of its options appear under that label in `--help` output. The function doesn't change parsing behavior — it only affects help text rendering.

## Implementation

### 1. Define option group types

Separate your command's options into logical groups, each with its own record type:

```haskell
data OutputOpts = OutputOpts
  { format :: !Format,
    hideId :: !Bool
  }

data StatusOpts = StatusOpts
  { statusFilter :: !StatusFilter,
    showDormant :: !Bool,
    showCompleted :: !Bool
  }

data ScopeOpts = ScopeOpts
  { context :: !(Maybe Text),
    category :: !(Maybe Text),
    search :: !(Maybe Text)
  }
```

### 2. Write a parser for each group, wrapped with `parserOptionGroup`

```haskell
import Options.Applicative

outputOptsParser :: Parser OutputOpts
outputOptsParser =
  parserOptionGroup
    "Output"
    ( OutputOpts
        <$> option
          formatReader
          ( long "format"
              <> short 'f'
              <> metavar "FORMAT"
              <> value DefaultFormat
              <> help "Output format: default, fzf, or json"
          )
        <*> switch
          ( long "hide-id"
              <> help "Hide IDs from output"
          )
    )

statusOptsParser :: Parser StatusOpts
statusOptsParser =
  parserOptionGroup
    "Status"
    ( StatusOpts
        <$> statusFilterParser
        <*> switch (long "dormant" <> short 'd' <> help "Show only dormant")
        <*> switch (long "completed" <> help "Show only completed")
    )

scopeOptsParser :: Parser ScopeOpts
scopeOptsParser =
  parserOptionGroup
    "Scope"
    ( ScopeOpts
        <$> optional (strOption (long "context" <> short 'c' <> metavar "CONTEXT" <> help "Filter by context"))
        <*> optional (strOption (long "category" <> metavar "SLUG" <> help "Filter by category slug"))
        <*> optional (strOption (long "search" <> short 's' <> metavar "KEYWORD" <> help "Search by title"))
    )
```

### 3. Compose groups in the command parser

Combine the group parsers with `<*>` as usual:

```haskell
data ListOpts = ListOpts
  { output :: !OutputOpts,
    status :: !StatusOpts,
    scope :: !ScopeOpts
  }

listOptsParser :: Parser ListOpts
listOptsParser =
  ListOpts
    <$> outputOptsParser
    <*> statusOptsParser
    <*> scopeOptsParser

listCmd :: Mod CommandFields Command
listCmd =
  command
    "list"
    ( info
        (List <$> listOptsParser <**> helper)
        (progDesc "List all items")
    )
```

### 4. Access fields in the handler

Use the nested record fields in your handler:

```haskell
handleList :: ListOpts -> IO ()
handleList opts = do
  let fmt = opts.output.format
      ctx = opts.scope.context
  -- ...
```

## Grouping Subcommands

Subcommands can also be grouped using `commandGroup`:

```haskell
myCommandParser :: Parser Command
myCommandParser =
  subparser (commandGroup "Lifecycle" <> lifecycleCommands)
    <|> subparser (commandGroup "View" <> viewCommands)
    <|> subparser (commandGroup "Metadata" <> metadataCommands)
  where
    lifecycleCommands =
      command "create" (info ...) <> command "complete" (info ...)
    viewCommands =
      command "list" (info ...) <> command "show" (info ...)
    metadataCommands =
      command "set-title" (info ...) <> command "set-context" (info ...)
```

This produces grouped subcommand help:

```
Lifecycle
  create                   Create a new item
  complete                 Mark as complete

View
  list                     List all items
  show                     Show details

Metadata
  set-title                Set title
  set-context              Set context
```

## Guidelines

- **Group by user intent**, not implementation detail — "Output", "Filters", "Scope" are better than "Strings", "Booleans"
- **Keep group names short** — they appear as section headers in `--help`
- **Options not in any group** appear under the default "Available options" section (where `-h,--help` lives)
- **Order matters** — groups appear in the order their parsers are composed with `<*>`
- A parser wrapped with `parserOptionGroup` behaves identically at parse time — the grouping is purely cosmetic for `--help`
