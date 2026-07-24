---
type: Pattern
title: "Hierarchical Config with Dhall"
description: "Layer user and project Dhall configuration for legacy CLIs; superseded by Settei for new work"
timestamp: 2026-07-22T12:43:31-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-hierarchical-config
tags: [cli, configuration, dhall, layering, legacy, settei]
status: legacy
---

# Hierarchical Config with Dhall

A pattern for structuring CLI configuration into separate, layered Dhall files — user-wide settings, per-project identity, and per-project automation — each with its own schema, discovery logic, and validation pipeline.

> **Superseded for new work.** The layered-Dhall pattern below is superseded by the
> settei configuration standard for all new keiro-fleet CLIs and services. See the
> `keiro-runtime-patterns` repo (mori project `shinzui/keiro-runtime-patterns`):
> `config/settei-cli-standard.md` (DocRef `config-settei-cli-standard`) and
> `config/settei-service-standard.md` (DocRef `config-settei-service-standard`).
> This document remains valid for tools already built on layered Dhall.

## Problem

A CLI tool that manages multi-project workflows needs configuration at multiple scopes:

- **User preferences** (aliases, display settings) that apply across all projects
- **Project identity** (name, packages, dependencies) that is checked into a specific repo
- **Automation policy** (event selectors, reactions) that is project-specific but separate from identity

Cramming all of these into a single config file conflates concerns. A flat approach forces users to repeat preferences per project, or pollutes project-level config with personal settings. Splitting into layers with clear ownership and discovery rules keeps each file focused and independently valid.

## How It Works

```
~/.config/mori/config.dhall          ← User config (aliases, CLI behavior)
        │                                 Discovered via precedence chain
        ▼
    loadUserConfig
        │
        ▼
   expandAlias → optparse-applicative

./mori.dhall                          ← Project config (identity, packages, deps)
        │                                 Fixed location in project root
        ▼
    loadConfig → validateConfig

./mori.automation.dhall               ← Automation config (selectors, reactions)
   or ./automation/*.dhall                Single file or directory of fragments
        │                                 Loaded and merged, then validated
        ▼
    loadAutomationConfigPath → mergeAutomationConfigs → validateAutomationConfig
```

Key property: **no merging between layers**. Each layer is a distinct concern with its own schema. The user config governs CLI behavior, the project config declares what the project is, and the automation config declares how it reacts to events.

## Dependencies

```
dhall                   -- Dhall interpreter (inputFile, FromDhall)
transformers            -- ExceptT for flattening fallible IO pipelines
directory               -- doesFileExist, getHomeDirectory, listDirectory
filepath                -- (</>) for path construction
containers              -- Map for alias maps
```

GHC extensions:
```
DeriveGeneric
DuplicateRecordFields
OverloadedLabels
StrictData
```

## Implementation

### 1. Define the user config layer

The user config governs CLI-wide behavior. It lives outside any project directory.

```haskell
-- | User-level configuration (loaded from config.dhall)
data UserConfig = UserConfig
  { aliases :: !AliasConfig
  }
  deriving stock (Generic, Show, Eq)

instance FromDhall UserConfig

-- | Alias configuration: maps short names to command expansions
newtype AliasConfig = AliasConfig
  { aliasMap :: Map Text Text
  }
  deriving stock (Generic, Show, Eq)
  deriving newtype (FromDhall)

-- | Default user configuration (no aliases)
defaultUserConfig :: UserConfig
defaultUserConfig =
  UserConfig { aliases = AliasConfig Map.empty }
```

The Dhall schema:

```dhall
-- ~/.config/mori/config.dhall
{ aliases : List { mapKey : Text, mapValue : Text } }
```

Example file:

```dhall
{ aliases = toMap { reg = "registry list", sh = "show --full" } }
```

### 2. Implement precedence-based discovery for user config

The user config is found by checking locations in priority order. The first match wins — no merging across locations.

```haskell
-- | Source of the configuration file
data ConfigSource
  = ConfigFromEnv    -- ^ MORI_CONFIG environment variable
  | ConfigFromLocal  -- ^ ./mori-config.dhall (current directory)
  | ConfigFromXDG    -- ^ ~/.config/mori/config.dhall
  | ConfigFromDot    -- ^ ~/.mori/config.dhall (legacy)
  deriving stock (Eq, Show)

-- | Find the config file with its source.
-- Checks in order: MORI_CONFIG env var, local, XDG, dot.
findConfigFileWithSource :: IO (Maybe (FilePath, ConfigSource))
findConfigFileWithSource = do
  mEnvPath <- lookupEnv "MORI_CONFIG"
  case mEnvPath of
    Just envPath -> do
      envExists <- doesFileExist envPath
      if envExists
        then pure (Just (envPath, ConfigFromEnv))
        else findLocalOrGlobalConfig
    Nothing -> findLocalOrGlobalConfig
  where
    findLocalOrGlobalConfig = do
      localPath <- localConfigPath
      localExists <- doesFileExist localPath
      if localExists
        then pure (Just (localPath, ConfigFromLocal))
        else findGlobalConfig

    findGlobalConfig = do
      xdgPath <- xdgConfigPath
      xdgExists <- doesFileExist xdgPath
      if xdgExists
        then pure (Just (xdgPath, ConfigFromXDG))
        else do
          dotPath' <- dotConfigPath
          dotExists <- doesFileExist dotPath'
          if dotExists
            then pure (Just (dotPath', ConfigFromDot))
            else pure Nothing
```

