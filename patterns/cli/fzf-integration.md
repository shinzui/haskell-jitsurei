---
type: Pattern
title: "FZF Integration for Interactive CLI Selection"
description: "Integrate fzf as a composable interactive selector for Haskell CLIs"
timestamp: 2026-03-12T11:11:43-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-fzf-integration
tags: [cli, fzf, interactive, selection, process]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-03-12T11:11:43-07:00
    scope: catalog-metadata
    outcome: approved
---

# FZF Integration for Interactive CLI Selection

A pattern for integrating the [fzf](https://github.com/junegunn/fzf) fuzzy finder into a Haskell CLI, providing interactive entity selection with composable options, index-based value extraction, view toggling, and multi-select.

## Dependencies

- **System.Process** — spawn fzf as a subprocess
- **System.Directory** — `findExecutable` for availability detection
- **containers** — `Map` for index-based lookup
- No Haskell fzf library needed — fzf is invoked as a plain subprocess with piped stdin/stdout

## Architecture

```
Fzf.hs                        -- Core: process spawning, types, option combinators
Fzf/Selector/Types.hs         -- Per-entity selection result ADTs
Fzf/Selector/Internal.hs      -- Shared defaults, toggle helpers
Fzf/Selector/Intention.hs     -- Entity-specific selector (one per entity)
Fzf/Selector/Habit.hs
Fzf/Selector/Anchor.hs        -- Unified multi-entity selector
Fzf/Selector.hs               -- Re-exports everything
```

Command handlers import only the re-export module and call `resolveEntityId` or `selectEntity` functions.

## 1. Config Detection

Detect fzf availability once at CLI startup and thread the config through command handlers.

```haskell
data FzfConfig = FzfConfig
  { fzfBinary       :: !FilePath    -- resolved path or "fzf"
  , fzfAvailable    :: !Bool        -- findExecutable succeeded
  , stdinIsTerminal :: !Bool        -- hIsTerminalDevice stdin
  , stdoutIsTerminal :: !Bool       -- hIsTerminalDevice stdout
  , ttyAvailable    :: !Bool        -- /dev/tty can be opened
  }

detectFzfConfig :: IO FzfConfig
detectFzfConfig = do
  mFzf <- findExecutable "fzf"
  stdinTerm <- hIsTerminalDevice stdin
  stdoutTerm <- hIsTerminalDevice stdout
  ttyOk <- checkTtyAvailable
  pure FzfConfig
    { fzfBinary = fromMaybe "fzf" mFzf
    , fzfAvailable = isJust mFzf
    , stdinIsTerminal = stdinTerm
    , stdoutIsTerminal = stdoutTerm
    , ttyAvailable = ttyOk
    }

isFzfAvailable :: FzfConfig -> Bool
isFzfAvailable cfg = fzfAvailable cfg && (stdinIsTerminal cfg || ttyAvailable cfg)
```

The `/dev/tty` check matters because fzf can read user input directly from the terminal device even when stdin is piped. This means fzf works inside shell pipelines.

```haskell
checkTtyAvailable :: IO Bool
checkTtyAvailable = do
  result <- try @SomeException $ openFile "/dev/tty" ReadMode
  case result of
    Left _  -> pure False
    Right h -> hClose h >> pure True
```

## 2. Composable Options (Monoid Pattern)

Options are a record with a `Monoid` instance. Smart constructors each set a single field on `mempty`. Callers combine them with `<>`.

```haskell
data FzfOpts = FzfOpts
  { fzfPrompt     :: !(Maybe Text)
  , fzfHeader     :: !(Maybe Text)
  , fzfPreview    :: !(Maybe Text)
  , fzfHeight     :: !(Maybe Text)
  , fzfAnsi       :: !Bool
  , fzfNoSort     :: !Bool
  , fzfMulti      :: !Bool
  , fzfExpectKeys :: ![(Text, FzfAction)]
  }

instance Semigroup FzfOpts where
  a <> b = FzfOpts
    { fzfPrompt     = fzfPrompt b     <|> fzfPrompt a      -- right-biased
    , fzfHeader     = fzfHeader b     <|> fzfHeader a
    , fzfPreview    = fzfPreview b    <|> fzfPreview a
    , fzfHeight     = fzfHeight b     <|> fzfHeight a
    , fzfAnsi       = fzfAnsi a       || fzfAnsi b          -- sticky true
    , fzfNoSort     = fzfNoSort a     || fzfNoSort b
    , fzfMulti      = fzfMulti a      || fzfMulti b
    , fzfExpectKeys = if null (fzfExpectKeys b) then fzfExpectKeys a else fzfExpectKeys b
    }

instance Monoid FzfOpts where
  mempty = FzfOpts Nothing Nothing Nothing Nothing False False False []

-- Smart constructors
withPrompt  :: Text -> FzfOpts
withPrompt p = mempty { fzfPrompt = Just p }

withHeader  :: Text -> FzfOpts
withAnsi    :: FzfOpts
withNoSort  :: FzfOpts
withMulti   :: FzfOpts
withHeight  :: Text -> FzfOpts
withPreview :: Text -> FzfOpts
withExpect  :: Text -> FzfAction -> FzfOpts
-- ... each sets one field on mempty
```

Usage at call sites reads naturally:

```haskell
let opts = withPrompt "habit> "
        <> withHeader "Select a habit"
        <> withHeight "40%"
        <> withAnsi
        <> withNoSort
```

Convert to CLI args for the fzf process:

```haskell
optsToArgs :: FzfOpts -> [String]
optsToArgs opts = concat
  [ maybe [] (\p -> ["--prompt", T.unpack p]) (fzfPrompt opts)
  , maybe [] (\h -> ["--header", T.unpack h]) (fzfHeader opts)
  , maybe [] (\p -> ["--preview", T.unpack p]) (fzfPreview opts)
  , maybe [] (\h -> ["--height", T.unpack h]) (fzfHeight opts)
  , ["--ansi"    | fzfAnsi opts]
  , ["--no-sort" | fzfNoSort opts]
  , ["--multi"   | fzfMulti opts]
  , if null (fzfExpectKeys opts) then []
    else ["--expect", T.unpack $ T.intercalate "," (map fst $ fzfExpectKeys opts)]
  ]
```

## 3. Candidates and Index-Based Selection

The core insight: don't try to parse display text back from fzf output. Instead, use hidden integer indices.

```haskell
data Candidate a = Candidate
  { candidateDisplay :: !Text    -- what the user sees
  , candidateValue   :: !a       -- what you get back
  }
  deriving stock (Functor)
```

The selection protocol:

1. Zip candidates with indices: `[(0, c0), (1, c1), ...]`
2. Build `Map Int a` from index to value
3. Write each line as `"<index>\t<display>"` to fzf's stdin
4. Pass `--with-nth=2..` so fzf hides the index column from the user
5. On selection, parse the index from fzf's output, look up in the map

This avoids all issues with special characters, tabs, or formatting in display text.

## 4. Process Spawning

```haskell
runFzf :: FzfConfig -> FzfOpts -> [Candidate a] -> IO (FzfResult a)
runFzf cfg opts candidates
  | null candidates = pure FzfNoMatch       -- short-circuit empty list
  | not (isFzfAvailable cfg) = pure $ FzfError "FZF not available"
  | otherwise = do
      let indexed = zip [0 :: Int ..] candidates
          valueMap = Map.fromList [(i, candidateValue c) | (i, c) <- indexed]
          inputLines = [show i <> "\t" <> T.unpack (candidateDisplay c) | (i, c) <- indexed]
          args = ["-1", "--with-nth=2.."] ++ optsToArgs opts

      let processSpec = (proc (fzfBinary cfg) args)
            { std_in = CreatePipe
            , std_out = CreatePipe
            , std_err = Inherit
            , delegate_ctlc = True   -- Ctrl-C goes to fzf, not parent
            }

      result <- try @SomeException $ do
        (Just hIn, Just hOut, _, ph) <- createProcess processSpec
        mapM_ (hPutStrLn hIn) inputLines
        hClose hIn
        outputStr <- hGetContents hOut
        exitCode <- waitForProcess ph
        let output = T.strip (pack outputStr)
        pure (exitCode, output)

      case result of
        Left err -> pure $ FzfError (pack $ show err)
        Right (exitCode, output) -> case exitCode of
          ExitSuccess   -> -- parse index, lookup in valueMap
          ExitFailure 1   -> pure FzfNoMatch      -- no matches
          ExitFailure 130 -> pure FzfCancelled     -- Esc / Ctrl-C
          ExitFailure n   -> pure $ FzfError ("FZF exited with code " <> show n)
```

Key details:
- **`-1` flag**: auto-select when there's only one candidate (single-select only)
- **`delegate_ctlc = True`**: forwards Ctrl-C to fzf instead of killing the parent process; fzf exits with code 130
- **`std_err = Inherit`**: fzf's UI renders to stderr, so it must go to the terminal
- **Lazy read + waitForProcess**: read stdout lazily, then wait — the exit code forces evaluation

## 5. Result Types

Three variants for different selection modes:

```haskell
-- Single selection
data FzfResult a
  = FzfSelected  !a
  | FzfNoMatch
  | FzfCancelled
  | FzfError     !Text
  deriving stock (Functor)

-- Multi-selection (Tab to mark, Enter to confirm)
data FzfMultiResult a
  = FzfMultiSelected  ![a]
  | FzfMultiNoMatch
  | FzfMultiCancelled
  | FzfMultiError     !Text
  deriving stock (Functor)

-- Selection with expect keys (action + optional selection)
data FzfAction = ActionDefault | ActionToggle

data FzfResultWithAction a
  = FzfSelectedAction !FzfAction !a    -- key + item
  | FzfActionOnly     !FzfAction       -- key only, no item
  | FzfNoMatchAction
  | FzfCancelledAction
  | FzfErrorAction    !Text
  deriving stock (Functor)
```

All result types derive `Functor` so callers can `fmap` over the selected value.

## 6. Expect Keys and the Toggle Pattern

Fzf's `--expect` flag makes it report which key was pressed on the first output line. This enables multi-action interfaces where different keys trigger different behaviors.

### Expect key output format

```
<pressed-key>           -- empty string if Enter, key name otherwise
<index>\t<display>      -- selected item (may be absent)
```

### Toggle loop

The most common use: ctrl-f toggles between "active only" and "all" views. Implemented as a recursive IO loop:

```haskell
data ViewMode = ViewActiveOnly | ViewAll

selectWithToggle :: FzfConfig -> Pool -> FzfOpts -> IO Selection
selectWithToggle cfg pool baseOpts =
  go ViewActiveOnly
  where
    go mode = do
      items <- fetchByMode pool mode
      let headerText = case mode of
            ViewActiveOnly -> "[Active] ctrl-f: show all"
            ViewAll        -> "[All] ctrl-f: active only"
          opts = baseOpts
              <> withHeader headerText
              <> withExpect "ctrl-f" ActionToggle
          candidates = map formatCandidate items

      result <- runFzfWithExpect cfg opts candidates
      case result of
        -- ctrl-f pressed (with or without highlighted item) → toggle and re-run
        FzfActionOnly ActionToggle       -> go (toggle mode)
        FzfSelectedAction ActionToggle _ -> go (toggle mode)
        -- Enter pressed → return selection
        FzfSelectedAction ActionDefault val -> pure (Selected val)
        -- Cancel / error
        FzfCancelledAction   -> pure Cancelled
        FzfNoMatchAction     -> pure NoMatch
        FzfErrorAction err   -> pure (SelectionError err)

    toggle ViewActiveOnly = ViewAll
    toggle ViewAll        = ViewActiveOnly
```

Key points:
- When ctrl-f is pressed with an item highlighted, fzf reports both the key *and* the item — but the intent is to toggle, so the item is discarded
- Each iteration re-fetches from the database, so the user sees fresh data
- The header text updates to reflect the current mode and available action

## 7. Entity Selector Pattern

Each entity type gets a selector module with a consistent structure:

### Format function

Converts a database row into a `Candidate`:

```haskell
formatHabitCandidate :: HabitView -> Candidate (HabitId, HabitView)
formatHabitCandidate view =
  Candidate
    { candidateDisplay = "[" <> statusText <> "] " <> habitName <> " (" <> idText <> ")"
    , candidateValue = (habitId, view)
    }
```

### Default options

```haskell
defaultHabitOpts :: FzfOpts
defaultHabitOpts = withPrompt "habit> " <> withHeight "40%" <> withAnsi <> withNoSort
```

`withNoSort` preserves the input order (typically recency from the database). Heights are `40%` for single-entity pickers, `50%` for unified pickers.

### Select function

```haskell
selectHabit :: FzfConfig -> Pool -> IO HabitSelection
selectHabit cfg pool = do
  result <- fetchActiveHabits pool
  case result of
    Left err -> pure $ HabitSelectionError err
    Right habits | null habits -> pure HabitNoMatch
    Right habits -> do
      let candidates = map formatHabitCandidate habits
      fzfResult <- runFzf cfg defaultHabitOpts candidates
      case fzfResult of
        FzfSelected (hid, row) -> pure $ HabitChosen hid row
        FzfNoMatch             -> pure HabitNoMatch
        FzfCancelled           -> pure HabitSelectionCancelled
        FzfError err           -> pure $ HabitSelectionError err
```

### Resolve function (entry point for command handlers)

Three-way dispatch: explicit ID > fzf selection > error.

```haskell
resolveHabitId :: FzfConfig -> Maybe Pool -> Maybe Text -> IO (Maybe HabitId)
resolveHabitId cfg mPool mIdText = case (mIdText, mPool) of
  (Just idText, _)     -> -- parse the ID text directly
  (Nothing, Just pool) -> if isFzfAvailable cfg
                            then selectHabit cfg pool  -- interactive picker
                            else -- print error, return Nothing
  (Nothing, Nothing)   -> -- print "no database" error, return Nothing
```

### Per-entity result type

Each entity defines its own result ADT for type-safe handling:

```haskell
data HabitSelection
  = HabitChosen !HabitId !HabitView
  | HabitNoMatch
  | HabitSelectionCancelled
  | HabitSelectionError !Text
  | HabitFzfUnavailable
```

## 8. Preview

Use `withPreview` to show a detail pane alongside the picker:

```haskell
defaultCategoryOpts :: FzfOpts
defaultCategoryOpts =
  withPrompt "category> "
    <> withHeight "50%"
    <> withAnsi
    <> withNoSort
    <> withPreview "rei category show {2}"
```

Since the index column is hidden by `--with-nth=2..`, fzf's `{1}` is the hidden index and `{2}` is the first visible field. Format the candidate display with a tab-separated field that the preview command can accept as an argument.

## 9. Unified Multi-Entity Selectors

When a command can accept different entity types (e.g., attaching a note to an intention, action, or habit), build a unified selector:

```haskell
data AnchorCandidate
  = AnchorIntention IntentionId IntentionView
  | AnchorHabit HabitId HabitView
  | AnchorNote NoteId NoteView

selectAnchor :: FzfConfig -> Pool -> IO AnchorSelection
selectAnchor cfg pool = do
  -- Fetch all entity types in parallel
  intentions <- fetchActiveIntentions pool
  habits     <- fetchActiveHabits pool
  notes      <- fetchNotes pool

  -- Concatenate with type-tag prefixes
  let candidates = concat
        [ map (\i -> Candidate ("[intention] " <> name i) (AnchorIntention ...)) intentions
        , map (\h -> Candidate ("[habit] "     <> name h) (AnchorHabit ...))     habits
        , map (\n -> Candidate ("[note] "      <> name n) (AnchorNote ...))      notes
        ]

  runFzf cfg (withPrompt "anchor> " <> withHeight "50%" <> withAnsi <> withNoSort) candidates
```

The `[type]` prefix lets the user visually distinguish entity types within a single fzf list. Fzf's fuzzy matching still works naturally — typing "habit" filters to habits.

## 10. Optional Selection (Skip Entry)

When selection is optional, inject a skip candidate at position 0:

```haskell
selectOptionalHabit :: FzfConfig -> Pool -> IO OptionalHabitSelection
selectOptionalHabit cfg pool = do
  habits <- fetchActiveHabits pool
  let skipCandidate = Candidate "< Skip - no habit >" Nothing
      habitCandidates = map (fmap Just . formatHabitCandidate) habits
      candidates = skipCandidate : habitCandidates
  result <- runFzf cfg opts candidates
  case result of
    FzfSelected Nothing       -> pure OptionalHabitSkipped
    FzfSelected (Just (h, v)) -> pure (OptionalHabitChosen h v)
    ...
```

The candidate type becomes `Candidate (Maybe (HabitId, HabitView))` — `Nothing` for skip, `Just` for real entries.

## 11. optparse-applicative Patterns for Optional FZF Values

There are two patterns for wiring fzf into optparse-applicative parsers, depending on whether the entity type is already known from context or needs to be selected by the user.

### Pattern A: Optional positional argument (`optional strArgument`)

Use when the command already establishes what entity type is being operated on (e.g., `rei intention complete` is always about intentions). The entity ID is a positional argument — present means direct lookup, absent means fzf.

```haskell
-- Parser
completeParser :: Parser CompleteData
completeParser =
  CompleteData
    <$> optional (strArgument (metavar "ID" <> help "Intention ID (uses FZF if not provided)"))
    <*> optional (strOption (long "at" <> metavar "TIME" <> help "Completion time"))

-- Handler
case mIdText of
  Just idText -> parseAndLookup idText
  Nothing     -> selectViaFzf fzfConf pool
```

Works because positional arguments are naturally optional — if no more positionals remain, `optional` succeeds with `Nothing`.

### Pattern B: Optional flag argument (`optional strOption`)

Use when one command can operate on different entity types and a flag selects which one (e.g., `rei intention set-focus --intention ID --focus FID`). Each flag is independently optional — absent means fzf picks that entity.

```haskell
-- Parser
setFocusParser :: Parser SetFocusData
setFocusParser =
  SetFocusCmd
    <$> optional (strOption (long "intention" <> short 'i' <> metavar "ID" <> help "Intention ID (uses FZF if not provided)"))
    <*> optional (strOption (long "focus" <> metavar "FID" <> help "Focus ID (uses FZF if not provided)"))

-- Handler: resolve each independently, fzf fills in the gaps
mIntentionId <- resolveIntentionId fzfConf mPool mIntentionIdText
mFocusId     <- resolveFocusId fzfConf mPool mFocusIdText
```

Works because `optional (strOption ...)` makes the entire `--flag VALUE` optional. Flag absent → `Nothing` → fzf. Flag present → `Just value` → direct lookup. The user never types the flag without a value — they either include it with a value or omit it entirely.

### Pattern C: Flag as mode selector with optional value (`flag'` + `optional strArgument`)

Use when a flag selects a *mode* and its value is optional. The flag's presence means "I want this mode" and the value (if given) means "and here's the specific item." This is the pattern for commands like `mori path` where the base behavior (project root) differs from the flagged behavior (package/doc path).

optparse-applicative cannot express "flag with optional value" directly — `strOption` always requires a value, and `<|>` with duplicate long names does not backtrack. The solution: `flag'` consumes the bare flag, then `optional strArgument` consumes the next positional if present.

```haskell
-- Parser
data PathTarget
  = ProjectRoot
  | PackagePath !(Maybe Text)
  | DocPath !(Maybe Text)

pathTargetParser :: Parser PathTarget
pathTargetParser =
  packageTarget <|> docTarget <|> pure ProjectRoot
  where
    packageTarget =
      flag' () (long "package" <> short 'p' <> help "Print path to a package (interactive if name omitted)")
        *> (PackagePath <$> optional (strArgument (metavar "PACKAGE" <> help "Package name")))
    docTarget =
      flag' () (long "doc" <> short 'd' <> help "Print location of a doc (interactive if key omitted)")
        *> (DocPath <$> optional (strArgument (metavar "KEY" <> help "Doc key")))
```

This gives the desired UX:

```
myapp path project                     # ProjectRoot (no flag)
myapp path project --package           # PackagePath Nothing → fzf picker
myapp path project --package mori-core # PackagePath (Just "mori-core") → direct
myapp path project --doc               # DocPath Nothing → fzf picker
myapp path project --doc api-guide     # DocPath (Just "api-guide") → direct
```

The help text naturally shows the optional value:

```
Usage: myapp path PROJECT [(-p|--package) [PACKAGE] | (-d|--doc) [KEY]]
```

**Why not `strOption <|> flag'` with the same long name?** It compiles, but optparse-applicative's option matcher commits to `strOption` when it sees the flag, then fails expecting a value — it does not backtrack to the `flag'` branch. The `flag' *> optional strArgument` pattern avoids this entirely by separating the flag (mode selector) from the value (positional argument).

### When to use which pattern

| Situation | Pattern | Example |
|-----------|---------|---------|
| Command already scopes entity type, ID is the only variable | A: `optional strArgument` | `rei intention complete [ID]` |
| Multiple entity flags on one command, each independently optional | B: `optional strOption` | `rei intention set-focus --intention ID --focus FID` |
| Flag selects a mode, value within that mode is optional | C: `flag' *> optional strArgument` | `mori path PROJECT --package [NAME]` |


## Summary of Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Index-based selection | Avoids parsing issues with special chars in display text |
| `delegate_ctlc = True` | Ctrl-C exits fzf gracefully (code 130) instead of killing the parent |
| `std_err = Inherit` | Fzf renders its UI to stderr; must reach the terminal |
| Monoid options | Composable, readable option construction at call sites |
| Per-entity result ADTs | Type-safe, exhaustive pattern matching in handlers |
| Recursive toggle loop | Simple, re-fetches fresh data on each toggle |
| `/dev/tty` fallback | Fzf works even when stdin is piped |
| Short-circuit empty candidates | Avoids spawning fzf with nothing to show |
