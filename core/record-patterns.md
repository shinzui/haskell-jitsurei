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
    , generic-lens ^>=2.2    -- Automatic lens generation
    , lens ^>=5.3            -- Lens operators
```

**Note**: GHC2024 includes `DataKinds`, `DerivingStrategies`, and `LambdaCase` by default, so they don't need to be listed separately.

### Prelude Setup

Create a custom prelude that re-exports lens functionality:

```haskell
-- src/Service/Prelude.hs
module Service.Prelude
  ( module X
  , module Control.Lens
  )
where

-- Enable #label syntax for Generic records
import "generic-lens" Data.Generics.Labels ()

-- Re-export lens operators
import "lens" Control.Lens

-- Other common re-exports
import Data.Text as X (Text, pack, unpack)
import Data.Time as X (UTCTime, Day)
import GHC.Generics as X (Generic)
import Data.Aeson as X (FromJSON, ToJSON, Value)
```

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
  , tanStatus :: !(Maybe TanStatus)
  }
  deriving stock (Generic, Eq, Show)

setTanStatus :: TanStatus -> MemberStateData -> MemberStateData
setTanStatus status stateData = stateData & #tanStatus ?~ status

-- Example: Set to Banned
banMember :: Text -> MemberStateData -> MemberStateData
banMember reason stateData = stateData & #tanStatus ?~ Banned reason
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
import qualified Data.Set as Set

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
import Service.Domain.Member.MemberCommand
import Service.Domain.Member.MemberEvent
import qualified TanES.Decider as D

type MemberDecider = D.Decider' MemberCommand MemberEvent MemberState

data MemberState
  = InitialState
  | MemberState !MemberStateData
  deriving stock (Generic, Eq, Show)

data MemberStateData = MemberStateData
  { memberSyncData :: !MemberSynchronizationData
  , memberEmail :: !(Maybe MemberEmail)
  , tanStatus :: !(Maybe TanStatus)
  }
  deriving stock (Generic, Eq, Show)

decider :: MemberDecider
decider = D.Decider {decide, evolve, initialState = InitialState, isTerminal = const False}

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
    , tanStatus = Nothing
    }
evolve (MemberState stateData) (MemberStatusChanged d) =
  let updatedSyncData = (stateData ^. #memberSyncData)
        & #synchronizedAt .~ d ^. #changedAt
        & #status .~ d ^. #status
  in MemberState $ stateData & #memberSyncData .~ updatedSyncData
evolve (MemberState stateData) (MemberBanned d) =
  MemberState $ stateData & #tanStatus ?~ Banned (d ^. #reason)
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

Use `defaultAesonOptions` from tan-aeson for consistent JSON:

```haskell
import TanAeson (defaultAesonOptions)

instance FromJSON MemberImportedData where
  parseJSON = genericParseJSON defaultAesonOptions

instance ToJSON MemberImportedData where
  toJSON = genericToJSON defaultAesonOptions
```

### Custom Options for Optional Fields

```haskell
import qualified Data.Aeson as A

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
