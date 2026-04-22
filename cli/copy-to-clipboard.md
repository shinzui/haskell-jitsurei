# Copy Command Result to System Clipboard

A pattern for adding an opt-in `--copy` / `-c` flag that copies a command's primary output (typically a path or identifier) to the system clipboard, without interfering with normal stdout. Works on macOS (`pbcopy`) and Linux (`xclip`), degrades gracefully when neither is installed, and composes with other CLI patterns (fzf pickers, stdin piping).

## When to use it

- The command's stdout is a single short value the user is likely to paste into another terminal, a PR description, or an editor (paths, URLs, hashes, rendered templates).
- The value is already being written to stdout, so the command remains pipe-friendly (`cmd | xargs code`) and the clipboard copy is purely additive.
- The user shouldn't have to install a dependency; if `pbcopy`/`xclip` is missing, the command still succeeds — it just prints a warning.

If the command already prints a multi-line report and only one field is copy-worthy, either narrow the `--copy` flag to that field or split the command.

## Core Utility

Two small top-level functions encapsulate the whole pattern. Keep them in the command module that first needs them; promote to a shared `Cli.Clipboard` module once a second command opts in.

```haskell
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Exit (ExitCode (..))
import System.IO (stderr)
import System.Info (os)
import System.Process (readProcessWithExitCode)

-- | Copy text to the system clipboard when the flag is set; no-op otherwise.
--   Never fails the command — a missing clipboard tool is reported on stderr.
maybeCopyToClipboard :: Bool -> Text -> IO ()
maybeCopyToClipboard False _ = pure ()
maybeCopyToClipboard True txt = do
  let (cmd, args) = clipboardCommand
  (exitCode, _stdout, _stderr) <- readProcessWithExitCode cmd args (T.unpack txt)
  case exitCode of
    ExitSuccess -> TIO.hPutStrLn stderr "  ✓ Copied to clipboard"
    ExitFailure _ ->
      TIO.hPutStrLn stderr $
        "  ⚠ Could not copy to clipboard (" <> T.pack cmd <> " not available)"

-- | Platform-specific clipboard command.
clipboardCommand :: (String, [String])
clipboardCommand = case os of
  "darwin" -> ("pbcopy", [])
  _        -> ("xclip", ["-selection", "clipboard"])
```

Key design choices:

- **`Bool -> Text -> IO ()` signature.** The flag is passed through the call stack rather than checked globally, so the copy side-effect is visible in each call site and easy to disable per code path.
- **`False` is a fast no-op.** Every printing function can call `maybeCopyToClipboard copy value` unconditionally; the flag gates the work.
- **Stdout stays clean.** The copied value goes to the clipboard via a child process (its stdin), not stdout. The command still prints the same value on stdout, so shell pipelines keep working.
- **Status goes to stderr.** Success (`✓ Copied to clipboard`) and failure (`⚠ Could not copy …`) messages are written to `stderr` so they never contaminate piped output.
- **Failure is soft.** A missing `pbcopy`/`xclip` prints a warning but the command exits successfully — the primary purpose (printing the value) has already happened.
- **`System.Info.os`, not runtime probing.** On macOS we always use `pbcopy`; elsewhere we assume `xclip`. For Wayland-only systems the user can install `xclip` (a thin X11 compat tool) or the utility can be extended to probe `wl-copy` first.

## Parser

Add a `switch` for the flag and store it on the options record. Keep the field name descriptive (`copyToClipboard`) rather than reusing the short flag name.

```haskell
data PathOpts = PathOpts
  { projectRef      :: !(Maybe Text)
  , pathTarget      :: !PathTarget
  , copyToClipboard :: !Bool
  }
  deriving stock (Generic, Show)

pathOptsParser :: Parser PathOpts
pathOptsParser =
  PathOpts
    <$> optional (strArgument (metavar "PROJECT" <> help "…"))
    <*> pathTargetParser
    <*> switch
      ( long "copy"
          <> short 'c'
          <> help "Copy the resolved path to the system clipboard"
      )
```

Conventions:

- **`--copy` / `-c`** — consistent long and short names across commands. Pick one and stick with it; muscle memory is the whole point.
- **Help text names the value.** "Copy the resolved path …" tells the user exactly what ends up on the clipboard, which matters when the command prints more than one thing.
- **`switch`, not `flag'`.** The flag defaults to `False`, so presence means "yes".

## Handler

Thread the `Bool` through every function that eventually reaches a `TIO.putStrLn`. Each "print and copy" site reads the same way:

