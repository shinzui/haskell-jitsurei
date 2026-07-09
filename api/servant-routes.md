# Servant API Design

This document describes how HTTP APIs are defined across the services. Two rules
carry most of the weight:

1. **Define the API as a `NamedRoutes` record**, never as a positional `:<|>` chain.
2. **Make every terminal verb a `MultiVerb`** whose response list declares the
   operation's error statuses, so errors are values in the type rather than
   exceptions thrown past it.

The two are orthogonal — `en` uses `MultiVerb` inside a `:<|>` chain, and `shomei`
uses `NamedRoutes` with plain `Verb`s — but new APIs should use both.

## Required Extensions and Dependencies

```haskell
-- service-api.cabal
common common
  default-language: GHC2024   -- supplies DataKinds
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedStrings

  build-depends:
    , servant         ^>=0.20
    , servant-server  ^>=0.20
```

`TypeOperators` is needed for `:>` and `:-` and is included in GHC2024. A route
module that only defines types needs `DataKinds` and `TypeOperators` and nothing
else.

## Part 1: `NamedRoutes`

### The Shape

An API is a record parameterized by servant's route `mode`. Each field is one
route (or one mounted sub-API), joined to its type with `:-`.

```haskell
import Servant.API
import Servant.API.Generic (type (:-))

data HealthApi mode = HealthApi
  { live :: mode :- Get '[PlainText] Text,
    db :: mode :- "db" :> Get '[JSON] Value
  }
  deriving stock (Generic)
```

The record is instantiated at different `mode`s to get different things: `AsApi`
for a description, `AsServerT m` for a record of handlers, `AsClientT` for a
record of client functions. Serving needs a `Proxy` over `NamedRoutes`:

```haskell
kizashiApi :: Proxy (NamedRoutes KizashiApi)
kizashiApi = Proxy
```

### Why, Beyond Taste

**Positional chains silently misroute.** This is the reason that costs real
outages. In a `:<|>` API, handlers are supplied as a positional chain, and any
two routes with the same *type* are interchangeable — transposing them typechecks,
compiles, serves, and returns the wrong data.

`kansoku`'s `MetricsAPI` is the clean illustration: eleven endpoints, of which nine
share a single `type MetricQuery = ... :> Get '[JSON] MetricResult` alias and differ
only in a path literal.

```haskell
-- kansoku-api/src/Kansoku/Api/Metrics.hs
type MetricsAPI =
       "metrics" :> "page-views"      :> MetricQuery
  :<|> "metrics" :> "sessions"        :> MetricQuery
  :<|> "metrics" :> "acquisition"     :> MetricQuery
  :<|> "metrics" :> "users"           :> MetricQuery
  :<|> "metrics" :> "organizations"   :> MetricQuery
  -- ...
```

Swap the `users` and `organizations` handlers in the corresponding chain and GHC
has nothing to object to. The endpoint serves org metrics under `/metrics/users`.
With a record, the same mistake is a field-name error at the construction site.

**Sub-APIs compose, and can share a path prefix.** A `:<|>` API is one flat chain;
a record can mount other records as fields, and *several fields may mount at the
same prefix*. `kizashi` mounts four different sub-records under `v1/actors`,
each owned by a different module and a different plan:

```haskell
-- kizashi-api/src/Kizashi/Api/Root.hs
data KizashiApi mode = KizashiApi
  { status :: mode :- "service-status" :> Get '[PlainText] Text,
    signals :: mode :- "v1" :> "signals" :> NamedRoutes SignalRoutes,
    actors :: mode :- "v1" :> "actors" :> NamedRoutes ActorRegistryRoutes,
    actorReads :: mode :- "v1" :> "actors" :> NamedRoutes ActorReadRoutes,
    actorContext :: mode :- "v1" :> "actors" :> NamedRoutes ActorContextRoutes,
    actorDigest :: mode :- "v1" :> "actors" :> NamedRoutes ActorDigestRoutes
  }
  deriving stock (Generic)
```

This lets the route tree follow the *module* structure rather than the URL
structure. `mori` does the same, one field per resource family.

