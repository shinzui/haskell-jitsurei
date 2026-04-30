# Command Aliases via KDL Config File

A pattern for user-defined command aliases that expand before
optparse-applicative parsing. Users define short aliases in a KDL config
file that map to longer command invocations, with built-in command
protection to prevent shadowing.

This is the KDL flavour of [`command-aliases.md`](command-aliases.md);
see that file for the YAML/aeson version. The pre-parse expansion logic,
built-in protection, and `mina alias list` UX are identical — only the
config-file decoder changes.

## How It Works

```
mina tw --json
      │
      ▼
expandAlias aliasMap ["tw", "--json"]
      │
      ▼
["exec-plan", "list", "--status", "active", "--json"]
      │
      ▼
optparse-applicative parses as normal
```

Aliases are expanded in a single pass before the argument list reaches
the parser. Only the first argument is matched. Extra arguments are
appended to the expansion.

## Configuration

Users define aliases in a KDL config file. Each child node inside the
`aliases { … }` block is one alias — the **node name** is the alias key
and the **first positional argument** is the expansion:

```kdl
aliases {
  tw "exec-plan list --status active"
  i  "rei intention show"
  sh "rei intention show --full"
  ls "exec-plan list --status active"
  h  "help"
}
```

This shape uses `KDL.remainingNodesWith` to accept any child node name
as an alias key. The alternative shape `aliases { alias "<name>"
"<expansion>" }` is more verbose and is not recommended.

## Dependencies

- **kdl-hs** (`kdl-hs ^>= 1.0` or later) — `KDL.remainingNodesWith` is
  exposed via `KDL.Decoder.Monad`, which mina and notion-cli both use.
- **containers** — `Map Text Text` for the resolved alias table and the
  `Map.mapMaybe listToMaybe` collapse step.
- **text** — `Data.Text.words` for splitting the expansion.
- **optparse-applicative** — `execParserPure` and `handleParseResult`
  for replacing `execParser` so we can interpose expansion.
- **base** — `System.Environment.getArgs`, `Data.Maybe.listToMaybe`.

No new external dependencies should be needed in a project that already
uses kdl-hs and optparse-applicative.

## Implementation

### 1. Define the alias config type

The container is a thin wrapper around `Map Text Text`:

```haskell
import Data.Map.Strict (Map)

data AliasesSection = AliasesSection
  { aliasMap :: Map Text Text
  }
  deriving stock (Show, Eq, Generic)
```

In larger projects you may want to embed this map directly into an
existing `UserConfig` type rather than introduce a new section type.
notion-cli does that:

```haskell
data UserConfig = UserConfig
  { defaultWorkspace :: !(Maybe Text)
  , workspaces       :: !(Map Text WorkspaceConfig)
  , commandAliases   :: !(Map Text Text)
  }
```

mina uses the dedicated wrapper because its `MinaConfig` already groups
related fields into named sub-records. Either shape is fine.

### 2. Decode the KDL block

The decoder uses `KDL.remainingNodesWith (KDL.arg @Text)` inside a
`KDL.children` block. This combinator iterates over **every** child
node regardless of name, decoding each as a `NodeDecoder b` and
returning a `Map Text [b]` keyed on node name:

```haskell
import Data.Maybe (listToMaybe)
import Data.Map.Strict qualified as Map
import KDL qualified

instance KDL.DecodeNode AliasesSection where
  nodeDecoder = KDL.children $ do
    rawMap <- KDL.remainingNodesWith (KDL.arg @Text)
    -- rawMap :: Map Text [Text]
    -- A node name that appears twice produces a two-element list. We
    -- collapse with listToMaybe so the first occurrence wins.
    pure AliasesSection
      { aliasMap = Map.mapMaybe listToMaybe rawMap
      }
```

To slot this into a top-level decoder (the document-level optional
`aliases` block):

```haskell
minaConfigDecoder :: KDL.DocumentDecoder MinaConfig
minaConfigDecoder = KDL.document $ do
  …
  a <- KDL.optional (KDL.node @AliasesSection "aliases")
  pure MinaConfig{ aliases = a, … }
```

If you embed the alias map inside an existing record (notion-cli's
shape), the decoder fragment is one block:

```haskell
cmdAliases <- KDL.option Map.empty $
  KDL.nodeWith "command-alias" $
    KDL.children $ do
      rawMap <- KDL.remainingNodesWith (KDL.arg @Text)
      pure (Map.mapMaybe listToMaybe rawMap)
```

The two shapes — `KDL.optional (KDL.node @T "name")` returning
`Maybe T`, vs. `KDL.option def $ KDL.nodeWith "name" innerDecoder`
returning a value directly — are interchangeable; pick whichever fits
the surrounding decoder's idiom.

### 3. Define the built-in commands list

