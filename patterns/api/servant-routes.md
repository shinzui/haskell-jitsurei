---
type: Standard
title: "Servant API Design"
description: "Organize Servant APIs as vertical NamedRoutes slices with typed MultiVerb responses"
timestamp: 2026-07-24T10:28:01-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-servant-routes
tags: [api, servant, named-routes, multiverb, vertical-slices, errors]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T10:28:01-07:00
    document_timestamp: 2026-07-24T10:28:01-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Servant API Design

This document describes how HTTP APIs are defined across the services. Two rules
carry most of the weight:

1. **Define the API as a `NamedRoutes` record**, never as a positional `:<|>` chain.
2. **Make every terminal verb a `MultiVerb`** whose response list declares the
   operation's error statuses, so errors are values in the type rather than
   exceptions thrown past it. The narrow exemptions — `Raw` routes, streaming,
   and cannot-fail single-status endpoints — are listed under
   [Scope](#scope-which-endpoints-get-multiverb); everything else gets the
   full response list.

The two are orthogonal — `MultiVerb` works inside a `:<|>` chain, and a `NamedRoutes`
record works with plain `Verb`s — but new APIs should use both.

The first rule is not really about servant. It is what allows an API to be split
along [vertical slices](#vertical-slices), one per domain aggregate, rather than
collected into a single `Routes.hs` grouped by layer.

## Required Extensions and Dependencies

```haskell
-- service-api.cabal
common common
  default-language: GHC2024   -- supplies DataKinds
  default-extensions:         -- the fleet baseline from Core Standards
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
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

data BuildInfoApi mode = BuildInfoApi
  { version :: mode :- Get '[PlainText] Text,
    revision :: mode :- "revision" :> Get '[JSON] Value
  }
  deriving stock (Generic)
```

The record is instantiated at different `mode`s to get different things: `AsApi`
for a description, `AsServerT m` for a record of handlers, `AsClientT` for a
record of client functions. Serving needs a `Proxy` over `NamedRoutes`:

```haskell
serviceApi :: Proxy (NamedRoutes ServiceApi)
serviceApi = Proxy
```

### Why, Beyond Taste

**It is what lets the API be split along the domain instead of the layer.** This
is the architectural reason, and it outweighs the rest. See [Vertical Slices](#vertical-slices)
below.

**Positional chains silently misroute.** In a `:<|>` API, handlers are supplied as a
positional chain. Two routes with the same *type* are interchangeable — transposing them
typechecks, compiles, serves, and returns the wrong data — and a route inserted in the
middle of the type shifts every handler after it. The record removes the positional
failure mode, but read the qualification below before treating it as a safety guarantee;
it is weaker than it first appears.

The hazard concentrates wherever several endpoints share a response type — a metrics
API whose endpoints all answer `MetricResult`, or a resource whose reads all answer
one view type:

```haskell
type MetricQuery = QueryParam "from" Day :> Get '[JSON] MetricResult

type MetricsAPI =
       "metrics" :> "page-views"    :> MetricQuery
  :<|> "metrics" :> "sessions"      :> MetricQuery
  :<|> "metrics" :> "users"         :> MetricQuery
  :<|> "metrics" :> "organizations" :> MetricQuery
```

All four alternatives have the same type. Swap the `users` and `organizations`
handlers in the corresponding chain and GHC has nothing to object to: the service
compiles, serves, and returns org metrics under `/metrics/users`.

**Be precise about what the record fixes, because it is easy to overclaim.** A record
does *not* turn a same-typed transposition into a type error. Writing
`users = organizationsHandler, organizations = usersHandler` typechecks, exactly as the
chain did. What the record removes is the *positional* failure mode: you cannot miscount,
and inserting a route in the middle cannot shift every handler after it. The remaining
mistake has to be written out by name, in full view of the reader, rather than fallen
into by arithmetic.

Two consequences follow, and both matter.

Where handler types *differ*, a chain already rejects a transposition — so the record
buys clearer errors (GHC names the offending field) rather than new safety.

Where handler types *coincide*, neither form is checked, and **only a runtime test
closes the gap.** For every set of routes that share a handler type, write a dispatch
test that pins each path to its own handler with a distinguishable response. That test,
not the type system, is what makes a same-typed family safe.

**Sub-APIs compose, and can share a path prefix.** A `:<|>` API is one flat chain;
a record can mount other records as fields, and *several fields may mount at the
same prefix* — each owned by a different module:

```haskell
data ServiceApi mode = ServiceApi
  { -- Cannot-fail, in-process, single-status: exempt from the MultiVerb rule (see Scope).
    status :: mode :- "service-status" :> Get '[PlainText] Text,
    -- Six independently-owned sub-records, all mounted under /v1/actors.
    -- They come from five different slices; none of them knows about the others.
    actors :: mode :- "v1" :> "actors" :> NamedRoutes ActorRegistryRoutes,
    actorReads :: mode :- "v1" :> "actors" :> NamedRoutes ActorReadRoutes,
    actorContext :: mode :- "v1" :> "actors" :> NamedRoutes ActorContextRoutes,
    actorDigest :: mode :- "v1" :> "actors" :> NamedRoutes ActorDigestRoutes,
    channelPrefs :: mode :- "v1" :> "actors" :> NamedRoutes ChannelPrefsRoutes,
    digest :: mode :- "v1" :> "actors" :> NamedRoutes DigestRoutes
  }
  deriving stock (Generic)
```

Under a positional chain those six records would be one interleaved list in one file.
Here each is owned by the slice that implements it, and the URL prefix they happen to
share costs nothing.

This lets the route tree follow the *module* structure rather than the URL
structure.

**Growth is additive and checked.** Adding a route to a record adds a field, which
breaks the server record construction until a handler exists for it — provided the
build treats `-Wmissing-fields` as fatal. A missing field in a record construction
is a *warning* by default; enable `-Werror=missing-fields` (or a blanket `-Werror`)
or this guarantee is only a diagnostic. Adding a route to a `:<|>` chain in the
wrong position silently shifts every handler after it. Keep the record shape stable
and additions stay purely additive.

**Unbuilt routes can be reserved.** Park a not-yet-implemented family as an
`EmptyAPI` field, which serves 404 until replaced:

```haskell
    ingest :: mode :- EmptyAPI,
    openapi :: mode :- EmptyAPI
```

**The client comes free.** `genericClient` derives a record of client functions
from the same type — no positional destructuring of a `:<|>` client:

```haskell
-- The client record, derived from the same type.
serviceClient :: ServiceAPI (AsClientT ClientM)
serviceClient = genericClient
```

**Handlers are a named record.** With `AsServerT`, the server is built by field
name, so a reader can see which handler implements which route without counting
positions.

**OpenAPI generation takes the same type.** `toOpenApi (Proxy @(NamedRoutes ServiceAPI))`
describes exactly the contract the server serves.

### Same-Typed Routes Need a Dispatch Test

Neither a chain nor a record catches a transposition of two routes whose handlers have
the same type. Find those families — routes differing only in a path literal, or in a
capture of the same underlying type — and pin each one with a test that asserts the path
reaches *its own* handler.

The cheapest form gives each handler a distinguishable response and asserts both
directions, so a swap fails two tests rather than none:

```haskell
testCase "by-handle resolves a handle, and only a handle" $ do
  get "/v1/principals/by-handle/alice"   `shouldRespondWith` 200
  get "/v1/principals/by-handle/usr_01x" `shouldRespondWith` 404

testCase "by-credential resolves a subject, and only a subject" $ do
  get "/v1/principals/by-credential/usr_01x" `shouldRespondWith` 200
  get "/v1/principals/by-credential/alice"   `shouldRespondWith` 404
```

Write this test *before* converting a chain to a record. It is the only thing that
protects the conversion, and it is the acceptance criterion that the conversion preserved
behavior.

### Field Order Can Be Load-Bearing: Literals Before Captures

A record does not free you from thinking about sibling order. Servant's router merges
same-kind siblings (literal with literal, capture with capture) but never hoists a
literal above a sibling `Capture` — `Servant.Server.Internal.Router.choice` has no
static-over-capture case. Alternatives are tried in declaration order, moving to the
next one only when the current one fails *recoverably*.

In practice, order matters exactly when the capture's parser accepts the literal. A
typed capture — `Capture "id" PrincipalId` whose `FromHttpApiData` rejects
`by-handle` — fails recoverably and routing backtracks to the literal sibling, so
either order works. A permissive capture declared first swallows a same-arity literal
silently:

```haskell
data Routes mode = Routes
  { byId :: mode :- Capture "id" Text :> Get '[JSON] PrincipalView,  -- tried first
    me :: mode :- "me" :> Get '[JSON] PrincipalView                  -- never reached
  }
  deriving stock (Generic)
```

`GET /me` parses `"me"` as the capture's `Text` and the `me` route is dead. Two rules
follow: declare literal siblings before a same-arity capture, and give captures typed
parsers that cannot accept the literals. The dispatch test above pins the behavior
either way — write it whenever a literal and a capture share a prefix.

### Auth Goes on the Field, Not the Record

Put the auth combinator on the individual routes that need it, so only those
handlers receive the leading auth payload. An auth service keeps `signup`/`login`/`refresh`
public and marks the rest:

```haskell
data ServiceAPI mode = ServiceAPI
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
serviceClient.signup body

-- CORRECT: qualified selector application
API.signup serviceClient body
```

This is worth a comment at the call site; it looks like a record and reads like a
record right up until you try dot syntax on it.

### Where `:<|>` Is Still Correct

Combining top-level APIs — mounting a `NamedRoutes` record alongside other routes
in a host application — is what `:<|>` is for, and there is no misordering hazard
because the alternatives have distinct types:

```haskell
type AppAPI =
  "auth" :> NamedRoutes ServiceAPI
    :<|> Authenticated :> "projects" :> Get '[JSON] [Project]
    :<|> RequireRole "admin" :> Authenticated :> "admin" :> "users" :> Get '[JSON] [User]
```

**Rule**: `:<|>` to mount records; never to enumerate the routes inside one.

## Vertical Slices

**Organize modules by domain aggregate, not by layer.** Everything belonging to one
aggregate — its domain type, aggregate/decider, routes, DTOs, read model, queries,
handler, workers — lives under one module prefix named for the aggregate. The layer
is the *leaf* of the module path, never the root.

```text
-- CORRECT: domain-first. One aggregate's slice, spanning four packages.
service-api/src/Service/Conversation/Api.hs
service-core/src/Service/Conversation/Domain.hs
service-core/src/Service/Conversation/ReadModel.hs
service-core/src/Service/Conversation/Projection.hs
service-server/src/Service/Conversation/Handler.hs
service-workers/src/Service/Conversation/Worker.hs

-- WRONG: layer-first. One aggregate, smeared across seven locations.
service-api/src/Service/Api/Routes.hs        -- every aggregate's routes, one file
service-api/src/Service/Api/Types.hs         -- every aggregate's DTOs, one file
service-core/src/Service/Domain/Conversation.hs
service-core/src/Service/Aggregate/Conversation.hs
service-core/src/Service/Effect/ConversationStore.hs
service-core/src/Service/Postgres/ConversationStore.hs
service-core/src/Service/ReadModel/Row.hs    -- every aggregate's rows, one file
```

The per-concept verticals own their own routes and DTOs. Under the layer-first
layout, adding an aggregate means editing seven shared files, every one of which is
a merge conflict against every other aggregate's work; under the vertical layout it
means adding files nobody else touches.

### Packages Are Layers; Module Trees Are Not

The two are easy to confuse, and conflating them is what makes vertical slicing look
impossible.

**Packages** stay split by layer, because they are *dependency* boundaries — an
`-api` package exists so the generated client can depend on the route types without
dragging in `-core`. That split is load-bearing and stays.

**Module paths inside each package** are domain-first. `Service/Conversation/Api`
lives in `service-api`, `Service/Conversation/Handler` in `service-server`, and they
share a prefix. Adding an aggregate means adding one module to each package it needs,
all under one name. Reading an aggregate means one `grep` for one prefix.

**Rule**: `<Project>/<Aggregate>/<Layer>.hs`, never `<Project>/<Layer>/<Aggregate>.hs`.

### Why `:<|>` Fights This

A `:<|>` API *can* be split into per-domain type aliases, so the obstacle is not
literally that you cannot name a sub-API. It is that the pieces do not stay
independent:

- **The handler chain must mirror the flattened route order.** A domain module that
  owns `ConversationRoutes = A :<|> B` also owns a positional `a :<|> b`. Inserting a
  route into the middle of that slice silently shifts its own handlers, and the root
  composition site has to know each slice's internal arity to assemble the whole.
- **A shared URL prefix forces interleaving.** Two aggregates that both serve under
  `/v1/actors` must be woven into one chain, so the *URL* structure dictates the
  *module* structure. That is precisely the coupling vertical slicing exists to break.

`NamedRoutes` removes both. Each aggregate exports a route record and a matching
handler record; the root names them as fields; and several fields may mount at the
same prefix — as in the six `v1/actors` sub-records above. Each of those records
lives in, and is owned by, its own vertical slice. With a positional chain they
would be one interleaved list in one file, owned by nobody.

The umbrella record then stays thin: a health check and one field per aggregate,
mounting a record the aggregate owns.

```haskell
-- The umbrella record: health, plus one field per aggregate. The probe sub-API
-- is the one prescribed by Kubernetes Health Endpoints, mounted as a record.
data RootApi mode = RootApi
  { health :: mode :- "health" :> NamedRoutes HealthApi,
    conversations :: mode :- "conversations" :> NamedRoutes ConversationsAPI
  }
  deriving stock (Generic)
```

## Part 2: `MultiVerb`

### The Problem

A handler that signals a 404 by throwing `ServerError` puts that 404 nowhere in
the type. It does not reach the generated OpenAPI document, it does not reach the
generated client's result type, and nothing forces the handler to actually be able
to produce it. The status set becomes a property of an error-mapping function
rather than of the contract.

Declaring the statuses in the type is only half of it — the document must be *derived*
from that type for them to surface. See [Generating the OpenAPI Document from Servant
Types](./openapi-from-types.md), and note that Hackage's `servant-openapi3` carries no
`HasOpenApi` instance for `MultiVerb` at all: against those packages a `MultiVerb` API
has no derivable document — `toOpenApi` does not typecheck. The released `openapi-hs` /
`servant-openapi-hs` cohort supplies the instance.

### Scope: Which Endpoints Get MultiVerb

The rule is really about contracts, not the combinator: **every status an operation
can actually answer belongs in its route type.** For a JSON operation that means
`MultiVerb`, and nearly every operation qualifies — any handler that touches the
store or a downstream dependency already owns the 503 arm, and most own a 404 or 422
besides. Do not talk yourself out of the response list because an endpoint "cannot
fail"; check its fault type first.

Three genuine exemptions exist, and each is recorded, not silent:

- **Cannot-fail, in-process, single-status endpoints** — a plain-text build-info or
  service-status route that consults nothing outside the process. A one-alternative
  `MultiVerb` adds machinery without adding contract; a plain `Verb` is correct.
  Exempt the route by name in the errors-declared conformance test of
  [Generating the OpenAPI Document](./openapi-from-types.md).
- **`Raw` routes** — WebSocket upgrades, reverse proxies, embedded static assets. A
  `Raw` route hands the request to a WAI `Application`; it has no response list and
  cannot be a `MultiVerb` alternative.
- **Streaming responses** — `MultiVerb` ships `RespondStreaming`, but servant-client
  currently buffers the whole body when unrendering it. A plain `Stream` verb remains
  the simpler, better-supported choice for an endpoint whose point is the stream.

Paginated list endpoints are not an exemption: their response list is prescribed by
[Relay Pagination](./relay-pagination.md) (200 `Connection`, 400 `RelayPageError`).

None of this loosens Rule 1. `NamedRoutes` is unconditional — it is what vertical
slices hang off — and an exempt route (a plain `Verb`, a `Raw` mount, a `Stream`) is
still a named field on its slice's record.

### The Shape

Declare the operation's responses as a type-level list, and give the handler a
plain sum type that maps onto it.

> **The error body is standardized separately.** The `ErrorEnvelopeWire` in the examples
> below predates the fleet's adoption of RFC 9457 problem details; the wire shape is now
> a problem details document served as `application/problem+json` — see [RFC 9457 Problem
> Details for Error Bodies](./rfc9457-problem-details.md). Everything structural here (the
> response list, the result sum, `AsUnion`, `faultToResult`) applies unchanged; only the
> payload type and the error alternatives' combinator (`RespondAs ProblemJSON` instead of
> `Respond`) differ.

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
data ServiceResult a
  = ServiceOk a
  | ServiceBadRequest !ErrorEnvelopeWire
  | ServiceNotFound !ErrorEnvelopeWire
  | ServiceConflict !ErrorEnvelopeWire
  | ServiceUnavailable !ErrorEnvelopeWire
  deriving stock (Generic, Eq, Show)
```

Used in a route:

```haskell
  getPrincipal ::
    mode :- Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId
           :> MultiVerb 'GET '[JSON] (OkResponses "The principal" PrincipalView)
                        (ServiceResult PrincipalView)
```

A 204 uses `RespondEmpty` and `a ~ ()`; a 201 differs only in the success status,
so the tail is factored into `OkResponses` / `CreatedResponses` / `NoContentResponses`
aliases sharing one error suffix.

Servant also ships `UVerb`, an older multi-status mechanism. Prefer `MultiVerb`:
`UVerb` hangs each status off the payload type through `HasStatus` and cannot vary
description, headers, or content type per alternative, while `MultiVerb` keeps all of
that in the response list and maps it onto a plain domain sum through `AsUnion`.

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
    (ServiceResult a)
  where
  toUnion = \case
    ServiceOk value -> Z (I value)
    ServiceBadRequest e -> S (Z (I e))
    ServiceNotFound e -> S (S (Z (I e)))
    ServiceConflict e -> S (S (S (Z (I e))))
    ServiceUnavailable e -> S (S (S (S (Z (I e)))))
  fromUnion = \case
    Z (I value) -> ServiceOk value
    S (Z (I e)) -> ServiceBadRequest e
    S (S (Z (I e))) -> ServiceNotFound e
    S (S (S (Z (I e)))) -> ServiceConflict e
    S (S (S (S (Z (I e))))) -> ServiceUnavailable e
    S (S (S (S (S impossible)))) -> case impossible of {}
```

The final clause is the **exhaustiveness witness**: the union has exactly five
positions, so the sixth shift is uninhabited and matches into the empty case. If
the response list grows, that line stops compiling — which is the point.

### Share One Response List, Even If It Is Slightly Over-Broad

Give every operation in a service the same error tail unless there is a reason not
to. It is tempting to narrow the list per operation — a write cannot exceed a
read's traversal bound, so why document a 422 on it? Because the domain fault type
is one closed sum: the type system cannot prove the write path never yields
`ResolutionLimitExceeded`, so a narrower list makes the fault-to-result conversion
partial.

**A total conversion is worth a slightly over-broad document.** The payoff is a
single total function from the domain fault type into the result type:

```haskell
faultToResult :: ServiceFault -> ServiceResult a
faultToResult = \case
  BadRequestFault envelope -> ServiceBadRequest envelope
  UnprocessableFault envelope -> ServiceUnprocessable envelope
  UnavailableFault envelope -> ServiceUnavailable envelope
```

### The Tail Spans Two Sources

Not every status in the shared list comes from the domain fault type. A service's engine
error typically covers store and concurrency faults; the 404 and the 400/422 are usually
raised at the *handler edge*, where a lookup returns `Nothing` or a request fails
validation. Both feed the same result sum.

This matters when choosing the fault type to build `faultToResult` over. Pick the engine
error and you will find it has no not-found arm — that is correct, not a defect. Convert
the engine error totally, and construct the edge statuses directly:

```haskell
-- engine faults: total conversion
faultToResult :: ServiceFault -> ServiceResult a
-- edge statuses: constructed where the condition is detected
lookupPrincipal pid >>= maybe (pure (ServiceNotFound envelope)) (pure . ServiceOk)
```

### `MultiVerb` Changes the Generated Client

Adding `MultiVerb` to a route changes what `genericClient` returns for it: callers now
receive the result sum rather than the success payload. For a service whose client is
consumed by other repositories, **this is a breaking change even if no module moves.**

It is easy to miss, because the usual worry about a refactor like this is module paths.
Either accept the break and bump, or fold the union back inside the client's wrapper
functions so downstream signatures are unchanged:

```haskell
-- the wrapper absorbs the union; callers still see Either ClientError X
check :: ClientEnv -> CheckRequest -> IO (Either ClientError CheckResponse)
```

### Choosing Statuses

- **A failed dependency is a 503, not a 500.** If the store is unreachable, *a
  dependency of the service* failed, not the service. Pair it with `retryable = True`;
  it is the only status for which retrying an unchanged request can succeed.
- **A genuine internal fault is still a 500.** The rule above is not a ban on 500. A
  decode failure, a replay failure, an impossible state — these are the service being
  broken, and they belong in the response list as a 500 with `retryable = False`. Omit
  the 500 arm only if the fault type provably has no internal case. Deciding by
  reflex that "500 is wrong" makes `faultToResult` partial, which is the one thing the
  shared list exists to prevent.
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
- **405 Method Not Allowed, 406 Not Acceptable, and 415 Unsupported Media Type** —
  servant raises these *outside* `ErrorFormatters` (in `methodCheck`, `acceptCheck`,
  and the request content-type check respectively), so they return an empty body. No
  hook exists for them.
  (A WAI middleware can rewrite the 405 if the service cares; see the formatters
  section of [RFC 9457 Problem Details](./rfc9457-problem-details.md#before-a-handler-runs).)

One consequence worth knowing: a 405 does not consume the request body. An endpoint
that must read a body is better modelled as a `POST` than a `DELETE`, so a
method mismatch cannot leave an unread body on the wire.

## Combining Both

The target shape for a new service is a `NamedRoutes` record whose every field is a
`MultiVerb`:

```haskell
data PrincipalApi mode = PrincipalApi
  { register ::
      mode :- Authenticated :> "v1" :> "principals"
             :> ReqBody '[JSON] RegisterPrincipalRequest
             :> MultiVerb 'POST '[JSON]
                  (CreatedResponses "Principal registered" RegisterPrincipalResponse)
                  (ServiceResult RegisterPrincipalResponse),
    getPrincipal ::
      mode :- Authenticated :> "v1" :> "principals" :> Capture "id" PrincipalId
             :> MultiVerb 'GET '[JSON]
                  (OkResponses "The principal" PrincipalView)
                  (ServiceResult PrincipalView)
  }
  deriving stock (Generic)
```

Every route behind the auth combinator, every error status in the type, every
handler reached by name.

## Anti-Patterns to Avoid

### Don't Enumerate Routes with `:<|>`

```haskell
-- WRONG: positional. Handlers are supplied by counting, and a route inserted in the
-- middle silently shifts every handler after it.
type QueryRoutes =
       Authenticated :> "v1" :> "principals" :> "by-handle" :> Capture "handle" Text :> Get '[JSON] PrincipalView
  :<|> Authenticated :> "v1" :> "principals" :> "by-credential" :> Capture "sub" Text :> Get '[JSON] PrincipalView

-- CORRECT: named fields. The two routes below still share a handler type
-- (AuthUser -> Text -> Handler PrincipalView), so swapping them STILL COMPILES.
-- A dispatch test is what catches that; see "Same-Typed Routes Need a Dispatch Test".
data QueryRoutes mode = QueryRoutes
  { byHandle :: mode :- Authenticated :> "v1" :> "principals" :> "by-handle" :> Capture "handle" Text :> Get '[JSON] PrincipalView,
    byCredential :: mode :- Authenticated :> "v1" :> "principals" :> "by-credential" :> Capture "sub" Text :> Get '[JSON] PrincipalView
  }
  deriving stock (Generic)
```

### Don't Group Modules by Layer

```text
-- WRONG: one Routes.hs and one Types.hs for every aggregate in the service
Service/Api/Routes.hs
Service/Api/Types.hs
Service/Domain/Principal.hs

-- CORRECT: the aggregate owns its routes, DTOs, and domain type
Service/Principal/Api.hs
Service/Principal/Domain.hs
Service/Principal/ReadModel.hs
```

A single `Routes.hs` holding every endpoint is the symptom; the positional `:<|>`
chain is what makes it the path of least resistance.

### Don't Throw `ServerError` for Domain Errors

```haskell
-- WRONG: the 404 is invisible to the type, the OpenAPI doc, and the client
getPrincipal pid = maybe (throwError err404) pure =<< lookupPrincipal pid

-- CORRECT: the 404 is a response alternative
getPrincipal pid = maybe (ServiceNotFound notFoundEnvelope) ServiceOk <$> lookupPrincipal pid
```

### Don't Derive `AsUnion` with `GenericAsUnion`

It silently re-maps bodies onto statuses when the response list changes. Write the
instance out; let the change break the build.

### Don't Return 500 for a Failed Dependency

```haskell
-- WRONG: says the service is broken
StoreUnavailable -> throwError err500

-- CORRECT: says a dependency is, and that a retry may work
StoreUnavailable -> ServiceUnavailable (ErrorEnvelopeWire "store_unavailable" msg True)
```

The converse is equally wrong. Do not force a genuine internal fault into a 503 to
satisfy the rule above — a decode failure is not retryable, and mislabelling it tells
the caller to hammer a request that can never succeed.

```haskell
-- WRONG: not retryable, and no dependency failed
HydrationDecodeFailed e -> ServiceUnavailable (ErrorEnvelopeWire "decode_failed" msg True)

-- CORRECT
HydrationDecodeFailed e -> ServiceInternal (ErrorEnvelopeWire "decode_failed" msg False)
```

### Don't Reach for `OverloadedRecordDot` on a Generated Client

See the pitfall above. Use qualified selector application.

## Related Patterns

- [Generating the OpenAPI Document from Servant Types](./openapi-from-types.md)
- [RFC 9457 Problem Details for Error Bodies](./rfc9457-problem-details.md)
- [OpenTelemetry Integration](./opentelemetry-integration.md)
- [Production Request Logging](./request-logging.md)
- [Relay Pagination](./relay-pagination.md)
- [Kubernetes Health Endpoints](./health-endpoints.md)
