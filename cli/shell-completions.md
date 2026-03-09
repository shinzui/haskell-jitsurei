# Shell Completion Generation

A pattern for generating Bash, Zsh, and Fish completion scripts from a declarative command definition in Haskell. Uses a custom generator approach rather than optparse-applicative's built-in completion system, giving full control over the output.

## Architecture

```
Completions/
├── Types.hs       -- CommandDef type, helpers
├── Commands.hs    -- Single source of truth for all commands
├── Bash.hs        -- Bash script generator
├── Zsh.hs         -- Zsh script generator
├── Fish.hs        -- Fish script generator
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

## 1. Command Definition (Single Source of Truth)

All CLI commands are declared in a single module as a tree of `CommandDef` values. This is the only place you need to update when adding commands.

```haskell
data CommandDef = CommandDef
  { cmdName      :: String        -- command name
  , cmdDesc      :: String        -- one-line description (shown in shell help)
  , cmdSubs      :: [CommandDef]  -- nested subcommands
  , cmdNeedsFile :: Bool          -- enable file path completion
  }

-- Helper: create a command without file completion
cmd :: String -> String -> [CommandDef] -> CommandDef
cmd name desc subs = CommandDef name desc subs False
```

### Command tree example

```haskell
allCommands :: [CommandDef]
allCommands =
  [ cmd "intention" "Manage intentions" intentionSubs
  , cmd "habit"     "Manage habits"     habitSubs
  , cmd "today"     "Show daily dashboard" []
  , cmd "help"      "Show help topics"  []
  , cmd "completions" "Generate shell completions" completionsSubs
  ]

intentionSubs :: [CommandDef]
intentionSubs =
  [ cmd "create"   "Create a new intention"    []
  , cmd "show"     "Show intention details"    []
  , cmd "complete" "Mark intention complete"   []
  , cmd "note"     "Manage notes for intention" intentionNoteSubs
  ]

intentionNoteSubs :: [CommandDef]
intentionNoteSubs =
  [ cmd "open" "Open a note" []
  , cmd "list" "List notes"  []
  ]

completionsSubs :: [CommandDef]
completionsSubs =
  [ cmd "bash" "Generate Bash completions" []
  , cmd "zsh"  "Generate Zsh completions"  []
  , cmd "fish" "Generate Fish completions" []
  ]
```

Supports 3 levels of nesting: `myapp command subcommand sub-subcommand`.

## 2. File Completion

Some commands accept file path arguments. These are declared separately:

```haskell
fileArgCommands :: [(String, String)]
fileArgCommands =
  [ ("doc", "attach")  -- myapp doc attach <file>
  ]
```

Each generator uses this list to emit shell-specific file completion logic (Bash: `_filedir`, Zsh: `_files`, Fish: `-F`).

## 3. Handler

The handler routes to the appropriate generator, passing the command tree:

```haskell
data CompletionsCommand
  = CompletionsBash
  | CompletionsZsh
  | CompletionsFish

handleCompletionsCommand :: CompletionsCommand -> IO ()
handleCompletionsCommand = \case
  CompletionsBash -> TIO.putStrLn $ generateBashCompletion allCommands
  CompletionsZsh  -> TIO.putStrLn $ generateZshCompletion allCommands
  CompletionsFish -> TIO.putStrLn $ generateFishCompletion allCommands