Prevent aliases from shadowing real commands. This list must include
**every** name registered as a top-level optparse `command "<name>"`:

```haskell
builtinCommands :: [Text]
builtinCommands =
  [ "exec-plan", "master-plan", "rei",
    "config", "completions", "help",
    "alias"
    -- … keep this list in sync with the parser
  ]
```

To prevent silent drift, write a unit test that asserts
`runCliParserInfo` accepts every name in `builtinCommands` (passing
`[name, "--help"]` to `execParserPure` returns a `Failure` with a help
dump, not an "Invalid argument" error). Optionally also assert that
invoking any name *not* in `builtinCommands` fails to parse — that
catches the inverse drift mode where someone adds a `command` literal
but forgets the registry.

### 4. Write the expansion function

The expander is pure and has no KDL dependency. It is identical to the
YAML version of this pattern except for the dash-bypass guard:

```haskell
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

expandAlias :: Map Text Text -> [String] -> [String]
expandAlias aliasMap = \case
  [] -> []
  (first : rest)
    | startsWithDash first         -> first : rest
    | T.pack first `elem` builtinCommands
                                   -> first : rest
    | otherwise -> case Map.lookup (T.pack first) aliasMap of
        Nothing        -> first : rest
        Just expansion -> map T.unpack (T.words expansion) <> rest
  where
    startsWithDash ('-' : _) = True
    startsWithDash _         = False
```

Key properties:

- **First-argument only** — only the first CLI argument is checked.
- **Single-pass** — no recursive expansion, so `tw` expanding to
  `today …` won't re-expand `today`.
- **Built-in protection** — built-in command names are never overridden.
- **Dash bypass** — argv whose first token starts with `-` is left
  alone. This protects `--version`, `--help`, and especially
  optparse-applicative's bash-completion entry argv
  (`--bash-completion-index N --bash-completion-word …`), which would
  otherwise hit the alias map on a misconfigured user file.
- **Argument appending** — remaining arguments are appended after the
  expansion.

### 5. Integrate into the main entry point

Replace `execParser` (which calls `getArgs` internally) with the
explicit `getArgs → expandAlias → execParserPure → handleParseResult`
sequence. You must load the config *before* parsing so the alias map
is available:

```haskell
runCli :: IO ()
runCli = do
  userConf <- loadUserConfigForAliases
  rawArgs  <- getArgs
  let expandedArgs = expandAlias (commandAliases userConf) rawArgs
  cmd <- handleParseResult $
    execParserPure (prefs showHelpOnEmpty) parserInfo expandedArgs
  -- … dispatch on cmd as before
```

Provide a forgiving config loader for the alias path so a malformed
config does not block the CLI from running its non-alias-dependent
commands:

```haskell
loadUserConfigForAliases :: IO UserConfig
loadUserConfigForAliases = do
  result <- loadUserConfig
  case result of
    Right cfg -> pure cfg
    Left  _   -> pure defaultUserConfig
```

