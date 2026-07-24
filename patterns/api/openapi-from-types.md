---
type: Standard
title: "Generating the OpenAPI Document from Servant Types"
description: "Derive OpenAPI 3.1 from Servant route types and enforce the generated artifact in CI"
timestamp: 2026-07-22T12:26:31-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-openapi-from-types
tags: [api, servant, openapi, openapi-3.1, multiverb, code-generation]
status: current
---

# Generating the OpenAPI Document from Servant Types

The rule is one sentence: **the OpenAPI document is derived from the route types by
`toOpenApi`, never written or edited by hand.** A checked-in `openapi.json` is a build
artifact, like an object file. If a human edits it, it is wrong the next time anyone runs
the generator.

This is not merely a tidiness preference. A hand-written specification asserts what the
service *ought* to do; a derived one states what the type system *guarantees* it does. The
first drifts silently the moment someone adds a route. The second cannot.

This document depends on [Servant API Design](./servant-routes.md), which requires that
routes be a `NamedRoutes` record and that each operation's error statuses be declared in
its route type as `MultiVerb` response alternatives. Both feed directly into the document
you generate here.


## Use the OpenAPI 3.1 Packages by Name

Two packages are required, and both are released on Hackage:

- `openapi-hs` — the OpenAPI **3.1** data model (a fork of `openapi3`, which targets 3.0).
- `servant-openapi-hs` — derives the document from a Servant API type and tests handler
  conformance (a fork of `biocad/servant-openapi3`, retargeted at 3.1 via `openapi-hs`).

The load-bearing reason for these package names is not the version bump. It is this:

> The upstream-lineage `openapi3` and `servant-openapi3` packages carry **no `HasOpenApi` instance for
> `MultiVerb`**. `servant-openapi-hs` does.

Consequently, with `openapi3` and `servant-openapi3`, every error response an operation
declares in its route type — the 400, 404, 409, 503 — is **silently absent from the generated document**.
Not a compile error. Not a warning. The document simply describes a service that only ever
succeeds. Since the entire purpose of putting errors in the route type is that they reach
the document and the generated client, using `servant-openapi3` quietly destroys
the benefit while appearing to work.

The former forks are published packages now. Depend on them normally:

```cabal
library
  build-depends:
    , openapi-hs >= 5.0 && < 5.1
    , servant-openapi-hs >= 5.1 && < 5.2
```

Those were the current released versions on 2026-07-22. Treat the two libraries as a
compatibility cohort and re-check Hackage plus the upstream release tags before changing
bounds. In particular, `relay-pagination-servant-0.1.0.0` intentionally requires the
older but coherent `openapi-hs >=4.1 && <4.2` / `servant-openapi-hs >=4.1 && <4.2`
cohort. Let the consuming package's constraints select one coherent pair; do not mix
major/minor cohorts.

Note the module namespaces are unchanged from the upstream packages — you still
`import Data.OpenApi` and `import Servant.OpenApi`. Only the package names differ.

### Keep One Released Cohort

Three ways to get this wrong, all of them seen in the wild.

**Do not depend on the upstream package names.** A `build-depends: openapi3,
servant-openapi3` resolves successfully, but a service using `MultiVerb` is already
missing every declared error response from its document.

**Do not add local filesystem paths.** A `packages:` stanza naming
`/Users/you/src/openapi-hs` builds on one laptop and nowhere else. Use the released
Hackage packages. A `source-repository-package` pin is reserved for an intentional
unreleased fix and must name immutable compatible commits for both packages.

**Do not mix cohorts.** `servant-openapi-hs` targets a bounded `openapi-hs` range.
Different services resolving different cohorts can emit subtly different documents from
equivalent types, and a shared DTO can acquire different schemas. Record the selected
released pair in one place and apply the same bounds across a service.

Check what a repository actually resolves before trusting its document:

```bash
grep -rn "openapi" --include="*.cabal" .   # package names and compatible bounds?
grep -n  "openapi" cabal.project           # unexpected git pins or local paths?
```


## The Generator Module