```

## 4. Bash Generator

Generates a `_myapp_completions()` function using standard Bash completion builtins.

**Strategy:**
- Store subcommand names in shell variables (`intention_cmds="create show complete note"`)
- At `cword == 1`: complete with top-level commands via `compgen -W`
- At `cword == 2`: `case` on the first word, complete with that command's subcommands
- File commands: check parent + subcommand match, call `_filedir`

```haskell
generateBashCompletion :: [CommandDef] -> Text
generateBashCompletion cmds = T.unlines
  [ "_myapp_completions() {"
  , "    local cur prev words cword"
  , "    _init_completion || return"
  , ""
  , "    local commands=\"" <> topLevelNames <> "\""
  ,      subcommandVars          -- local intention_cmds="create show ..."
  , ""
  , "    if [[ $cword -eq 1 ]]; then"
  , "        COMPREPLY=($(compgen -W \"$commands\" -- \"$cur\"))"
  , "        return"
  , "    fi"
  , ""
  ,      fileCompletionCheck     -- if doc attach at cword >= 3, _filedir
  , ""
  , "    case ${words[1]} in"
  ,      subcommandCases         -- intention) compgen -W "$intention_cmds" ...
  , "    esac"
  , "}"
  , ""
  , "complete -F _myapp_completions myapp"
  ]
```

**Subcommand variable generation:**

```haskell
generateBashSubcommandVars :: [CommandDef] -> Text
generateBashSubcommandVars cmds = T.unlines
  [ "    local " <> pack (cmdName c) <> "_cmds=\""
      <> pack (unwords (map cmdName (cmdSubs c))) <> "\""
  | c <- cmds
  , not (null (cmdSubs c))
  ]
```

**Case generation:**

```haskell
generateBashCases :: [CommandDef] -> Text
generateBashCases cmds = T.unlines
  [ T.unlines
      [ "        " <> pack (cmdName c) <> ")"
      , "            if [[ $cword -eq 2 ]]; then"
      , "                COMPREPLY=($(compgen -W \"$" <> pack (cmdName c) <> "_cmds\" -- \"$cur\"))"
      , "            fi"
      , "            ;;"
      ]
  | c <- cmds
  , not (null (cmdSubs c))
  ]
```

## 5. Zsh Generator

Generates a `_myapp()` function with `#compdef` tag. Zsh completions show descriptions alongside command names via `_describe`.

**Strategy:**
- Declare arrays for each command level (`local -a intention_cmds`)
- Fill arrays with `'name:description'` pairs
- At `CURRENT == 2`: `_describe` top-level commands
- At `CURRENT == 3`: `case` on `$words[2]`, `_describe` subcommands
- At `CURRENT == 4`: nested `case` for 3rd-level subcommands
- At `CURRENT >= 5`: file completion check

```haskell
generateZshCompletion :: [CommandDef] -> Text
generateZshCompletion cmds = T.unlines
  [ "#compdef myapp"
  , ""
  , "_myapp() {"
  , "    local -a commands"
  ,      arrayDecls               -- local -a intention_cmds
  ,      nestedArrayDecls         -- local -a intention_note_cmds
  , ""
  , "    commands=("
  ,      commandList              -- 'intention:Manage intentions'
  , "    )"
  ,      subcommandArrays        -- intention_cmds=('create:...' 'show:...')
  ,      nestedArrays            -- intention_note_cmds=('open:...' 'list:...')
  , ""
  , "    if (( CURRENT == 2 )); then"
  , "        _describe -t commands 'myapp commands' commands"
  , "    elif (( CURRENT == 3 )); then"
  , "        case $words[2] in"
  ,          cases                -- intention) _describe ... intention_cmds ;;
  , "        esac"
  , "    elif (( CURRENT == 4 )); then"
  ,          nestedCases          -- intention) case $words[3] in note) ... esac ;;
  , "    elif (( CURRENT >= 5 )); then"
  ,          fileCheck            -- doc) case $words[3] in attach) _files ;; ...
  , "    fi"
  , "}"
  , ""
  , "_myapp"
  ]
```

**Zsh variable naming:** hyphens in command names are converted to underscores for valid shell identifiers:

```haskell
toZshVarName :: String -> Text
toZshVarName = pack . map (\c -> if c == '-' then '_' else c)
-- "custom-property" → "custom_property"
```

**Command list with descriptions:**