**Growth is additive and checked.** Adding a route to a record adds a field, which
breaks the server record construction until a handler exists for it. Adding a
route to a `:<|>` chain in the wrong position silently shifts every handler after
it. Both `kizashi` and `mori` lean on this deliberately — kizashi's `Root.hs`
records the intent in a comment: *"Keep the record shape stable so those additions
are purely additive"*, with each field annotated by the plan that introduced it.

**Unbuilt routes can be reserved.** `mori` parks not-yet-implemented families as
`EmptyAPI` fields, which serve 404 until replaced:

```haskell
    ingest :: mode :- EmptyAPI,   -- EP-132
    openapi :: mode :- EmptyAPI   -- EP-133
```

**The client comes free.** `genericClient` derives a record of client functions
from the same type — no positional destructuring of a `:<|>` client:

```haskell
-- shomei-client/src/Shomei/Client.hs
shomeiClient :: ShomeiAPI (AsClientT ClientM)
shomeiClient = genericClient
```

**Handlers are a named record.** With `AsServerT`, the server is built by field
name, so a reader can see which handler implements which route without counting
positions.

**OpenAPI generation takes the same type.** `toOpenApi (Proxy @(NamedRoutes ShomeiAPI))`
describes exactly the contract the server serves.

### Auth Goes on the Field, Not the Record

Put the auth combinator on the individual routes that need it, so only those
handlers receive the leading auth payload. `shomei` keeps `signup`/`login`/`refresh`
public and marks the rest:

```haskell
data ShomeiAPI mode = ShomeiAPI
  { login ::
      mode :- "auth" :> "login" :> ReqBody '[JSON] LoginRequest
             :> Post '[JSON] (WithCookies LoginResponse),
    passwordChange ::
      mode :- Authenticated :> "auth" :> "password" :> ...
  }
```

If *every* route is authenticated, the combinator still goes on each field rather
than wrapping the record — wrapping it would be uniform but would also apply to any
future public route added to the same record.

### Pitfall: `OverloadedRecordDot` Does Not Work on Route Fields

A `NamedRoutes` field's type is a `(:-)` **type-family application**, which
record-dot's `HasField` cannot see through. Selector application does reduce it.

```haskell
-- WRONG: does not typecheck
shomeiClient.signup body

-- CORRECT: qualified selector application
API.signup shomeiClient body
```

This is worth a comment at the call site; it looks like a record and reads like a
record right up until you try dot syntax on it.

### Where `:<|>` Is Still Correct

Combining top-level APIs — mounting a `NamedRoutes` record alongside other routes
in a host application — is what `:<|>` is for, and there is no misordering hazard
because the alternatives have distinct types:

```haskell
-- shomei-servant/src/Shomei/Servant/API.hs
type AppAPI =
  "auth" :> NamedRoutes ShomeiAPI
    :<|> Authenticated :> "projects" :> Get '[JSON] [Project]
    :<|> RequireRole "admin" :> Authenticated :> "admin" :> "users" :> Get '[JSON] [User]
```

**Rule**: `:<|>` to mount records; never to enumerate the routes inside one.

## Part 2: `MultiVerb`

### The Problem

A handler that signals a 404 by throwing `ServerError` puts that 404 nowhere in
the type. It does not reach the generated OpenAPI document, it does not reach the
generated client's result type, and nothing forces the handler to actually be able
to produce it. The status set becomes a property of an error-mapping function
rather than of the contract.

### The Shape

Declare the operation's responses as a type-level list, and give the handler a
plain sum type that maps onto it.

