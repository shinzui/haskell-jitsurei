---
type: Pattern
title: "Record Patterns"
description: "Define and manipulate records with Generic Lens and overloaded labels"
timestamp: 2026-07-24T09:59:51-07:00
resource: mori://shinzui/haskell-jitsurei/docs/core-record-patterns
tags: [core, haskell, records, generic-lens, overloaded-labels]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T09:59:51-07:00
    document_timestamp: 2026-07-24T09:59:51-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Record Patterns

This document describes the conventions for defining and manipulating records using Generic Lens with the `#label` syntax.

## Required Extensions and Dependencies

### Cabal Configuration

```haskell
-- service-core.cabal
common common
  default-language: GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields    -- Allows same field names in different records
    OverloadedLabels         -- Enables #fieldName syntax
    OverloadedStrings

  build-depends:
    , generic-lens ^>=2.3    -- Automatic lens generation
    , lens ^>=5.3            -- Lens operators
```

**Note**: GHC2024 includes `DataKinds`, `DerivingStrategies`, and `LambdaCase` by default, so they don't need to be listed separately.

### Prelude Setup

Create a custom prelude that re-exports lens functionality:

```haskell
-- src/Service/Prelude.hs
{-# LANGUAGE PackageImports #-}

module Service.Prelude
  ( module X
  , module Control.Lens
  )
where

-- Re-export lens operators (PackageImports pins the package; see Custom Prelude)
import "lens" Control.Lens

-- Other common re-exports
import "text" Data.Text as X (Text, pack, unpack)
import "time" Data.Time as X (UTCTime, Day)
import "base" GHC.Generics as X (Generic)
import "aeson" Data.Aeson as X (FromJSON, ToJSON, Value)
```