```haskell
generateZshCommandList :: [CommandDef] -> Int -> Text
generateZshCommandList cmds indent = T.intercalate "\n"
  [ T.replicate indent " " <> "'" <> pack (cmdName c) <> ":" <> pack (cmdDesc c) <> "'"
  | c <- cmds
  ]
```

## 6. Fish Generator

Fish uses a declarative `complete` command syntax — no function needed.

**Strategy:**
- `complete -c myapp -f` disables file completion by default
- Top-level: condition `__fish_use_subcommand`
- Subcommands: condition `__fish_seen_subcommand_from parent`
- File commands: add `-F` flag for specific parent+sub combinations

```haskell
generateFishCompletion :: [CommandDef] -> Text
generateFishCompletion cmds = T.unlines $
  [ "# Disable file completion by default"
  , "complete -c myapp -f"
  , ""
  , "# Main commands"
  ]
  ++ [generateFishMainCommand c | c <- cmds]
  ++ [""]
  ++ concatMap generateFishSubcommands cmds
  ++ generateFishFileCompletions
```

**Main commands:**

```haskell
generateFishMainCommand :: CommandDef -> Text
generateFishMainCommand c =
  "complete -c myapp -n \"__fish_use_subcommand\" -a "
    <> pack (cmdName c) <> " -d \"" <> pack (cmdDesc c) <> "\""
```

**Subcommands:**

```haskell
generateFishSubcommands :: CommandDef -> [Text]
generateFishSubcommands c
  | null (cmdSubs c) = []
  | otherwise =
      ["# " <> T.toTitle (pack (cmdName c)) <> " subcommands"]
        ++ [ "complete -c myapp -n \"__fish_seen_subcommand_from "
               <> pack (cmdName c) <> "\" -a "
               <> pack (cmdName s) <> " -d \"" <> pack (cmdDesc s) <> "\""
           | s <- cmdSubs c
           ]
        ++ [""]
```

## 7. Adding a New Command

1. Add the entry to the appropriate list in `Commands.hs`:
   ```haskell
   intentionSubs =
     [ ...existing...
     , cmd "archive" "Archive an intention" []   -- new
     ]
   ```

2. If it accepts file arguments, add to `fileArgCommands` in `Types.hs`:
   ```haskell
   fileArgCommands =
     [ ("doc", "attach")
     , ("doc", "import")   -- new
     ]
   ```

3. Rebuild and regenerate:
   ```bash
   cabal build
   myapp completions bash > ~/.local/share/bash-completion/completions/myapp
   ```

No changes needed in the generator modules — they operate on the `[CommandDef]` tree.

## Why Not optparse-applicative's Built-In Completions?

optparse-applicative has a `--bash-completion-script` mechanism, but the custom approach offers:

| Aspect | Built-in | Custom generator |
|--------|----------|-----------------|
| Descriptions in Zsh/Fish | No | Yes (via `_describe` / `-d`) |
| File completion control | Limited | Per-command granularity |
| Output format control | Fixed | Full control per shell |
| Runtime dependency | Calls binary for each completion | Static script, no callbacks |
| Nesting depth | Automatic | Explicit (currently 3 levels) |
| Maintenance | Automatic from parsers | Manual `Commands.hs` updates |

The tradeoff is maintaining `Commands.hs` in sync with the actual parsers. In practice this is manageable — new commands are rare relative to other changes, and a missing completion is a minor inconvenience, not a bug.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Static scripts (no binary callbacks) | Faster completions, works offline, no process spawn per keystroke |
| Single `Commands.hs` source of truth | One place to update, all three shells stay in sync |
| `cmdDesc` on every command | Zsh and Fish display descriptions; Bash ignores them |
| `fileArgCommands` as separate list | File completion is opt-in; most commands don't need it |
| Hyphens → underscores in Zsh vars | Zsh variable names can't contain hyphens |
| `complete -c myapp -f` in Fish | Disable default file completion; re-enable selectively with `-F` |