```haskell
import Servant.API.MultiVerb (AsUnion (..), MultiVerb, Respond, RespondEmpty)

-- | The one error-body shape. `code` is stable and machine-readable; `retryable`
-- distinguishes "fix your request" from "try again".
data ErrorEnvelopeWire = ErrorEnvelopeWire
  { code :: !Text,
    message :: !Text,
    retryable :: !Bool
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)

-- | The shared error tail, parameterized by the success description and payload.
type OkResponses (desc :: Symbol) a =
  '[ Respond 200 desc a,
     Respond 400 "Malformed request" ErrorEnvelopeWire,
     Respond 404 "Not found" ErrorEnvelopeWire,
     Respond 409 "Conflict" ErrorEnvelopeWire,
     Respond 503 "Store unavailable" ErrorEnvelopeWire
   ]

-- | What every handler returns. One constructor per distinct status.
data MeiboResult a
  = MeiboOk a
  | MeiboBadRequest !ErrorEnvelopeWire
  | MeiboNotFound !ErrorEnvelopeWire
  | MeiboConflict !ErrorEnvelopeWire
  | MeiboUnavailable !ErrorEnvelopeWire
  deriving stock (Generic, Eq, Show)
```

Used in a route:

```haskell
  getPrincipal ::
    mode :- Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId
           :> MultiVerb 'GET '[JSON] (OkResponses "The principal" PrincipalView)
                        (MeiboResult PrincipalView)
```

A 204 uses `RespondEmpty` and `a ~ ()`; a 201 differs only in the success status,
so the tail is factored into `OkResponses` / `CreatedResponses` / `NoContentResponses`
aliases sharing one error suffix.

### Write `AsUnion` by Hand

`GenericAsUnion` can derive the mapping. Don't use it. The correspondence between
each constructor and its response alternative is the load-bearing fact of the
design; a new status, or a reordering of the response list, should break loudly at
compile time rather than silently re-map a body onto the wrong status.

```haskell
instance
  AsUnion
    '[ Respond 200 desc a,
       Respond 400 "Malformed request" ErrorEnvelopeWire,
       Respond 404 "Not found" ErrorEnvelopeWire,
       Respond 409 "Conflict" ErrorEnvelopeWire,
       Respond 503 "Store unavailable" ErrorEnvelopeWire
     ]
    (MeiboResult a)
  where
  toUnion = \case
    MeiboOk value -> Z (I value)
    MeiboBadRequest e -> S (Z (I e))
    MeiboNotFound e -> S (S (Z (I e)))
    MeiboConflict e -> S (S (S (Z (I e))))
    MeiboUnavailable e -> S (S (S (S (Z (I e)))))
  fromUnion = \case
    Z (I value) -> MeiboOk value
    S (Z (I e)) -> MeiboBadRequest e
    S (S (Z (I e))) -> MeiboNotFound e
    S (S (S (Z (I e)))) -> MeiboConflict e
    S (S (S (S (Z (I e))))) -> MeiboUnavailable e
    S (S (S (S (S impossible)))) -> case impossible of {}
```

The final clause is the **exhaustiveness witness**: the union has exactly five
positions, so the sixth shift is uninhabited and matches into the empty case. If
the response list grows, that line stops compiling — which is the point.

### Share One Response List, Even If It Is Slightly Over-Broad

Give every operation in a service the same error tail unless there is a reason not
to. `en` shares one list across all six operations even though a write can never
exceed a traversal bound (422), and explains why: the error sum is one closed type,
so the type system cannot prove the write path never yields `ResolutionLimitExceeded`,
and a narrower list would make the fault-to-result conversion partial.

> A total conversion is worth a slightly over-broad document.

The payoff is a single total function from the domain fault type into the result
type:

```haskell
faultToResult :: EnFault -> EnResult a
faultToResult = \case
  BadRequestFault envelope -> EnClientError envelope
  UnprocessableFault envelope -> EnUnprocessable envelope
  UnavailableFault envelope -> EnUnavailable envelope
```

### Choosing Statuses

- **A failed dependency is a 503, not a 500.** If the store is unreachable, *a
  dependency of the service* failed, not the service. Pair it with `retryable = True`;
  it is the only status for which retrying an unchanged request can succeed.
- **`code` is what clients branch on**, never the message prose.

### What `MultiVerb` Cannot Cover

Errors raised *before a handler runs* are not response alternatives, because no
handler ran to return one. These need separate handling to keep the error envelope
consistent:

- **Malformed body, unmatched route** — rejected by servant's routing layer. Supply
  `ErrorFormatters` in the context so they emit the same envelope:

  ```haskell
  app env = serveWithContext apiProxy (envelopeFormatters :. EmptyContext) (server env)
  ```

