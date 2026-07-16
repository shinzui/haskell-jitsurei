# RFC 7807 Problem Details for Error Bodies

Every error body every service returns is an **RFC 7807 problem details** document, served
as `application/problem+json`. This document defines the shape, the two ways to integrate
it with servant (typed `MultiVerb` responses for new APIs, `ServerError` rendering for
throw-based ones), what to convert beyond the handlers, and where the convention
deliberately stops.

This is the third document in the API family. [Servant API Design](./servant-routes.md)
covers *which statuses* an operation declares and how (`MultiVerb`, the shared response
list, `faultToResult`); [Generating the OpenAPI Document](./openapi-from-types.md) covers
how the declared contract reaches a machine-readable document. This one covers the *error
body itself*: its members, its media type, and its rendering. The `ErrorEnvelopeWire`
shape that appears in the older documents' examples predates this convention; the problem
document below supersedes it as the wire shape, and everything else in those documents
(response lists, `AsUnion`, status choice, conformance tests) applies unchanged.

A note on the name: RFC 7807 was renumbered **RFC 9457** with an identical wire format.
We say "RFC 7807" because that is the name the services standardized on; if you are
reading the spec, read 9457.

Reference implementations: **shomei** (`shomei-servant/src/Shomei/Servant/Error.hs`) is
the shipped `ServerError`-style adopter, including the formatters, the middleware, and
the catalog pattern; **kotei** (ExecPlan 46 in the kotei repository) is the `MultiVerb`-
style adoption, including the `RespondAs` mechanics verified against the servant 0.20
source.

## Why a Standard Shape

A bespoke envelope — `{"error": msg}`, `{"code", "message"}` — costs nothing inside one
service and compounds across a fleet: every client grows one decoder per service, every
gateway and log pipeline grows one parser per service, and no off-the-shelf tooling
understands any of them. RFC 7807 is the IETF's answer, and HTTP tooling increasingly
speaks it natively. The payoff of adopting it fleet-wide is exactly one client-side
decoder for every service's failures — and the media type `application/problem+json`
makes an error response self-describing even out of context, in a HAR file or a log line.

## The Wire Shape

A problem document is a JSON object. Four members come from the RFC; services add two
extension members (the RFC explicitly permits extensions):

```json
{
  "type": "about:blank",
  "title": "Not found",
  "status": 404,
  "detail": "no run run_7f3a2b",
  "code": "not_found",
  "retryable": false
}
```

- **`type`** — a URI identifying the error *kind*. Always `"about:blank"` (the RFC's
  "no particular type" value) until a service actually hosts error-documentation URLs.
  Do not invent URIs that resolve to nothing.
- **`title`** — a short human phrase for the error kind. **Stable per `code`**: the same
  code always carries the same title, so documentation catalogs and dashboards can key on
  it. Request-specific text never goes here.
- **`status`** — a number mirroring the HTTP status line. Redundant on a direct response,
  load-bearing the moment the body is separated from its response (logs, queues, batch
  reports).
- **`detail`** — the request-specific prose: the parse message, the offending id, the
  role name that did not exist. This is where the old envelope's `message` goes.
- **`code`** *(extension)* — the stable, machine-readable, `snake_case` key. **This is
  what clients branch on** — never `title` or `detail` prose. When migrating a service
  from a pre-7807 envelope, carry the old codes forward verbatim so a client that
  switched on the old key ports by reading `code` instead (shomei did exactly this).