**Important**: The prelude does **not** import `Data.Generics.Labels`. See [Enabling `#label` Syntax](#enabling-label-syntax) below.

## Enabling `#label` Syntax

The `#fieldName` syntax (`OverloadedLabels`) resolves through an `IsLabel`
instance. generic-lens supplies one as an **orphan instance** in
`Data.Generics.Labels`, which turns `#field` into a lens over a `Generic`
record. To use `#label` access in a module you must bring that instance into
scope:

```haskell
module Service.Domain.Member.MemberDecider where

import Service.Prelude
import Data.Generics.Labels ()  -- enables #label here

decide :: MemberCommand -> MemberState -> [MemberEvent]
decide cmd state = ... state ^. #status ...
```

### Import it per-module, not in the prelude

It is tempting to import `Data.Generics.Labels ()` once in the [custom
prelude](./custom-prelude.md) so every module gets `#label` for free. **Do not
do this.** Because `IsLabel` is an orphan instance, re-exporting it from the
prelude forces the generic-lens interpretation of `#label` onto *every* module
in the project.

That breaks any module that needs a **different** `IsLabel` instance — most
notably the **keiki DSL**, which overloads `#label` for its own purposes. With
the generic-lens orphan in scope, keiki's bare-`#name` reads stop resolving:
the orphan shadows keiki's instances during type inference, and keiki's own
documentation records exactly this failure for consumers whose prelude
re-exports generic-lens. The breakage cannot be repaired at the use site.

One more property to know: orphan instances propagate *transitively*. Any
module that (even indirectly) imports a module importing
`Data.Generics.Labels` also sees the instance. The per-module import therefore
limits exposure rather than strictly scoping it — in particular, keep the
import out of modules that only *define* domain types (definition modules
rarely manipulate records), so keiki-facing modules can import the types
without inheriting the orphan.

Keeping the import out of the prelude makes `#label` resolution a local,
per-module decision:

- Modules that manipulate `Generic` records import `Data.Generics.Labels ()`
  and get generic-lens `#label`.
- Modules that use the keiki DSL import the DSL's `IsLabel` instance instead and
  are never exposed to the generic-lens orphan.
- A module that genuinely needs both must reconcile them explicitly, rather than
  inheriting an unwanted instance from the prelude.

**Rule**: import `Data.Generics.Labels ()` in each module that uses `#label`
over `Generic` records. Use a plain (unqualified-by-package) import here —
`PackageImports` is reserved for the [custom prelude](./custom-prelude.md),
where it pins `Control.Lens` to the `lens` package. Per-module label imports do
not need the package pin: `generic-lens` is the only provider of the
`Data.Generics.Labels` module in scope, so a plain `import Data.Generics.Labels ()`
resolves unambiguously.

## Record Definition Conventions

### No Field Prefixes

**Do NOT use field prefixes**. Instead, rely on `DuplicateRecordFields`:

```haskell
-- WRONG: Old-style with prefixes
data Member = Member
  { _memberMemberId :: !MemberId
  , _memberStatus :: !MemberStatus
  , _memberEmail :: !(Maybe Text)
  }

-- CORRECT: No prefixes
data Member = Member
  { memberId :: !MemberId
  , status :: !MemberStatus
  , email :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
```

### Strict Fields

**Always use strict fields** with the `!` annotation:

```haskell
data MemberSynchronizationData = MemberSynchronizationData
  { memberId :: !MemberId            -- Strict
  , memberMlsId :: !MemberMlsId      -- Strict
  , status :: !MemberStatus          -- Strict
  , synchronizedAt :: !UTCTime       -- Strict
  , modificationTimestamp :: !(Maybe UTCTime)  -- Maybe is strict, contents evaluated lazily
  , rawData :: !Value                -- Strict
  }
  deriving stock (Generic, Eq, Show)
```

### Entity ID First

For **events and commands**, the entity ID must be the **first field**:

```haskell
-- Event data: Entity ID first
data MemberStatusChangedData = MemberStatusChangedData
  { memberId :: !MemberId      -- FIRST: Entity ID
  , changedAt :: !UTCTime
  , status :: !MemberStatus
  }
  deriving stock (Generic, Eq, Show)

-- Command data: Entity ID first
data BanMemberData = BanMemberData
  { memberId :: !MemberId      -- FIRST: Entity ID
  , reason :: !Text
  , bannedAt :: !UTCTime
  , bannedBy :: !Text
  }
  deriving stock (Generic, Eq, Show)
```

### Explicit Deriving Strategies

Always use explicit deriving strategies:

```haskell
data Member = Member
  { memberId :: !MemberId
  , status :: !MemberStatus
  }
  deriving stock (Generic, Eq, Show, Data)  -- stock for standard classes
  deriving anyclass (FromJSON, ToJSON)       -- anyclass for type classes with Generic

-- For newtypes, use deriving newtype
newtype MemberId = MemberId { unMemberId :: Text }
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromJSON, ToJSON, Hashable)
```

## Field Access with Generic Lens

### View Operator (`^.`)

Extract a field value:

```haskell
import Service.Prelude
import Data.Generics.Labels ()  -- enables #label access

getMemberStatus :: MemberSynchronizationData -> MemberStatus
getMemberStatus syncData = syncData ^. #status

-- Multiple field access
processMember :: MemberSynchronizationData -> IO ()
processMember d = do
  putStrLn $ "Member ID: " <> show (d ^. #memberId)
  putStrLn $ "Status: " <> show (d ^. #status)
  putStrLn $ "Synced at: " <> show (d ^. #synchronizedAt)
```

### Set Operator (`.~`)

Set a field value (returns new record):

```haskell
updateStatus :: MemberStatus -> MemberSynchronizationData -> MemberSynchronizationData
updateStatus newStatus syncData = syncData & #status .~ newStatus

-- Chained updates with &
updateMultipleFields :: UTCTime -> MemberStatus -> MemberSynchronizationData -> MemberSynchronizationData
updateMultipleFields time newStatus syncData =
  syncData
    & #status .~ newStatus
    & #synchronizedAt .~ time
```

### Maybe Set Operator (`?~`)

Set a `Maybe` field to `Just value`:

```haskell
data MemberStateData = MemberStateData
  { memberSyncData :: !MemberSynchronizationData
  , memberEmail :: !(Maybe Text)
  , banStatus :: !(Maybe BanStatus)
  }
  deriving stock (Generic, Eq, Show)

setBanStatus :: BanStatus -> MemberStateData -> MemberStateData
setBanStatus status stateData = stateData & #banStatus ?~ status

-- Example: Set to Banned
banMember :: Text -> MemberStateData -> MemberStateData
banMember reason stateData = stateData & #banStatus ?~ Banned reason
```

### Over Operator (`%~`)

Apply a function to a field:

```haskell
incrementCounter :: Record -> Record
incrementCounter rec = rec & #counter %~ (+1)

uppercaseName :: Member -> Member
uppercaseName member = member & #name %~ Text.toUpper

-- Append to a list field
addAction :: ActionView -> ViewState -> ViewState
addAction action state = state & #actions %~ (<> [action])
```

## Prefer Lens Over Record Update Syntax

**Always prefer lens operators over Haskell's record update syntax**. Lens operators compose better, are more consistent, and make code easier to read and refactor.

This is more than a style preference. Under `DuplicateRecordFields` (mandatory
per [Core Standards](./standards.md)), bare selector occurrences must be
entirely unambiguous as of GHC 9.4, and a record update is accepted only when
at most one datatype in scope has every field being updated — so selector
access and update syntax stop compiling exactly where the fleet's shared field
names appear. `#label` access resolves through `Generic` and is unaffected.

### Simple Field Updates

```haskell
-- WRONG: Record update syntax
updateStatus :: Status -> Record -> Record
updateStatus newStatus record = record { status = newStatus }

-- CORRECT: Lens setter
updateStatus :: Status -> Record -> Record
updateStatus newStatus record = record & #status .~ newStatus
```

### Multiple Field Updates

```haskell
-- WRONG: Nested record update
updateFields :: UTCTime -> Status -> Record -> Record
updateFields time newStatus record =
  record { status = newStatus, updatedAt = time }

-- CORRECT: Chained lens operations
updateFields :: UTCTime -> Status -> Record -> Record
updateFields time newStatus record =
  record
    & #status .~ newStatus
    & #updatedAt .~ time
```

### Updating Nested Maybe Fields

Use `_Just` to traverse into Maybe values:

```haskell
data ViewState = ViewState
  { intention :: !(Maybe Intention)
  , isCompleted :: !Bool
  }

-- WRONG: Manual Maybe handling with record update
setParent :: IntentionId -> ViewState -> ViewState
setParent parentId state =
  state { intention = fmap (\i -> i { parent = Just parentId }) (intention state) }

-- CORRECT: Lens composition with _Just
setParent :: IntentionId -> ViewState -> ViewState
setParent parentId state =
  state & #intention . _Just . #parent ?~ parentId
```

### Map Operations with `at` and `ix`

Use lens-based Map operations instead of `Map.insert`, `Map.adjust`, etc.:

```haskell
import Data.Map.Strict (Map)

data ViewState = ViewState
  { blockers :: !(Map BlockerId BlockerView)
  }

-- WRONG: Using Map.insert
addBlocker :: BlockerId -> BlockerView -> ViewState -> ViewState
addBlocker bid bv state =
  state { blockers = Map.insert bid bv (blockers state) }

-- CORRECT: Using 'at' lens (for insert/delete)
addBlocker :: BlockerId -> BlockerView -> ViewState -> ViewState
addBlocker bid bv state =
  state & #blockers . at bid ?~ bv

-- WRONG: Using Map.adjust
resolveBlocker :: BlockerId -> UTCTime -> ViewState -> ViewState
resolveBlocker bid time state =
  state { blockers = Map.adjust (\b -> b { resolvedAt = Just time }) bid (blockers state) }

-- CORRECT: Using 'ix' lens (for updating existing keys)
resolveBlocker :: BlockerId -> UTCTime -> ViewState -> ViewState
resolveBlocker bid time state =
  state
    & #blockers . ix bid . #resolvedAt ?~ time
    & #blockers . ix bid . #isResolved .~ True
```

**Note**: `at` returns `Maybe` and is used for insert/delete operations. `ix` only updates if the key exists and silently does nothing otherwise.

### Appending to List Fields

```haskell
-- WRONG: Record update with list append
addOutcome :: OutcomeView -> ViewState -> ViewState
addOutcome ov state =
  state { outcomes = outcomes state <> [ov] }

-- CORRECT: Using %~ with append
addOutcome :: OutcomeView -> ViewState -> ViewState
addOutcome ov state =
  state & #outcomes %~ (<> [ov])
```

### Reading Fields Consistently

When extracting multiple fields from a record, use lens access consistently:

```haskell
-- WRONG: Mixing record access and lens
extractView :: ViewState -> Maybe IntentionView
extractView state = do
  int <- intention state  -- record syntax
  let allBlockers = Map.elems (state ^. #blockers)  -- lens
  ...

-- CORRECT: Consistent lens access
extractView :: ViewState -> Maybe IntentionView
extractView state = do
  int <- state ^. #intention
  let allBlockers = Map.elems (state ^. #blockers)
      active = filter (not . isResolved) allBlockers
  pure IntentionView
    { intention = int
    , actions = state ^. #actions
    , outcomes = state ^. #outcomes
    , blockers = allBlockers
    , activeBlockers = active
    , isCompleted = state ^. #isCompleted
    }
```

## Nested Field Access

### Lens Composition with `.`

Access nested fields by composing lenses:

```haskell
data AppConfig = AppConfig
  { environment :: !Environment
  , streamCategories :: !StreamCategories
  , pool :: !Pool
  }
  deriving stock (Generic)

data StreamCategories = StreamCategories
  { membersStreamCategory :: !CategoryStream
  , propertiesStreamCategory :: !CategoryStream
  }
  deriving stock (Generic)

-- Access nested field
getMembersStream :: AppConfig -> CategoryStream
getMembersStream config = config ^. #streamCategories . #membersStreamCategory

-- Usage in handlers
handleGetMember :: (Reader AppConfig :> es) => MemberId -> Eff es Member
handleGetMember memberId = do
  config <- ask @AppConfig
  let membersStream = config ^. #streamCategories . #membersStreamCategory
  -- ...
```

### Nested Updates

```haskell
-- Update nested field
updateMembersStream :: CategoryStream -> AppConfig -> AppConfig
updateMembersStream newStream config =
  config & #streamCategories . #membersStreamCategory .~ newStream
```

## Functional Composition with `.to`

Apply a pure function after lens access:

```haskell
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Set.Lens (setOf)  -- not re-exported by Control.Lens

data MapLocationAreasData = MapLocationAreasData
  { propertyId :: !PropertyId
  , locationServiceAreaIds :: !(NonEmpty LocationServiceAreaId)
  }
  deriving stock (Generic)

-- Convert NonEmpty to Set
getAreaIdsAsSet :: MapLocationAreasData -> Set LocationServiceAreaId
getAreaIdsAsSet d = d ^. #locationServiceAreaIds . to (Set.fromList . NonEmpty.toList)

-- Using folded for traversable structures
getAllAreaIds :: MapLocationAreasData -> Set LocationServiceAreaId
getAllAreaIds d = d ^. #locationServiceAreaIds . to (setOf folded)
```

## Complete Examples

### Event Record Definition

```haskell
module Service.Domain.Member.MemberEvent where

import Service.Prelude

-- Event ADT
data MemberEvent
  = MemberImported !MemberImportedData
  | MemberStatusChanged !MemberStatusChangedData
  | MemberUpdated !MemberUpdatedData
  | MemberBanned !MemberBannedData
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)

-- Event data records (entity ID first)
data MemberImportedData = MemberImportedData
  { memberId :: !MemberId              -- Entity ID first
  , memberMlsId :: !MemberMlsId
  , status :: !MemberStatus
  , address :: !Address
  , mls :: !Mls
  , importedAt :: !UTCTime
  , modificationTimestamp :: !(Maybe UTCTime)
  , rawData :: !Value
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)

data MemberStatusChangedData = MemberStatusChangedData
  { memberId :: !MemberId              -- Entity ID first
  , changedAt :: !UTCTime
  , status :: !MemberStatus
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)

data MemberBannedData = MemberBannedData
  { memberId :: !MemberId              -- Entity ID first
  , bannedAt :: !UTCTime
  , reason :: !Text
  , bannedBy :: !Text
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)
```

### Decider with Lens Usage

```haskell
module Service.Domain.Member.MemberDecider where

import Service.Prelude
import Data.Generics.Labels ()  -- enables #label access below
import Service.Domain.Member.MemberCommand
import Service.Domain.Member.MemberEvent

data MemberState
  = InitialState
  | MemberState !MemberStateData
  deriving stock (Generic, Eq, Show)

data MemberStateData = MemberStateData
  { memberSyncData :: !MemberSynchronizationData
  , memberEmail :: !(Maybe MemberEmail)
  , banStatus :: !(Maybe BanStatus)
  }
  deriving stock (Generic, Eq, Show)

-- The decide/evolve pair is the shape the event-sourcing runtime consumes
-- (keiro's EventStream); the framework wiring is out of scope here.

-- Using lens in decide function
decide :: MemberCommand -> MemberState -> [MemberEvent]
decide (SyncMember d) = \case
  InitialState -> [MemberImported $ mkMemberImportedData d]
  MemberState stateData -> syncExistingMember d stateData
decide (BanMember d) = \case
  InitialState -> []  -- Can't ban non-existent member
  MemberState stateData ->
    [MemberBanned $ MemberBannedData
      { memberId = d ^. #memberId
      , bannedAt = d ^. #bannedAt
      , reason = d ^. #reason
      , bannedBy = d ^. #bannedBy
      }]

-- Lens-heavy sync logic
syncExistingMember :: MemberSynchronizationData -> MemberStateData -> [MemberEvent]
syncExistingMember d stateData =
  let state = stateData ^. #memberSyncData
      updatedAt = d ^. #synchronizedAt

      -- Compare fields using lens access
      statusChanged = d ^. #status /= state ^. #status
      needsUpdate = d ^. #modificationTimestamp > state ^. #modificationTimestamp

      -- Build events conditionally
      statusEvent = [mkMemberStatusChanged d updatedAt | statusChanged]
      updateEvent = [mkMemberUpdated d updatedAt | needsUpdate && not statusChanged]
  in statusEvent ++ updateEvent

mkMemberStatusChanged :: MemberSynchronizationData -> UTCTime -> MemberEvent
mkMemberStatusChanged d updatedAt = MemberStatusChanged $
  MemberStatusChangedData
    { memberId = d ^. #memberId
    , changedAt = updatedAt
    , status = d ^. #status
    }

-- Using lens in evolve function
evolve :: MemberState -> MemberEvent -> MemberState
evolve s (MemberImported d) = MemberState $
  MemberStateData
    { memberSyncData = mkSyncDataFromImport d
    , memberEmail = Nothing
    , banStatus = Nothing
    }
evolve (MemberState stateData) (MemberStatusChanged d) =
  let updatedSyncData = (stateData ^. #memberSyncData)
        & #synchronizedAt .~ d ^. #changedAt
        & #status .~ d ^. #status
  in MemberState $ stateData & #memberSyncData .~ updatedSyncData
evolve (MemberState stateData) (MemberBanned d) =
  MemberState $ stateData & #banStatus ?~ Banned (d ^. #reason)
evolve s _ = s
```

### Record Construction from Lens Extractions

```haskell
-- Building new record by extracting from source
mkMemberImportedData :: MemberSynchronizationData -> MemberImportedData
mkMemberImportedData d = MemberImportedData
  { memberId = d ^. #memberId
  , memberMlsId = d ^. #memberMlsId
  , status = d ^. #status
  , address = d ^. #address
  , mls = d ^. #mls
  , importedAt = d ^. #synchronizedAt
  , modificationTimestamp = d ^. #modificationTimestamp
  , rawData = d ^. #rawData
  }
```

## JSON Serialization

### Default Aeson Options

Define the project's shared Aeson options once in the [custom
prelude](./custom-prelude.md) — `eventAesonOptions` there is the pattern — and
use them for every serialized type, so the wire format is decided in one place:

