---
type: Pattern
title: "Custom Prelude Pattern"
description: "Centralize common re-exports and project-wide utilities in a small project prelude"
timestamp: 2026-06-19T08:57:05-07:00
resource: mori://shinzui/haskell-jitsurei/docs/core-custom-prelude
tags: [core, haskell, prelude, imports, generic-lens]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-06-19T08:57:05-07:00
    scope: catalog-metadata
    outcome: approved
---

# Custom Prelude Pattern

Define a project-level prelude module that re-exports commonly used types and functions, reducing repetitive imports across the codebase.

## Motivation

Haskell projects accumulate a set of imports that appear in nearly every module — `Text`, `Generic`, `FromJSON`/`ToJSON`, lens operators, `MonadIO`, etc. A custom prelude centralizes these into a single import, which:

- **Reduces boilerplate** — one import replaces ten or more
- **Enforces consistency** — every module gets the same foundational types
- **Provides a home for small project-wide utilities** that don't belong in any domain module

## Module Structure

Name the module `<Project>.Prelude` and place it in the core library package:

```haskell
-- src/Service/Prelude.hs
module Service.Prelude
  ( module X
  , module Control.Lens
  )
where

import "base" GHC.Generics as X (Generic)
import "base" Control.Monad as X (void, when, unless, guard)
import "base" Data.Maybe as X (fromMaybe, isJust, isNothing)
import "base" Data.Proxy as X (Proxy(..))
import "base" Control.Applicative as X ((<|>))
import "base" Control.Monad.IO.Class as X (MonadIO, liftIO)
import "base" Data.List.NonEmpty as X (NonEmpty(..))

import "text" Data.Text as X (Text)

import "aeson" Data.Aeson as X
  ( FromJSON, ToJSON
  , parseJSON, toJSON, fromJSON, toEncoding
  , genericParseJSON, genericToJSON, genericToEncoding
  , Options, SumEncoding(..), defaultOptions
  )
import "aeson" Data.Aeson.Casing as X (camelTo2)

import "time" Data.Time as X (UTCTime, getCurrentTime)

-- Re-export lens operators
import "lens" Control.Lens

-- NOTE: Do NOT import "generic-lens" Data.Generics.Labels () here.
-- That orphan IsLabel instance enables generic-lens #label syntax, but
-- re-exporting it from the prelude forces it on every module — which
-- collides with other modules that define their own IsLabel instances
-- (notably the keiki DSL). Import it per-module where #label is used.
```

### Key Points

- **Use `PackageImports`, but only here** — qualify each import with the package name to avoid ambiguity. Enable the extension with a per-file pragma at the top of the prelude module, **not** as a global `default-extension`:

  ```haskell
  {-# LANGUAGE PackageImports #-}
  module Service.Prelude where

  import "base" GHC.Generics as X (Generic)
  ```

  Package-qualified imports exist to disambiguate the re-exports the prelude collects; no other module needs them. Keeping `PackageImports` scoped to this one file (rather than in the cabal `default-extensions`) avoids encouraging package-qualified imports elsewhere in the codebase, where they add noise without benefit.

- **Re-export via `as X`** — the `module X` export in the module header collects everything imported `as X`
- **Export `Control.Lens` directly** — lens operators are used everywhere and benefit from a blanket re-export
- **Do NOT re-export `Data.Generics.Labels`** — it is tempting to enable `#label` syntax once in the prelude, but the orphan `IsLabel` instance it provides then leaks into every module. Any module that needs a *different* `IsLabel` instance — most notably the **keiki DSL**, which overloads `#label` for its own purposes — would then conflict with the generic-lens instance, producing overlapping-instance errors that cannot be resolved locally. Keep the prelude free of it and import it explicitly in the modules that use generic-lens `#label` access. See [Record Patterns](./record-patterns.md) for the per-module pattern.

## Cabal Configuration

Expose the prelude from the core library package:

```haskell
-- service-core.cabal
library
  exposed-modules:
    Service.Prelude
    -- ...other modules

  build-depends:
    , base
    , aeson
    , generic-lens ^>=2.2
    , lens ^>=5.3
    , text
    , time
```

Use GHC2024 and a shared set of default extensions:

```haskell
common common
  default-language: GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
    OverloadedStrings
```

Note that `PackageImports` is deliberately **absent** from `default-extensions`. It is only needed by the prelude module to disambiguate its re-exports, so it is enabled there with a per-file `{-# LANGUAGE PackageImports #-}` pragma rather than turned on project-wide.

## Adding Project-Wide Utilities

The prelude is the right place for small, domain-agnostic definitions that are used across the project:

```haskell
module Service.Prelude
  ( module X
  , module Control.Lens
  , eventAesonOptions
  , TimeZoneId(..)
  )
where

-- ... re-exports ...

-- | Standard Aeson options for event types.
-- Encodes sum types as {"type": "snake_case_tag", "data": {...}}
eventAesonOptions :: Options
eventAesonOptions = defaultOptions
  { sumEncoding = TaggedObject "type" "data"
  , constructorTagModifier = camelTo2 '_'
  , tagSingleConstructors = True
  }

-- | IANA timezone identifier (e.g. "America/Los_Angeles")
newtype TimeZoneId = TimeZoneId { unTimeZoneId :: Text }
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromJSON, ToJSON)
```

### What Belongs Here

- Types used across many modules with no single domain home (e.g. `TimeZoneId`)
- Shared serialization options (e.g. `eventAesonOptions`)
- Small combinators that fill gaps in imported libraries

### What Does NOT Belong Here

- Domain types (put them in their domain module)
- Large utility functions (create a dedicated module)
- Anything with non-trivial dependencies beyond what the prelude already imports

## Usage

Every module in the project imports the prelude instead of individual packages:

```haskell
module Service.Domain.Member.MemberEvent where

import Service.Prelude

data MemberStatusChangedData = MemberStatusChangedData
  { memberId :: !MemberId
  , changedAt :: !UTCTime
  , status :: !MemberStatus
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)
```

No additional imports are needed for `Generic`, `UTCTime`, `Text`, `FromJSON`, `ToJSON`, or lens operators — the prelude provides them all.

The one thing the prelude deliberately does **not** provide is the generic-lens `#label` instance. Modules that use `#label` access over `Generic` records add it themselves:

```haskell
module Service.Domain.Member.MemberDecider where

import Service.Prelude
import "generic-lens" Data.Generics.Labels ()  -- enables #label access
```

This keeps the orphan `IsLabel` instance from leaking into modules that need a different one (e.g. the keiki DSL). See [Record Patterns](./record-patterns.md#enabling-label-syntax) for the rationale.

## Resolving Import Conflicts

Because the prelude re-exports a broad surface, a name it provides will occasionally clash with a name from another import — most often an operator. Two rules keep these conflicts resolvable:

- **Hide the clashing name from the prelude import, never the other way around.** When a prelude re-export collides with a name you need from another module, hide it at the prelude import site:

  ```haskell
  import Service.Prelude hiding ((:=))

  import "some-dsl" Some.DSL ((:=))  -- the (:=) you actually want here
  ```

  The prelude is imported in every module, so it is the predictable place to subtract a name. Hiding it there keeps the conflicting import clean and makes the intent obvious: *this module wants the other `(:=)`*.

- **Never qualify operators.** Operators must always be imported unqualified — never write `M.<>` or `Map.!`. Qualified operator syntax is noisy, and reaching for it to dodge a clash is the wrong fix. Resolve operator conflicts by hiding the unwanted name (from the prelude, per the rule above), not by qualifying. Qualified imports are fine for ordinary identifiers; operators are the exception.