Loading falls back to defaults when no config file exists:

```haskell
loadUserConfig :: IO (Either Text UserConfig)
loadUserConfig = do
  mPath <- findConfigFile
  case mPath of
    Nothing -> pure $ Right defaultUserConfig
    Just path -> do
      result <- try $ inputFile auto path
      case result of
        Left (e :: SomeException) ->
          pure $ Left $ "Failed to parse user config: " <> pack (show e)
        Right config -> pure $ Right config
```

### 3. Define the project config layer

The project config lives at a fixed, well-known path (`mori.dhall`) in the project root. It has a rich schema covering project identity, packages, dependencies, and documentation.

```haskell
data MoriConfig = MoriConfig
  { project      :: !Project,
    repos        :: ![Repo],
    packages     :: ![Package],
    bundles      :: ![PackageBundle],
    dependencies :: ![Text],
    apis         :: ![Api],
    agents       :: ![AgentHint],
    skills       :: ![Skill],
    subagents    :: ![Subagent],
    standards    :: ![Text],
    docs         :: ![DocRef]
  }
  deriving stock (Generic, Show, Eq)

instance FromDhall MoriConfig
```

Loading uses `ExceptT` to flatten the three-stage pipeline (existence check, Dhall parse, semantic validation) into a linear sequence with no nesting:

```haskell
data ConfigError
  = ConfigFileNotFound !FilePath
  | ConfigParseError !Text
  | ConfigValidationError ![ValidationError]
  deriving stock (Show, Eq)

loadConfig :: FilePath -> IO (Either ConfigError MoriConfig)
loadConfig path = runExceptT $ do
  exists <- liftIO $ doesFileExist path
  unless exists $ throwE $ ConfigFileNotFound path
  result <- liftIO $ try @SomeException $ inputFile auto path
  cfg <- except $ first (ConfigParseError . pack . show) result
  except $ first ConfigValidationError $ validateConfig cfg
```

Each line is one step: `unless` guards with early exit, `except` lifts a pure `Either` into `ExceptT` while `first` maps the error type. No nested if/else or cascading case expressions.

### 4. Add semantic validation for project config

Dhall's type checker handles structural validation. Semantic rules are checked in a separate pass after parsing succeeds:

```haskell
data ValidationError
  = InvalidNamespace !Text !Text
  | DuplicatePackageName !Text
  | EmptyDependencyName
  | InvalidBundleRef !Text !Text
  | MissingBundlePrimary !Text !Text
  | ApiSourceProjectNotInDependencies !Text !Text
  deriving stock (Show, Eq)

validateConfig :: MoriConfig -> Either [ValidationError] MoriConfig
validateConfig cfg =
  let errs =
        validateNamespace cfg
          <> validatePackageNames cfg
          <> validateDependencies cfg
          <> validateBundles cfg
          <> validateApiSources cfg
   in if null errs then Right cfg else Left errs
```

This separation means Dhall catches schema violations (wrong types, missing fields) and the Haskell validator catches cross-field invariants (duplicate names, dangling references).

### 5. Define the automation config layer

The automation config is an optional, separate Dhall file (`mori.automation.dhall`) or a directory of Dhall fragments. It has its own schema, independent from the project config.

```haskell
data AutomationConfig = AutomationConfig
  { events    :: ![EventSelector],
    reactions :: ![ReactionDef],
    execution :: !ExecutionPolicy
  }
  deriving stock (Generic, Eq, Show)

data EventSelector
  = ChangesetSelector !ChangesetSelectorData
  | RefSelector !RefSelectorData
  | SignalSelector !SignalSelectorData
  deriving stock (Generic, Eq, Show)
```

### 6. Support directory-based config splitting with merge

For the automation layer, allow either a single file or a directory of `.dhall` files that are merged:

```haskell
loadAutomationConfigPath :: FilePath -> IO (Either AutomationConfigError AutomationConfig)
loadAutomationConfigPath path = do
  isDir <- doesDirectoryExist path
  if isDir
    then loadAutomationConfigDir path
    else loadAutomationConfig path

-- | Merge multiple automation configs into one.
-- Events and reactions are concatenated. Execution policy is taken from the
-- first config.
mergeAutomationConfigs :: [AutomationConfig] -> Maybe AutomationConfig
mergeAutomationConfigs [] = Nothing
mergeAutomationConfigs (first : rest) =
  Just
    AutomationConfig
      { events = concatMap (^. #events) (first : rest),
        reactions = concatMap (^. #reactions) (first : rest),
        execution = first ^. #execution
      }
```

Validation runs *after* merging to catch cross-file issues (e.g., a reaction referencing a selector defined in a different fragment):