```haskell
import Service.Prelude  -- re-exports eventAesonOptions

instance FromJSON MemberImportedData where
  parseJSON = genericParseJSON eventAesonOptions

instance ToJSON MemberImportedData where
  toJSON = genericToJSON eventAesonOptions
```

### Custom Options for Optional Fields

```haskell
import Data.Aeson qualified as A

aesonOptions :: A.Options
aesonOptions = A.defaultOptions
  { A.omitNothingFields = True
  , A.fieldLabelModifier = camelTo2 '_'  -- camelCase to snake_case
  }

instance ToJSON MemberPayload where
  toJSON = A.genericToJSON aesonOptions
```

## Anti-Patterns to Avoid

### Don't Use Field Prefixes

```haskell
-- WRONG
data Member = Member { _memberStatus :: !MemberStatus }

-- CORRECT
data Member = Member { status :: !MemberStatus }
```

### Don't Use Record Syntax for Access

```haskell
-- WRONG: Direct record field access
let s = memberSyncData stateData

-- CORRECT: Use lens
let s = stateData ^. #memberSyncData
```

Pattern matching is not "access" in this sense. Matching a record in a function
head — positionally or with field puns, as the API standards' `SortSpec`
extractors do (`\Member {createdAt} -> createdAt`) — is fine and often
clearest; `DuplicateRecordFields` resolves pun fields by the constructor being
matched. The anti-pattern is selector-function application and update `{}`
syntax, not pattern matches. Record *construction* syntax is likewise fine —
the examples in this document use it throughout.

### Don't Use Record Update Syntax

```haskell
-- WRONG: Record update syntax
let newState = state { status = Active, updatedAt = now }

-- CORRECT: Use lens setters
let newState = state & #status .~ Active & #updatedAt .~ now
```

### Don't Use Map.insert/Map.adjust with Record Updates

```haskell
-- WRONG: Map operations with record update
state { items = Map.insert key value (items state) }

-- CORRECT: Use 'at' lens
state & #items . at key ?~ value
```

### Don't Forget Strictness

```haskell
-- WRONG: Lazy field
data Record = Record { field :: Text }

-- CORRECT: Strict field
data Record = Record { field :: !Text }
```

### Don't Mix Deriving Styles

```haskell
-- WRONG: Mixed implicit and explicit
data Record = Record { field :: !Text }
  deriving (Generic, Show)  -- Missing strategy
  deriving anyclass (ToJSON)

-- CORRECT: All explicit
data Record = Record { field :: !Text }
  deriving stock (Generic, Show)
  deriving anyclass (ToJSON)
```