If your project also wants to surface the same `UserConfig` to the
command handlers, capture it once here and thread the value through
rather than re-parsing the file later. notion-cli's
[`runCli`](https://github.com/shinzui/notion-cli/blob/main/notion-cli-exe/src/NotionCli/Cli.hs)
shows the full pattern: load → expand → parse → dispatch with the
already-loaded config in scope.

### 6. Add a CLI command to list aliases

A small inspection command lets users verify what their config produced:

```haskell
data AliasCommand = AliasList

aliasCommandParser :: Parser AliasCommand
aliasCommandParser =
  hsubparser
    ( command "list"
        (info (pure AliasList <**> helper)
              (progDesc "List configured aliases"))
    )
    <|> pure AliasList   -- default to list with no subcommand

handleAliasCommand :: Map Text Text -> AliasCommand -> IO ()
handleAliasCommand aMap AliasList
  | Map.null aMap =
      TIO.putStrLn "No aliases configured."
  | otherwise = do
      let maxKeyLen = maximum (map T.length (Map.keys aMap))
      mapM_
        (\(name, expansion) ->
          TIO.putStrLn $
            T.justifyLeft (maxKeyLen + 2) ' ' name <> "= " <> expansion)
        (Map.toAscList aMap)
```

Output:

```
$ mina alias list
h  = help
i  = rei intention show
ls = exec-plan list --status active
sh = rei intention show --full
tw = exec-plan list --status active
```

If the project already exposes a `config show` style subcommand, an
alternative is to surface the alias table there instead of adding a
top-level `alias` command — notion-cli does this with `config aliases`
because its `alias` namespace is already taken by a resource-alias
feature. Use a top-level `alias` command only when the namespace is
free.

## Validation

`validateAliases` is short — most pathological cases are unrepresentable
in the KDL grammar:

- **Empty alias names cannot occur.** KDL node names are non-empty by
  grammar.
- **Within-file duplicates are silently collapsed.** `KDL.remainingNodesWith`
  produces `Map Text [Text]`; `listToMaybe` keeps the first occurrence.
  This matches notion-cli; if you need duplicate detection, decode into
  `Map Text [Text]` and reject keys whose list has length > 1 before
  collapsing.
- **Reject dash-prefixed names.** They will always be skipped by the
  expander; flagging at config-load time avoids silent confusion.
- **Reject empty / whitespace-only expansions.** They expand to
  nothing and look like a typo.

```haskell
validateAliases :: AliasesSection -> [Text]
validateAliases s =
  Map.foldlWithKey check [] s.aliasMap
  where
    check errs name expansion =
      errs
        ++ [ "alias name starts with '-': " <> quoted name
           | "-" `T.isPrefixOf` name ]
        ++ [ "alias " <> quoted name <> " has empty expansion"
           | T.null (T.strip expansion) ]
    quoted t = "\"" <> t <> "\""
```

## Merging Across Config Files

If your project loads aliases from multiple KDL files (e.g. a global
`$XDG_CONFIG_HOME/<app>/config.kdl` plus a per-project `<app>.kdl`),
project entries should win on key collision, otherwise the union of
both maps:

```haskell
resolveAliasesSection ::
  Maybe AliasesSection ->  -- global
  Maybe AliasesSection ->  -- project
  Map Text Text
resolveAliasesSection mGlobal mProject =
  let g = maybe Map.empty (.aliasMap) mGlobal
      p = maybe Map.empty (.aliasMap) mProject
   in p `Map.union` g  -- left-biased: project wins
```

`Data.Map.Strict.union` is left-biased — its first argument wins on
key collision — so passing the project map first gives the desired
precedence.

## Design Decisions

- **Config file over CLI registration** — aliases live in user config,
  not in code. Users can add aliases without recompiling.
- **Pre-parse expansion** — expanding before optparse-applicative sees
  the args means aliases work with any command structure, including
  subcommands and flags. The alternative (registering each alias as
  its own optparse `command`) doesn't work because aliases live in a
  config file the binary loads at runtime, after the parser is built.
- **No recursive expansion** — keeps behaviour predictable. `a → b ...`
  and `b → c ...` won't chain; `a` expands to `b ...` and stops.
- **Built-in shadowing prevention** — the built-in commands list must
  be maintained manually but prevents a misconfigured alias from
  hiding a real command. Pair it with a unit test (see step 3) to
  catch drift.
- **Dash bypass** — argv whose first token starts with `-` is never
  expanded. Without this, optparse-applicative's bash-completion path
  (`--bash-completion-index 4 …`) and `--version`/`--help` would all
  be candidates for alias expansion, which is never what the user
  wants.
- **Idiomatic KDL shape** — use child node names as the alias keys
  (`aliases { tw "…" }`), not a wrapping verb (`aliases { alias "tw"
  "…" }`). The former is what `KDL.remainingNodesWith` was designed
  for and is what notion-cli does.

## Guidelines

- Keep the `builtinCommands` list in sync when adding new commands;
  back it with a registry test (every name parses, no extras).
- Aliases should expand to valid command invocations — there is no
  validation at config-load time beyond the dash and empty checks.
- `T.words` splitting means alias expansions can't contain arguments
  with embedded spaces. If a user needs that, recommend a shell alias
  instead.
- Consider adding `alias add` / `alias remove` commands if you want
  CLI-driven alias management. A KDL writer is required, which most
  projects do not have today; in mina and notion-cli the user edits
  the KDL file directly.
- If your config supports global + project layers, apply the
  project-wins union from the merging section above. Mirror whatever
  precedence policy your other sections use.
- `KDL.remainingNodesWith` consumes every child node in its scope, so
  do not put unrelated nodes inside `aliases { … }`. Each child must
  decode as `KDL.arg @Text`.

## Known Implementations

- [`notion-cli`](file:///Users/shinzui/Keikaku/bokuno/notion-cli) — first
  in-tree adoption (2026-03-29). Uses section name `command-alias` and
  module `NotionCli.CommandAlias` to avoid collision with its
  pre-existing resource-alias feature.
  See `notion-cli-core/src/NotionCli/Config/Types.hs:106-120` for the
  decoder and `notion-cli-exe/src/NotionCli/CommandAlias.hs` for the
  expander.
- [`mina`](file:///Users/shinzui/Keikaku/bokuno/mina) — second adoption
  (2026-04-30, `docs/plans/43-support-user-defined-command-aliases.md`).
  Uses the cleaner section name `aliases` and module
  `Mina.CLI.Aliases` because no namespace collision exists. Also
  applies the global+project merge pattern documented above.

When porting to a new project, prefer the shorter `aliases` section
name unless your CLI already uses `alias` for an unrelated feature.