Put the document in **one module**, in the package that owns the route types. It should be
almost empty. Everything the document contains ought to come from the API type; what is
left over is the handful of facts the types genuinely cannot carry.

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
-- Orphans, deliberate and confined. Concentrating them here -- rather than in the route
-- module -- keeps the OpenAPI dependency out of the route types and limits the orphans to
-- the single call site that resolves them, so there is no incoherence risk.
{-# OPTIONS_GHC -Wno-orphans #-}

module Service.Api.OpenApi (serviceOpenApi) where

import Data.OpenApi (OpenApi, ToParamSchema (..), info, title, version, description, servers)
import Servant.OpenApi (HasOpenApi (..))

-- | Teach the document what a custom combinator means. Without this instance
-- `toOpenApi` will not typecheck at all when every route sits behind the combinator.
instance (HasOpenApi api) => HasOpenApi (AuthProtect "service-jwt" :> api) where
  toOpenApi _ =
    toOpenApi (Proxy @api)
      & (components . securitySchemes .~ SecurityDefinitions (InsOrdHashMap.singleton "service-jwt" bearer))
      & (allOperations . security <>~ [SecurityRequirement (InsOrdHashMap.singleton "service-jwt" [])])
    where
      bearer = SecurityScheme (SecuritySchemeHttp (HttpSchemeBearer (Just "JWT"))) Nothing

-- | Path captures need a parameter schema. A typed id renders as text.
instance ToParamSchema (KindID p) where
  toParamSchema _ = toParamSchema (Proxy @Text)

-- | The document. Note `toOpenApi serviceApi` -- the same Proxy the server serves.
serviceOpenApi :: OpenApi
serviceOpenApi =
  toOpenApi serviceApi
    & info . title .~ "Service API"
    & info . version .~ "0.1.0.0"
    & info . description ?~ "What this service is for."
    & servers .~ ["http://localhost:8080"]
```

Four things belong here and nowhere else.

**A `ToSchema` per DTO.** Usually `instance ToSchema FooRequest` with no body — the generic
default matches the wire JSON, provided the DTO's `ToJSON` uses the same field-label
modifier. The conformance test below enforces that agreement.

**A `ToParamSchema` per captured or queried type.** `Capture`/`QueryParam` types need a
parameter schema even when they already have `FromHttpApiData`.

**A `HasOpenApi` instance per custom combinator.** Servant ships instances for its own
combinators; a project's auth combinator, role guard, or version header is its own to
describe. A phantom combinator (one that does not change the wire) gets a transparent
instance: `toOpenApi _ = toOpenApi (Proxy @sub)`.

**Enrichment the types cannot carry**: title, version, description, server list, and stable
`operationId`s.

### Two Instances You Will Need And Will Not Find

`openapi-hs` ships **no `ToSchema` for aeson's `Value`.** Any DTO carrying an opaque JSON
payload needs one. A bare empty schema is *not* enough — the validator rejects unmentioned
object properties unless `additionalProperties` explicitly permits them:

```haskell
instance ToSchema Value where
  declareNamedSchema _ =
    pure . NamedSchema (Just "AnyValue") $
      mempty & additionalProperties ?~ AdditionalPropertiesAllowed True
```

A DTO with a **hand-written, tagged-union `ToJSON`** needs a hand-written `ToSchema` to
match — generic derivation will not reproduce the custom JSON. Write it as a `oneOf` of
the branch shapes, and let the conformance test hold the two in agreement.

### Stable `operationId`s

Client generators turn `operationId` into a method name. Absent one, they invent something
from the path, and it churns. Assign them deterministically from method and path:

```haskell
withOperationIds :: OpenApi -> OpenApi
withOperationIds = paths %~ imap setForPath
  where
    setForPath path =
      (get . _Just . operationId %~ orSet ("get" <> key))
        . (post . _Just . operationId %~ orSet ("create" <> key))
        . (put . _Just . operationId %~ orSet ("update" <> key))
        . (delete . _Just . operationId %~ orSet ("delete" <> key))
      where key = camel path
    orSet v = Just . maybe v id
```


## Write the Artifact From an Executable

Emit `docs/api/openapi.json` from a **dedicated executable**, not from a test. A test that
writes files is a test with a side effect; it may be skipped, sandboxed, or run in
parallel. An executable is a build step you can invoke deterministically and run in CI.

```cabal
-- Writes docs/api/openapi.json. An executable rather than a test, so the artifact is
-- produced deterministically rather than as a side effect of the suite.
executable service-openapi
  main-is: OpenApi.hs
  hs-source-dirs: app
  build-depends: base, bytestring, aeson-pretty, service-api
```

```haskell
main :: IO ()
main = BSL.writeFile "docs/api/openapi.json" (encodePretty' config serviceOpenApi <> "\n")
  where
    config = defConfig { confIndent = Spaces 2, confCompare = compare }
```

Sort the keys (`confCompare = compare`) and end with a newline. Both make the artifact
diffable, so a reviewer sees the contract change rather than a reshuffle.

**Check the artifact in, and enforce it in CI.** Regenerate and fail on any difference:

```bash
cabal run service-openapi
git diff --exit-code docs/api/openapi.json
```

A red build here means someone changed the API and did not regenerate. That is exactly the
drift the rule exists to catch.


## Test the Document, Not Just the Types

Deriving the document proves it matches the *route types*. Three further properties rot
silently and must be pinned by tests.

**The path set is exactly the served set.** An endpoint added without a thought for its
description should fail, not appear as an undocumented route.

```haskell
testCase "paths list exactly the served operations" $
  assertEqual "paths" servedPaths (sort (InsOrdHashMap.keys (serviceOpenApi ^. paths)))
```

**Every operation declares its error responses.** This is the test that gives the
`MultiVerb` convention its teeth: it fails the moment an endpoint is added without a
response list — and it is the test that would have caught a silent switch to
`servant-openapi3`, where every error response vanishes at once.

```haskell
testCase "every operation declares its error responses" $
  for_ (allOperationsOf serviceOpenApi) $ \op ->
    assertBool "has 4xx/5xx" (any (>= 400) (responseCodesOf op))
```

**Every DTO's `ToJSON` validates against its own `ToSchema`.** A field renamed on one side
only is otherwise invisible until a client's generated code fails to decode.

```haskell
testCase "ToJSON matches ToSchema" $
  case validateToJSON sampleFooRequest of
    [] -> pure ()
    errs -> assertFailure (unlines errs)
```

If the API is authenticated, assert that too — that every operation carries the security
requirement. A route that lost its auth combinator is a security bug, and the document is
where it shows.


## Anti-Patterns to Avoid

### Don't Hand-Write or Hand-Edit `openapi.json`

It is a build artifact. Editing it produces a document that disagrees with the server, and
the disagreement survives exactly until the next `cabal run service-openapi`, at which
point the edit is lost. If the document is wrong, the *types* are wrong. Fix them.

### Don't Use `openapi3` / `servant-openapi3`

They emit OpenAPI 3.0 and, decisively, carry no `HasOpenApi` instance for `MultiVerb`.
Every declared error response disappears from the document with no error and no warning.
Use the released `openapi-hs` / `servant-openapi-hs` compatibility cohort.

### Don't Generate From a Different Type Than You Serve

```haskell
-- WRONG: the document describes a type nobody serves; the two drift silently
serviceOpenApi = toOpenApi (Proxy @ServiceAPI)
app = serve (Proxy @SomeOtherAPI) server

-- WRONG: the server does not go through servant at all
app = \req respond -> case pathInfo req of ...   -- hand-rolled WAI router

-- CORRECT: one Proxy, serving and describing
serviceApi :: Proxy (NamedRoutes ServiceApi)
serviceOpenApi = toOpenApi serviceApi
app = serveWithContext serviceApi ctx (serviceServer env)
```

If the server dispatches by hand on `pathInfo`, the generated document is decorative. It
describes a type that has no necessary relationship to what the service answers.

### Don't Scatter the Orphan Instances

`ToSchema`, `ToParamSchema`, and `HasOpenApi` instances for other people's types are
orphans. Put every one in the generator module, under `-Wno-orphans`. They are resolved
only at the `toOpenApi` call site there, so there is no incoherence risk — and the route
modules stay free of the OpenAPI dependency.

### Don't Write the Document From a Test

A test that writes `docs/api/openapi.json` couples artifact production to suite execution.
Use an executable, and let a test *read* the document and assert properties of it.