- **`retryable`** *(extension)* — `True` only when retrying the *unchanged* request can
  succeed, which in practice means the 503 "a dependency is down" case. The
  500-versus-503 discipline is in [Servant API Design — Choosing
  Statuses](./servant-routes.md#choosing-statuses) and applies unchanged.

**The media type is part of the contract.** RFC 7807 §3 assigns
`application/problem+json`, and every problem response must carry it in `Content-Type` —
a problem body under plain `application/json` is the shape without the self-description,
and generic tooling will not recognize it.

**Never leak internals through `detail`, and never let the shape disclose what the
status should not.** Failures that are security-equivalent must be indistinguishable:
shomei collapses wrong-password, unknown-account, and locked-account into one generic
`401 invalid_login`, and its invalid-token problems deliberately do not say whether the
token was expired, forged, or malformed. The problem document makes errors *clearer*;
do not let that clarity extend to account enumeration.

## The Haskell Type

`type` is a Haskell reserved word, so the record field is `problemType` and one shared
aeson `Options` value renames it on the wire. Everything hangs off that single value: the
`ToJSON`, the `FromJSON`, and (see below) the `ToSchema`, so the codec and the schema
cannot disagree.

```haskell
-- | An RFC 7807 problem document. problemType is rendered as the RFC's
-- "type" member (a Haskell reserved word) and is always "about:blank".
data ProblemDetails = ProblemDetails
  { problemType :: !Text,
    title :: !Text,
    status :: !Int,
    detail :: !Text,
    code :: !Text,
    retryable :: !Bool
  }
  deriving stock (Generic, Eq, Show)

-- | The single field mapping shared by the JSON codec and the ToSchema.
problemJsonOptions :: Options
problemJsonOptions =
  defaultOptions
    { fieldLabelModifier = \case
        "problemType" -> "type"
        other -> other
    }

instance ToJSON ProblemDetails where
  toJSON = genericToJSON problemJsonOptions

instance FromJSON ProblemDetails where
  parseJSON = genericParseJSON problemJsonOptions
```

Pin the rename with a unit test — encode a value, assert the object's keys are exactly
`type`, `title`, `status`, `detail`, `code`, `retryable` — so a later "cleanup" to plain
generic derivation cannot silently ship `problemType` onto the wire.

If a service makes `detail` optional (shomei omits it when there is nothing
request-specific to say), use `Maybe Text` with `omitNothingFields = True` in the same
shared `Options`. A service whose errors always carry prose keeps it total.

## Style 1: `MultiVerb` — the Media Type in the Route

For an API following [Servant API Design](./servant-routes.md), errors are response
alternatives, and the problem media type belongs *in the response list*. Stock `servant`
0.20 ships the combinator for exactly this: `RespondAs responseContentType status desc a`
hardcodes that one response's Content-Type regardless of the verb's content-type list.
Server-side it requires only `MimeRender ct a`
(`Servant.Server.Internal.ResponseRender`), client-side only `MimeUnrender ct a`
(`Servant.Client.Core.MultiVerb.ResponseUnrender`). No fork is involved.

Define the content type once, next to `ProblemDetails`:

```haskell
import Network.HTTP.Media ((//))   -- package: http-media (servant already depends on it)

-- | The application/problem+json content type (RFC 7807 §3).
data ProblemJSON

instance Accept ProblemJSON where
  contentType _ = "application" // "problem+json"

instance (ToJSON a) => MimeRender ProblemJSON a where
  mimeRender _ = encode

instance (FromJSON a) => MimeUnrender ProblemJSON a where
  mimeUnrender _ = eitherDecode
```

and use it in the shared error tail, so successes stay plain `application/json` while
every error carries the RFC media type:

```haskell
type OkResponses (desc :: Symbol) a =
  '[ Respond 200 desc a,
     RespondAs ProblemJSON 400 "Bad request" ProblemDetails,
     RespondAs ProblemJSON 404 "Not found" ProblemDetails,
     RespondAs ProblemJSON 409 "Conflict" ProblemDetails,
     RespondAs ProblemJSON 503 "Store unavailable" ProblemDetails
   ]
```

Everything else — the result sum, the hand-written `AsUnion` with its exhaustiveness
witness, the total `faultToResult` — is unchanged from [Servant API
Design](./servant-routes.md#part-2-multiverb); only the alternative's combinator and
payload type differ. `faultToResult` builds the document with `title` stable per `code`,
`status` mirroring the status the response list assigns that constructor, and the
request-specific prose in `detail`.

## Style 2: `ServerError` — Rendering at the Throw Site

An existing API that signals errors by throwing `ServerError` adopts the shape without
adopting `MultiVerb`: keep the throw, change what is thrown. This is shomei's style, and
its two load-bearing ideas are worth copying even into a future `MultiVerb` migration.

**One rendering function.** Every thrown error passes through a single function that
attaches the problem body *and* the media type — the Content-Type header is the piece a
hand-rolled `err404 { errBody = … }` always forgets:

```haskell
problemError :: ServerError -> Text -> Text -> Text -> Bool -> ServerError
problemError base title' code' detail' retryable' =
  base
    { errBody =
        encode
          ProblemDetails
            { problemType = "about:blank",
              title = title',
              status = base.errHTTPCode,
              detail = detail',
              code = code',
              retryable = retryable'
            },
      errHeaders = [("Content-Type", "application/problem+json")]
    }
```

**A catalog of specs, as values.** Shomei defines a `ProblemSpec` constant per error kind
(code + base status + stable title) and a `problemCatalog :: [ProblemSpec]` listing all of
them. The runtime mapping renders from the specs, and the OpenAPI error documentation is
generated from the same list — so the status and title the server sends are *literally*
the ones the document promises, and a conformance test asserts every documented code
appears in the catalog. Any service with more than a handful of error kinds should use
this pattern; a service with four wire faults can inline them in `faultToResult`.

Status-specific headers ride along in the same place: a 401 problem carries
`WWW-Authenticate: Bearer` (RFC 6750 §3), a 429 carries `Retry-After`.

## Before a Handler Runs

Handlers are not the only thing that answers requests. Two more surfaces must speak the
same shape, or the service has two error dialects again:

**Servant's own rejections.** An unparseable JSON body, a malformed query param or
header, an unmatched route — servant invents plain-text bodies for all of these.
`ErrorFormatters` (supplied via a servant `Context`; `serveWithContext`, or
`genericServeTWithContext` for a `NamedRoutes` server) has exactly four hooks —
body-parse, URL-parse, header-parse, and not-found — and each should render through the
same `problemError`:

```haskell
serviceErrorFormatters :: ErrorFormatters
serviceErrorFormatters =
  defaultErrorFormatters
    { bodyParserErrorFormatter = \_ _ msg ->
        problemError err400 "Bad request" "body_parse_error" (Text.pack msg) False,
      urlParseErrorFormatter = \_ _ msg ->
        problemError err400 "Bad request" "bad_request" (Text.pack msg) False,
      headerParseErrorFormatter = \_ _ msg ->
        problemError err400 "Bad request" "bad_request" (Text.pack msg) False,
      notFoundErrorFormatter = \_ ->
        problemError err404 "Not found" "not_found" "resource not found" False
    }
```

**405 is not reachable from `ErrorFormatters`.** A method mismatch raises a hardcoded
empty `err405` inside `Servant.Server.Internal.methodCheck` — none of the four hooks see
it. Shomei converts it with a WAI middleware (`Shomei.Servant.Middleware`) that rewrites
empty-bodied 405s into problem documents; a service may instead accept the empty 405 as a
documented limitation (kotei does — a 405 on its surface is a misconfigured client, not a
contract answer). Decide explicitly and record which; do not discover it in production.

**Combinator and middleware rejections.** Auth combinators and rate limiters answer
upstream of the handler too. Whatever raises the 401/403/429 must render through the same
function — in shomei the auth handler's rejections and the rate-limit middleware both
build their `ServerError` via the catalog.

## Where "Applicable" Ends

RFC 7807 is for *errors on JSON APIs*. Three exemptions recur, and each should be a
recorded decision rather than an accident:

- **Protocol-mandated shapes win.** OAuth2's token endpoint must answer RFC 6749 §5.2's
  `{"error": "invalid_grant", …}` — OAuth clients require it. A problem document there
  would be standards-compliant and interoperable with nothing.
- **Status reports are not errors.** A readiness probe answering 503 with a structured
  probe body (which dependency is down, since when) is reporting status, not failing;
  keep the informative body.
- **Non-JSON surfaces stay plain.** A `PlainText` health check and a streaming endpoint
  carry no JSON error tail; exempt them by name in the conformance tests rather than
  bending them into shape.

## The OpenAPI Document

Everything in [Generating the OpenAPI Document](./openapi-from-types.md) applies; RFC
7807 adds three specifics.

**The schema shares the codec's `Options`.** `ProblemDetails` is the one DTO whose
generic `ToSchema` would be wrong — its instance must bridge the same `Options` the codec
uses:

```haskell
instance ToSchema ProblemDetails where
  declareNamedSchema = genericDeclareNamedSchema (fromAesonOptions problemJsonOptions)
```

The `validateToJSON` conformance test then proves codec and schema agree, same as for any
DTO.

**The media type reaches the document for free.** The pinned `servant-openapi-hs` fork
has `IsSwaggerResponse (RespondAs (ct :: Type) s desc a)` requiring `Accept ct`, so a
`RespondAs ProblemJSON …` alternative appears in the document with its content keyed by
`application/problem+json`.

**Pin it in the conformance test.** Extend the "every operation declares its error
responses" test to also assert each error response's `content` is keyed by
`application/problem+json` — that is the assertion that catches a route quietly written
with `Respond … ProblemDetails` instead of `RespondAs ProblemJSON …`, which would serve
the right body under the wrong media type.

## Anti-Patterns to Avoid

### Don't Serve a Problem Body as `application/json`

The media type is the self-description. In `MultiVerb` style use `RespondAs ProblemJSON`,
never plain `Respond`, for the error alternatives; in `ServerError` style always set the
header — which is why a single `problemError` function exists.

### Don't Put Request-Specific Text in `title`

```json
// WRONG: title varies per request; catalogs and dashboards cannot key on it
{"title": "Role admin-ops is not defined", "code": "role_not_defined", ...}

// CORRECT: stable title, variable part in detail
{"title": "Role not defined", "detail": "admin-ops", "code": "role_not_defined", ...}
```

### Don't Branch on `title` or `detail`

`code` is the machine key. Titles are for humans and may be reworded; details vary per
request. A client switching on prose breaks on the next copy edit.

### Don't Invent `type` URIs You Don't Host

`"about:blank"` is not a placeholder to apologize for; it is the RFC's own value for "no
documentation URL exists". A made-up `https://service.example/errors/not-found` that 404s
is worse than no URI: it looks like documentation and resolves to nothing. Mint real
`type` URIs only when the service actually serves error documentation there.

### Don't Keep a Bespoke Envelope Alongside

One service answering `{"error": …}` on one path and problem documents on another has two
dialects — worse than one bad one. Adoption means converting the fallback paths too:
whatever `toServerError`-style mapping remains, the `ErrorFormatters`, and any middleware
that writes error bodies.

### Don't Let Security Distinctions Reach the Wire

Wrong password, unknown user, and locked account are one `code` with one `title`. If two
failures must be indistinguishable to an attacker, they must share a problem document
verbatim — same code, same title, no telltale `detail`.

### Don't Rename the Old Codes While Reshaping

The move to RFC 7807 changes the envelope; it must not simultaneously change the
vocabulary. Carry existing `code` strings forward so client migration is "read `code`
instead of `error`", not a re-mapping exercise. Rename codes, if ever, as their own
change with their own deprecation story.
