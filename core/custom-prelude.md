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

-- Enable #label syntax for Generic records
import "generic-lens" Data.Generics.Labels ()

-- Re-export lens operators
import "lens" Control.Lens
```

### Key Points

- **Use `PackageImports`** — qualify each import with the package name to avoid ambiguity:

  ```haskell
  {-# LANGUAGE PackageImports #-}
  import "base" GHC.Generics as X (Generic)
  ```

- **Re-export via `as X`** — the `module X` export in the module header collects everything imported `as X`
- **Import `Data.Generics.Labels ()`** — this orphan instance import enables the `#label` syntax; importing it here means no module needs to remember it
- **Export `Control.Lens` directly** — lens operators are used everywhere and benefit from a blanket re-export

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

No additional imports are needed for `Generic`, `UTCTime`, `Text`, `FromJSON`, `ToJSON`, lens operators, or `#label` syntax — the prelude provides them all.