```haskell
runPath :: Pool.Pool -> PathOpts -> IO ()
runPath pool opts = do
  let copy = opts ^. #copyToClipboard
  case opts ^. #projectRef of
    Just pRef -> do
      proj <- resolveProject pool cats pRef
      runPathForProject pool cats proj (opts ^. #pathTarget) copy
    Nothing ->
      selectProjectFzf pool cats (opts ^. #pathTarget) copy

checkAndPrintPath :: Text -> Text -> Bool -> IO ()
checkAndPrintPath qualifiedName path copy = do
  exists <- doesDirectoryExist (T.unpack path)
  if exists
    then do
      TIO.putStrLn path          -- stdout: the primary output
      maybeCopyToClipboard copy path  -- optional clipboard side-effect
    else do
      TIO.hPutStrLn stderr $ "…"
      exitFailure
```

The idiom is always the same three lines:

```haskell
TIO.putStrLn value
maybeCopyToClipboard copy value
-- (nothing else — don't branch on `copy` at the call site)
```

### Multiple terminal branches

A command can resolve its output along several branches (direct arg, fzf pick, fallback to a different path). Thread `copy` to *every* branch rather than wrapping the whole command in a single copy-at-the-end helper. Reasons:

- The value to copy is often computed inside the branch (e.g., a package path absolutised against a project root), and lifting it out produces awkward plumbing.
- Error branches (`exitFailure`) must not copy. Keeping `maybeCopyToClipboard` next to `TIO.putStrLn` makes "copy iff we successfully printed" obvious.

### Don't copy on error

If the command fails — path doesn't exist, project not found, fzf cancelled — skip the copy. The utility is never called on the error path; users ending up with a stale clipboard entry after a failure is worse than no copy at all.

## Interaction with fzf pickers

The pattern composes cleanly with interactive selection (see `fzf-integration.md`). Pass `copy` into every selector so the picked value still ends up on the clipboard:

```haskell
selectProjectFzf :: Pool.Pool -> StreamCategories -> PathTarget -> Bool -> IO ()
selectProjectFzf pool cats target copy = do
  -- …runFzf…
  case fzfResult of
    FzfSelected proj -> runPathForProject pool cats proj target copy
    FzfCancelled     -> pure ()  -- nothing selected, nothing to copy
    FzfNoMatch       -> …
    FzfError err     -> …
```

fzf reads keystrokes from `/dev/tty`, not stdin, so this also composes with stdin piping (see `stdin-integration.md`): a user can pipe into the command *and* use fzf *and* get the result on the clipboard, all at once.

## Usage

```bash
# Default: print to stdout, leave clipboard alone
myapp path shinzui/haskell-jitsurei
# → /Users/alice/code/haskell-jitsurei

# Same value, also copied to clipboard
myapp path shinzui/haskell-jitsurei --copy
# → /Users/alice/code/haskell-jitsurei
#   ✓ Copied to clipboard

# Short flag, composes with fzf picker
myapp path -c
# (fzf picker opens; selected project's path is printed AND copied)

# Still pipe-safe — the clipboard copy is a side channel
myapp path shinzui/foo -c | xargs code
```

## Platform notes

| OS                | Command used     | Install via              |
|-------------------|------------------|--------------------------|
| macOS             | `pbcopy`         | Preinstalled             |
| Linux (X11)       | `xclip`          | `apt install xclip` etc. |
| Linux (Wayland)   | `xclip` (via XWayland) or extend to `wl-copy` | `apt install xclip` / `wl-clipboard` |
| Windows (MSYS)    | Not supported    | Extend `clipboardCommand` |

To add Wayland-native support, probe for `wl-copy` before falling back to `xclip`:

```haskell
clipboardCommand :: (String, [String])
clipboardCommand = case os of
  "darwin" -> ("pbcopy", [])
  "linux"  | isWayland -> ("wl-copy", [])
  _        -> ("xclip", ["-selection", "clipboard"])
  where
    isWayland = … -- check WAYLAND_DISPLAY env var at startup
```

Keep the detection cheap — a one-shot env-var read at process start is fine; don't probe on every print.

## When *not* to use this pattern

- **Long / multi-line output.** A clipboard full of a rendered report is rarely useful; prefer `| pbcopy` in the user's shell or a `--format` flag that emits a dedicated copy-friendly form.
- **Secrets.** Don't silently put API tokens or passwords on the clipboard. If you must, warn the user and consider clearing the clipboard after a timeout.
- **Commands where the "primary value" is ambiguous.** If the user would have to read the help to know what `--copy` puts on the clipboard, the command is too polymorphic; split it first.
