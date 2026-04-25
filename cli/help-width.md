# Terminal-Aware Help Output Width

A pattern for making `help <topic>` output adapt to the terminal width: explicit `--width N` for scripts, ioctl-based auto-detect for interactive use, a sensible cap on ultra-wide displays, and verbatim source bytes when stdout is piped.

Composes with the [`help-topics.md`](./help-topics.md) pattern — this guide assumes you already have a `ShowTopic` command and a topic-content printer.

## Dependencies

- **terminal-size** — `System.Console.Terminal.Size.size :: IO (Maybe (Window Int))` is a thin `ioctl(TIOCGWINSZ)` wrapper. Returns the actual pty winsize on Unix and Windows. No escape sequences, no blocking reads.
- **base** — `System.IO.hIsTerminalDevice` for the TTY check.
- **text** — paragraph splitting and word-wrap.

Do **not** use `System.Console.ANSI.getTerminalSize` from `ansi-terminal`. See [Trap](#trap-ansi-terminals-getterminalsize-is-not-ioctl-based) below.

## The shape

Two pieces work together:

1. A `--width COLUMNS` option on the help subcommand, threaded through as `Maybe Int` (`Nothing` = no override).
2. A `resolveWidth :: Maybe Int -> IO (Maybe Int)` that turns the user's choice into an effective width: explicit value passes through; `Nothing` consults the terminal when stdout is a TTY, caps at a readability maximum, and falls back to `Nothing` (verbatim) when piped or when the terminal size is unavailable.

`Nothing` flows into a renderer whose `Nothing` branch emits the source unchanged — so verbatim is the default for any path that didn't ask for re-flow.

## 1. Parser: thread `Maybe Int` through `ShowTopic`

```haskell
data HelpCommand
  = ListTopics
  | SelectTopics !(Maybe Int)
  | ShowTopic !Text !(Maybe Int)

helpCommandParser :: Parser HelpCommand
helpCommandParser =
  listFlag <|> topicMode
  where
    listFlag =
      flag' ListTopics
        ( long "list" <> short 'l'
            <> help "List all topics without interactive selection"
        )

    -- Single mode covers both "open the picker" and "show a topic":
    -- the positional TOPIC is optional, --width is shared by both.
    topicMode =
      mkTopicCmd
        <$> optional (strArgument (metavar "TOPIC" <> help topicHelp))
        <*> widthOption

    mkTopicCmd Nothing  w = SelectTopics w
    mkTopicCmd (Just t) w = ShowTopic t w

widthOption :: Parser (Maybe Int)
widthOption =
  optional $ option auto
    ( long "width" <> short 'w' <> metavar "COLUMNS"
        <> help "Wrap topic prose to this many columns (indented blocks preserved verbatim)"
    )
```

The exact parser shape matters — naive variants silently break the bare-`help` (FZF picker) path. See the next section.

## 2. Don't break bare `help` (the FZF picker path)

The parser above looks fussier than it needs to be. There's a reason. The natural-looking shapes both break in non-obvious ways.

### Failure mode 1: `--width` only on the show branch

```haskell
-- WRONG
helpCommandParser = listFlag <|> showTopicParser <|> pure SelectTopics

showTopicParser =
  ShowTopic
    <$> strArgument (metavar "TOPIC" <> ...)
    <*> widthOption        -- attached here only
```

Then:

```
$ myapp help --width 60      # intending: open the picker at width 60
Missing: TOPIC
Usage: myapp help [(-l|--list) | TOPIC [-w|--width COLUMNS]]
```

`<|>` tries `showTopicParser` first because `--width` is one of its options, partially commits to that branch, then fails on the missing required `TOPIC`. The `pure SelectTopics` branch is never reached. From the user's point of view, `myapp help` works and `myapp help --width 60` doesn't — confusing.

### Failure mode 2: separate `selectTopicsParser` as a third alternative

```haskell
-- ALSO WRONG
helpCommandParser =
  listFlag <|> showTopicParser <|> selectTopicsParser

showTopicParser   = ShowTopic <$> topicArg <*> widthOption
selectTopicsParser = SelectTopics <$> widthOption
```

This builds and runs, but the generated usage line is a mess:

```
Usage: myapp help [(-l|--list) | TOPIC [-w|--width COLUMNS] | (-w|--width COLUMNS)]
                                          ^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^
                                          declared twice — once in each branch
```

`--help` lists `-w,--width COLUMNS` twice. The option is now part of two parsers that don't share a definition, and any future change to its `metavar` or `help` text has to be made in both places.

### Right fix: single shared option, optional positional, branch on `Nothing`/`Just`

```haskell
helpCommandParser =
  listFlag <|> (mkTopicCmd <$> optional topicArg <*> widthOption)
  where
    mkTopicCmd Nothing  w = SelectTopics w
    mkTopicCmd (Just t) w = ShowTopic t w
```

Now `widthOption` is declared exactly once, both branches receive the user's choice the same way, and the usage line is clean:

```
Usage: myapp help [(-l|--list) | [TOPIC] [-w|--width COLUMNS]]
```

`--width` is accepted in every form except `--list` (intentional — the listing is short and width-agnostic).

### Don't forget the FZF preview command

The `SelectTopics` handler typically passes the user's `mWidth` straight into the post-selection render. The fzf **preview** command, on the other hand, runs as a child process and can't probe its parent's pty for the preview pane's width. Hand it the pane width explicitly via `$FZF_PREVIEW_COLUMNS`:

```haskell
withPreview "myapp help {2} --width $FZF_PREVIEW_COLUMNS"
```

That arrives at the child's `widthOption` as `Just N`, short-circuiting `resolveWidth` (the explicit branch wins). See [FZF preview uses `$FZF_PREVIEW_COLUMNS` explicitly](#fzf-preview-uses-fzf_preview_columns-explicitly) below for the full rationale.

## 3. `resolveWidth` — the only IO bit

```haskell
import qualified System.Console.Terminal.Size as TermSize
import System.IO (hIsTerminalDevice, stdout)

-- | Cap on auto-detected widths. Explicit --width N bypasses the cap;
-- the user asked for it.
maxAutoWidth :: Int
maxAutoWidth = 140

resolveWidth :: Maybe Int -> IO (Maybe Int)
resolveWidth (Just w) = pure (Just w)
resolveWidth Nothing  = do
  isTTY <- hIsTerminalDevice stdout
  if not isTTY
    then pure Nothing                       -- piped/redirected → verbatim
    else do
      mWin <- TermSize.size
      pure $ case mWin of
        Just w | TermSize.width w > 0 ->
          Just (min (TermSize.width w) maxAutoWidth)
        _ -> Nothing
```

Three guarantees fall out of this shape:

- **Explicit `--width N` always wins.** No cap, no TTY check. The user asked for `200`, they get `200`.
- **Piped/redirected output is byte-stable.** `mycli help foo | cat`, `mycli help foo > out.txt`, `mycli help foo` captured by `$(...)` — all see the same bytes you'd get without the flag. No silent reflow as a function of the caller's environment.
- **Wide-screen readability.** A 200-column terminal renders at 140 — wide enough for tables and shell transcripts, narrow enough that the eye doesn't lose its place between line ends.

The cap value (`140`) is a judgment call. Pure typographic guidance is 50–100 cols for body prose, but CLI help interleaves prose with indented examples, tables, and command transcripts that benefit from more horizontal room. 140 is the next conventional engineering ceiling above the prose-only recommendation.

## 4. Wire into the renderer

```haskell
showTopic :: Text -> Maybe Int -> IO ()
showTopic name mWidth = case findTopic name of
  Just topic -> do
    effectiveWidth <- resolveWidth mWidth
    TIO.putStrLn (renderTopic effectiveWidth (topicContent topic))
  Nothing -> ...

renderTopic :: Maybe Int -> Text -> Text
renderTopic Nothing  body = body                     -- verbatim source
renderTopic (Just w) body = rewrap (max 1 w) body
```

Apply the same `resolveWidth mWidth` call at every site that emits topic content — typically `showTopic` and the `FzfSelected` arm of the picker handler. The rest of the picker (preview command, listing) is unaffected: see [FZF preview](#fzf-preview-uses-fzf_preview_columns-explicitly).

## 5. The wrap algorithm

The renderer needs to be conservative — code examples, ASCII tables, and shell transcripts must NOT be reflowed, or they'll be unreadable. The "indent ≥ 2 spaces ⇒ verbatim" rule is a remarkably effective heuristic if your topic files follow a consistent authoring discipline (every code block, table, and transcript is indented by exactly two spaces).

```haskell
rewrap :: Int -> Text -> Text
rewrap width body =
  T.intercalate "\n\n" (map (rewrapParagraph width) paragraphs)
  where paragraphs = splitOnBlankLines body

splitOnBlankLines :: Text -> [Text]
splitOnBlankLines body = go [] [] (T.lines body)
  where
    go acc cur [] = reverse (flush cur acc)
    go acc cur (l : ls)
      | T.null (T.strip l) = go (flush cur acc) [] ls
      | otherwise          = go acc (l : cur) ls
    flush []  acc = acc
    flush cur acc = T.intercalate "\n" (reverse cur) : acc

rewrapParagraph :: Int -> Text -> Text
rewrapParagraph width paragraph
  | isIndentedBlock paragraph = paragraph     -- code/table/transcript
  | otherwise                 = reflow width paragraph

isIndentedBlock :: Text -> Bool
isIndentedBlock paragraph =
  not (null nonEmpty) && all isIndented nonEmpty
  where
    nonEmpty = filter (not . T.null . T.strip) (T.lines paragraph)
    isIndented l = "  " `T.isPrefixOf` l

reflow :: Int -> Text -> Text
reflow width paragraph =
  T.intercalate "\n" (pack (T.words paragraph))
  where
    pack [] = []
    pack (firstWord : rest) = go firstWord rest
      where
        go acc [] = [acc]
        go acc (w : ws)
          | T.length acc + 1 + T.length w <= width = go (acc <> " " <> w) ws
          | otherwise                              = acc : go w ws
```

Behavior:

- **Paragraphs** are blocks separated by blank lines.
- **Indented paragraphs** (every non-empty line starts with `  ` or more) pass through verbatim — even at narrow widths. A 124-column Dhall import line will spill past a 60-column terminal; that's better than mangling it.
- **Prose paragraphs** are joined into a single string, split on whitespace, and packed greedily into lines no wider than `width`. A word longer than `width` goes on its own line — never break inside a word.

Markdown headings (`# foo`), ASCII separator lines, and similar single-line "paragraphs" are reflowed by this rule because they don't start with two spaces. In practice this is fine: a long section title spilling onto two lines at narrow widths is normal text behavior. If your corpus has long heading lines you care about, special-case them in `rewrapParagraph`.

## FZF preview uses `$FZF_PREVIEW_COLUMNS` explicitly

The preview pane in the picker has its own width, independent of the terminal width and independent of any `--width` the user passed. Resolve it at the preview shell command rather than via `resolveWidth`:

```haskell
withPreview "myapp help {2} --width $FZF_PREVIEW_COLUMNS"
```

`$FZF_PREVIEW_COLUMNS` is set by fzf in the preview process's environment to the actual pane width. Passing it as `--width` short-circuits `resolveWidth`'s auto-detect (the explicit branch wins), which is what you want — the child process can't probe its parent's pty for the preview pane's geometry, so explicit is the only correct option.

## Trap: ansi-terminal's `getTerminalSize` is NOT ioctl-based

A natural mistake — `ansi-terminal` is already a dependency of most CLIs, so why add a new one? Because on Unix, `System.Console.ANSI.getTerminalSize` does NOT call `ioctl(TIOCGWINSZ)`. It implements a cursor-query escape-sequence trick:

1. Write `ESC[s` (save cursor), `ESC[10000;10000H` (move to 10000,10000 — the terminal clamps to its actual bounds), `ESC[6n` (request cursor position), `ESC[u` (restore cursor) to **stdout**.
2. Block reading from **stdin** for the terminal emulator's `ESC[<row>;<col>R` response.
3. Parse the response.

This breaks in three ways:

- It needs a real interactive terminal emulator on the other end of stdin/stdout to interpret the escape sequences and write back a response. Inside `pty.fork`, `expect`, or any other harness with no emulator, the read returns nothing or hangs.
- It writes the escape sequence even when stdout isn't a TTY — visible as `7[10000;10000H[6n8` in piped output. That's user-visible garbage in scripts.
- A misbehaving terminal can leave the read hanging indefinitely.

Easy to verify: write a probe that calls `getTerminalSize`, run it under `pty.fork` with `TIOCSWINSZ` set to 200 cols. `ansi-terminal` returns `Nothing`. `terminal-size` returns `Just (Window {height = 24, width = 200})`.

Use `terminal-size`. It's small, well-maintained, and does the obvious ioctl call.

## Acceptance checklist

A correct implementation passes all of these (longest non-indented prose line in `myapp help <topic>`):

| context                                | expected                          |
|----------------------------------------|-----------------------------------|
| TTY 60 cols, no `--width`              | ≤ 60                              |
| TTY 100 cols, no `--width`             | ≤ 100                             |
| TTY 140 cols, no `--width`             | ≤ 140                             |
| TTY 200 cols, no `--width`             | ≤ 140 (cap applied)               |
| Piped (no TTY), no `--width`           | byte-identical to the source file |
| TTY 80 cols, `--width 200`             | ≤ 200 (override beats cap)        |
| TTY 80 cols, `--width 50`              | ≤ 50                              |
| `myapp help` → fzf → select            | renders at auto-detected width    |
| FZF preview pane                       | sized to `$FZF_PREVIEW_COLUMNS`   |

The TTY rows can't be tested with a normal pipe (`| wc -L` collapses stdout to a non-TTY). Use a `pty.fork`-style harness with `TIOCSWINSZ`, or run interactively in a real terminal.