- **Authentication and rate-limit rejections** — raised by combinators or WAI
  middleware, upstream of the handler.
- **405 Method Not Allowed and 415 Unsupported Media Type** — servant raises these
  *outside* `ErrorFormatters`, so they currently return an empty body. Known gap.

A useful consequence: because a 405 does not consume the request body, `en` moved
tuple deletion from `DELETE` to `POST`.

## Combining Both

The target shape for a new service is a `NamedRoutes` record whose every field is a
`MultiVerb`:

```haskell
data MeiboApi mode = MeiboApi
  { register ::
      mode :- Authenticated :> "v1" :> "principals"
             :> ReqBody '[JSON] RegisterPrincipalRequest
             :> MultiVerb 'POST '[JSON]
                  (CreatedResponses "Principal registered" RegisterPrincipalResponse)
                  (MeiboResult RegisterPrincipalResponse),
    getPrincipal ::
      mode :- Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId
             :> MultiVerb 'GET '[JSON]
                  (OkResponses "The principal" PrincipalView)
                  (MeiboResult PrincipalView)
  }
  deriving stock (Generic)
```

Every route behind the auth combinator, every error status in the type, every
handler reached by name.

## Anti-Patterns to Avoid

### Don't Enumerate Routes with `:<|>`

```haskell
-- WRONG: positional; same-typed neighbours are silently swappable
type QueryRoutes =
       Authenticated :> "v1" :> "principals" :> "by-handle" :> Capture "handle" Text :> Get '[JSON] PrincipalView
  :<|> Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId :> Get '[JSON] PrincipalView

-- CORRECT: named fields
data QueryRoutes mode = QueryRoutes
  { byHandle :: mode :- Authenticated :> "v1" :> "principals" :> "by-handle" :> Capture "handle" Text :> Get '[JSON] PrincipalView,
    getById :: mode :- Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId :> Get '[JSON] PrincipalView
  }
  deriving stock (Generic)
```

### Don't Throw `ServerError` for Domain Errors

```haskell
-- WRONG: the 404 is invisible to the type, the OpenAPI doc, and the client
getPrincipal pid = maybe (throwError err404) pure =<< lookupPrincipal pid

-- CORRECT: the 404 is a response alternative
getPrincipal pid = maybe (MeiboNotFound notFoundEnvelope) MeiboOk <$> lookupPrincipal pid
```

### Don't Derive `AsUnion` with `GenericAsUnion`

It silently re-maps bodies onto statuses when the response list changes. Write the
instance out; let the change break the build.

### Don't Return 500 for a Failed Dependency

```haskell
-- WRONG: says the service is broken
StoreUnavailable -> throwError err500

-- CORRECT: says a dependency is, and that a retry may work
StoreUnavailable -> MeiboUnavailable (ErrorEnvelopeWire "store_unavailable" msg True)
```

### Don't Reach for `OverloadedRecordDot` on a Generated Client

See the pitfall above. Use qualified selector application.

## Adoption Status

As of 2026-07-09:

| Project | Routes | Errors |
|---|---|---|
| shomei | `NamedRoutes` | `Verb` |
| kizashi | `NamedRoutes` | `Verb` |
| kotei | `NamedRoutes` | `Verb` |
| danwa | `NamedRoutes` | `Verb` |
| mori | `NamedRoutes` | `Verb` |
| en | `:<|>` | **`MultiVerb`** |
| kansoku | `:<|>` | `Verb` |
| kawa | `:<|>` | `Verb` |
| meibo | `:<|>` | **`MultiVerb`** |

`nagare` defines no API of its own; it consumes en's and shomei's generated clients.

The `MultiVerb` convention originates in `en-servant/src/En/Servant/API.hs`, which
is the reference implementation. Migration priority for the `:<|>` holdouts is by
misordering exposure: **kansoku** (nine interchangeable handlers), **meibo**
(nineteen routes, four interchangeable), **en** (eleven routes, actively growing),
**kawa** (three routes, all distinct types — low stakes).