```haskell
validateAutomationConfig :: AutomationConfig -> Either [Text] AutomationConfig
validateAutomationConfig cfg =
  let selectorNames = map getSelectorName (cfg ^. #events)
      dupes = selectorNames \\ nub selectorNames
      dupeErrors =
        [ "Duplicate selector name: " <> n | n <- nub dupes ]
      reactionOnNames = concatMap (^. #on) (cfg ^. #reactions)
      unknownRefs =
        [ "Reaction references unknown selector: " <> n
        | n <- reactionOnNames, n `notElem` selectorNames ]
   in if null (dupeErrors <> unknownRefs)
        then Right cfg
        else Left (dupeErrors <> unknownRefs)
```

### 7. Wire layers into the CLI entry point

Each layer is loaded independently. The user config is always loaded (for alias expansion). The project and automation configs are loaded only by commands that need them.

```haskell
runCli :: IO ()
runCli = do
  -- Layer 1: User config (always loaded, defaults if missing)
  userConfigResult <- loadUserConfig
  let aliasConf = case userConfigResult of
        Right cfg -> cfg ^. #aliases
        Left _err -> AliasConfig mempty

  -- Expand aliases before parsing
  rawArgs <- getArgs
  let expandedArgs = expandAlias (aliasMap aliasConf) rawArgs

  -- Parse with alias-expanded args
  cmd <- handleParseResult $
    execParserPure (prefs showHelpOnEmpty) parserInfo expandedArgs

  case cmd of
    -- Layer 2: Project config (loaded by commands that need it)
    Show opts -> runShow opts      -- reads ./mori.dhall internally
    Validate opts -> runValidate opts

    -- Layer 3: Automation config (loaded by automation commands)
    Automate automateCmd -> do
      pool <- setupPool
      runAutomate pool automateCmd  -- reads ./mori.automation.dhall internally
      Pool.release pool

    -- Commands that don't need project/automation config
    Alias aliasCmd -> runAlias aliasConf aliasCmd
    Help helpCmd -> handleHelpCommand helpCmd
    -- ...
```

### 8. Map Haskell constructors to Dhall names

When Haskell constructor names differ from Dhall union alternatives (to avoid name collisions or reserved words), use custom `InterpretOptions`:

```haskell
mkConstructorOpts :: [(Text, Text)] -> InterpretOptions
mkConstructorOpts mappings =
  defaultInterpretOptions
    { constructorModifier = \hs -> case lookup hs mappings of
        Just dhall -> dhall
        Nothing -> hs
    }

mkFieldOpts :: [(Text, Text)] -> InterpretOptions
mkFieldOpts fieldMappings =
  defaultInterpretOptions
    { fieldModifier = \hs -> case lookup hs fieldMappings of
        Just dhall -> dhall
        Nothing -> hs
    }

-- Example: Haskell `OriginOwn` ↔ Dhall `Own`
instance FromDhall Origin where
  autoWith =
    autoWithOpts $
      mkConstructorOpts
        [ ("OriginOwn", "Own"),
          ("OriginThirdParty", "ThirdParty"),
          ("OriginFork", "Fork"),
          ("OriginVendored", "Vendored")
        ]

-- Example: Haskell field `packageType` ↔ Dhall field `type`
instance FromDhall Project where
  autoWith = autoWithOpts $ mkFieldOpts [("projectType", "type")]
```

This keeps Haskell names unambiguous (no `DuplicateRecordFields` conflicts, no reserved-word clashes) while Dhall schemas use the natural, short names that config authors expect.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate files per layer | Each concern (identity, behavior, automation) has different audiences, change frequency, and review requirements. A user shouldn't need to edit project config to add an alias. |
| No merging between layers | Layers are orthogonal. Merging would imply one layer can override another, which makes no sense — aliases don't override project names. |
| First-found-wins for user config | Simple mental model. Users can override with `MORI_CONFIG` env var for testing without touching their real config. |
| Merging *within* automation layer | Large automation configs benefit from splitting by concern (e.g., `ci.dhall`, `deploy.dhall`). Merging lets teams own fragments independently. |
| Validate after merge | Cross-fragment references (reactions → selectors) can only be checked after all fragments are combined. |
| Dhall over YAML/TOML | Type-checked schemas, import system (configs can reference shared types), no YAML footguns (Norway problem, implicit type coercion). |
| Defaults when config missing | User config is optional — the CLI works out of the box. Project config is required only for project-aware commands. |
| Three-stage error pipeline | Parse errors (Dhall), type errors (Dhall), semantic errors (Haskell) each have distinct causes and fixes. Collapsing them into one error type obscures the problem. |

## When to Use

- Your CLI has configuration at multiple scopes (user, project, environment)
- Different config layers change at different rates and have different owners
- You want type-safe config with schema evolution support (Dhall's import system handles this)
- Automation/policy config benefits from splitting into composable fragments

## When NOT to Use

- A single config file is sufficient — don't add layers for hypothetical future needs
- Your config is simple enough for environment variables or a single YAML file
- You don't need the type safety or import system that Dhall provides
