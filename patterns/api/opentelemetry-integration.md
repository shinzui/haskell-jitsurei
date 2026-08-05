---
type: Standard
title: "OpenTelemetry Integration for Servant Services"
description: "Wire one OpenTelemetry SDK lifecycle through WAI, Servant route naming, Keiro, and the outbox"
timestamp: 2026-08-05T07:02:52-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-opentelemetry-integration
tags: [api, servant, opentelemetry, tracing, metrics, wai, keiro, http-route]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T07:39:31-07:00
    document_timestamp: 2026-07-24T07:39:31-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# OpenTelemetry Integration for Servant Services

**Every service initializes one tracer provider and one meter provider in brackets in
`main`, creates the WAI middleware only after installing those providers globally, adds
the Servant instrumentation middleware directly inside it, and passes the same tracer
into keiro.** That ordering gives one distributed trace from the incoming `traceparent`,
through the servant handler and keiro command, to the outbox row and the consuming
service, with every server span named by its Servant route rather than by its HTTP
method alone.

This standard was verified against the released `hs-opentelemetry` 1.0.0.0 cohort and
the upstream 1.0.0.0 tags on 2026-07-22. Re-check Hackage and the upstream tags before
changing a pin; keep the API, SDK, exporter, propagator, semantic-conventions, and WAI
instrumentation packages on one compatible cohort. Keiro 0.3.0.0 requires
`hs-opentelemetry-api >=1.0 && <1.1`. The Servant instrumentation is versioned
independently of the cohort and comes from a fork; it was verified on 2026-08-05 by
building it and running its test suite against that cohort with GHC 9.10.3 and servant
0.20.3.0. See [Name Spans by Servant Route](#name-spans-by-servant-route), the one place
in this standard that depends on a fork rather than a released package.

## Build the Executable for the SDK

The SDK's batch span processor requires the threaded runtime. Put `-threaded` on every
executable that initializes a tracer provider; the requirement is observable at runtime,
not merely an optimization.

```cabal
executable service-server
  ghc-options: -threaded -rtsopts -with-rtsopts=-N
  build-depends:
      hs-opentelemetry-api ==1.0.*
    , hs-opentelemetry-sdk ==1.0.*
    , hs-opentelemetry-exporter-otlp ==1.0.*
    , hs-opentelemetry-instrumentation-wai ==1.0.*
    , hs-opentelemetry-instrumentation-servant ==0.3.*
```

`hs-opentelemetry-instrumentation-servant` is versioned independently of the cohort, is
not on Hackage, and must come from our fork; [Name Spans by Servant
Route](#name-spans-by-servant-route) has the `cabal.project` pin and the reasons.

Without `-threaded`, provider initialization fails with:

```text
The hs-opentelemetry batch processor does not work without the -threaded GHC flag!
```

## Own the Provider Lifetimes in `main`

`OpenTelemetry.Trace.initializeGlobalTracerProvider` reads environment configuration,
creates a `TracerProvider`, installs its propagators, and installs it as the process-global
provider. `OpenTelemetry.Metric.initializeGlobalMeterProvider` does the same for metrics.
Create `newOpenTelemetryWaiMiddleware` only after both global installs: its 1.0.0.0
implementation reads both providers and builds the HTTP instruments at construction time.

```haskell
import Control.Exception (bracket)
import Control.Monad (void)
import Data.Proxy (Proxy (..))
import OpenTelemetry.Attributes qualified as Attributes
import OpenTelemetry.Instrumentation.Servant (openTelemetryServantMiddleware)
import OpenTelemetry.Instrumentation.Wai (newOpenTelemetryWaiMiddleware)
import OpenTelemetry.Metric qualified as OTelMetric
import OpenTelemetry.Trace qualified as OTel
import Network.Wai.Handler.Warp qualified as Warp
import Servant.API.NamedRoutes (NamedRoutes)

serviceApi :: Proxy (NamedRoutes ServiceApi)
serviceApi = Proxy

main :: IO ()
main =
  bracket OTel.initializeGlobalTracerProvider flushAndShutdown $ \provider ->
    bracket
      OTelMetric.initializeGlobalMeterProvider
      (\mp -> void (OTelMetric.shutdownMeterProvider mp Nothing))
      $ \_ -> do
        let tracer = OTel.makeTracer provider instrumentationLibrary OTel.tracerOptions
        otelMiddleware <- newOpenTelemetryWaiMiddleware
        Warp.run 8080 $
          otelMiddleware $
            openTelemetryServantMiddleware provider serviceApi $
              requestLogMiddleware defaultRequestLogPredicate (serviceApp tracer)
  where
    flushAndShutdown provider =
      void (OTel.forceFlushTracerProvider provider Nothing)
        *> void (OTel.shutdownTracerProvider provider Nothing)

instrumentationLibrary :: OTel.InstrumentationLibrary
instrumentationLibrary =
  OTel.InstrumentationLibrary
    { OTel.libraryName = "service-name",
      OTel.libraryVersion = "0.1.0.0",
      OTel.librarySchemaUrl = "",
      OTel.libraryAttributes = Attributes.emptyAttributes
    }
```

Use a bracket even for short-lived workers and CLIs. `forceFlushTracerProvider` followed
by `shutdownTracerProvider` gives buffered spans a chance to leave before process exit;
the meter-provider shutdown stops and flushes its periodic reader. Never initialize a
provider per request.

`HospitalCapacity.Telemetry.withTelemetry` in
`services/hospital-capacity/src/HospitalCapacity/Telemetry.hs` of
`keiro-runtime-jitsurei` is the fleet reference for this lifetime, including an explicit
enabled/disabled mode and temporary `OTEL_SERVICE_NAME` setup. That application is
worker-shaped and has no HTTP server, so copy its provider lifetime but add the WAI step
shown above.

## Configure Telemetry Outside the Binary

The SDK and exporter are environment-first. Deployment configuration, not Haskell code,
chooses the service identity, sampler, collector, and protocol.

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: conversation-service
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: deployment.environment.name=production,service.namespace=keiro
  - name: OTEL_TRACES_SAMPLER
    value: parentbased_traceidratio
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.10"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: http/protobuf
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://otel-collector.observability:4318
  - name: OTEL_SEMCONV_STABILITY_OPT_IN
    value: http
```

`OTEL_SDK_DISABLED=true` selects no-op providers. A service-specific feature flag may
choose whether to initialize telemetry at all, but `OTEL_SDK_DISABLED` wins when both are
present, as `HospitalCapacity.Telemetry.telemetryConfigFromEnvironment` demonstrates.

Configure the endpoint through the base variable only. The OTLP specification says a
per-signal variable such as `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is a complete URL used
as-is, but the released 1.0.0.0 HTTP exporters do not implement that: the span exporter
appends `/v1/traces` to whichever variable it reads, and the metric and log exporters
append their suffix unless the URL already contains `/v1/`. A spec-shaped traces value
ending in `/v1/traces` therefore posts to `/v1/traces/v1/traces` and exports nothing.

```text
# CORRECT: base URL; the exporter appends /v1/traces, /v1/metrics, /v1/logs
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318

# WRONG in 1.0.0.0: the trace exporter appends /v1/traces again
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces
```

Avoid the per-signal variables in this cohort, and re-verify the appending behavior
against the exporter source before trusting them after an upgrade.

## Put the OpenTelemetry Middleware Outermost

`OpenTelemetry.Instrumentation.Wai` 1.0.0.0 exports:

```haskell
newOpenTelemetryWaiMiddleware :: IO Middleware
newOpenTelemetryWaiMiddleware' :: TracerProvider -> Meter -> IO Middleware
requestContext :: Request -> Maybe Context
```

Use the first constructor after global initialization. Use the primed form only when an
embedding host deliberately owns explicit providers. The middleware extracts W3C context
from the incoming headers, creates a `Server` span, attaches its context for the request,
places that context in the request vault for `requestContext`, injects context into the
response headers, records the stable HTTP metrics, and marks 5xx spans as errors. Its
attach/detach bracket prevents Warp keep-alive threads from leaking one request's context
into the next.

Middleware composition is outside-in, so the tracing wrapper must be leftmost:

```haskell
-- CORRECT: the route instrumentation, the logger, and the servant handlers all
-- run with the server span attached.
otelMiddleware
  (openTelemetryServantMiddleware provider serviceApi
    (requestLogMiddleware defaultRequestLogPredicate (serviceApp tracer)))

-- WRONG: request logging runs before a server span exists and cannot correlate.
requestLogMiddleware defaultRequestLogPredicate (otelMiddleware (serviceApp tracer))

-- WRONG: no server span exists yet, so the route instrumentation cannot find one
-- to annotate and opens a redundant span of its own instead.
openTelemetryServantMiddleware provider serviceApi (otelMiddleware (serviceApp tracer))
```

Set `OTEL_SEMCONV_STABILITY_OPT_IN=http`. The released middleware still defaults to the
legacy HTTP attribute names; `http` selects only stable names such as
`http.request.method`, `url.path`, and `http.response.status_code`. The middleware also
records `http.server.request.duration`, `http.server.active_requests`, and
`http.server.request.count`.

## Name Spans by Servant Route

**Every Servant service adds `openTelemetryServantMiddleware` from
`hs-opentelemetry-instrumentation-servant` directly inside the WAI middleware.** Without
it a service produces no route dimension at all, in traces or in metrics.

The WAI middleware cannot know the route. It sees the concrete path
`/widgets/9f2c1b/items/17`, not the template `widgets/:widgetId/items/:itemId`, so
1.0.0.0 opens the server span under the bare request method — `spanName_ = method_`.
Every span in the service is therefore named `GET`, `POST`, or `DELETE`. When the
response is produced it re-reads the span's own attributes and, *only if something else
has already set `http.route`*, renames the span to `<METHOD> <route>` and copies the
route onto `http.server.request.duration` and `http.server.request.count`. The Servant
middleware is what sets that attribute. Skip it and per-endpoint latency, per-endpoint
error rate, and the collector's `spanmetrics` connector all have nothing to group by.

### Pin the Fork

**Depend on `mori://shinzui/hs-opentelemetry-instrumentation-servant`, not on upstream.**
Upstream 0.3.0.0 does not compile against a fleet-shaped API and does not admit this
standard's OpenTelemetry cohort; the fork fixes both and nothing else.

The package is not published to Hackage in either form — only `v0.1.0.0`, `v0.2.0.0`,
and `v0.2.1.0` were ever tagged upstream, and 0.3.0.0 exists only as a commit. So pin a
commit. The `.cabal` file is at the repository root, so no `subdir` is needed.

```cabal
source-repository-package
  type: git
  location: https://github.com/shinzui/hs-opentelemetry-instrumentation-servant.git
  tag: 5e99a7857032484abc669076704dee4335e7d0ad
```

That commit is the tip of `feat/multiverb-authprotect-and-api-1.0`, two commits ahead of
upstream `04141b2b`:

- `HasEndpoint` instances for `MultiVerb` and `AuthProtect`. Upstream's instance list
  reaches `Verb`, `NoContentVerb`, `UVerb`, `Stream`, `Raw`, and `BasicAuth` and stops
  there, so an API written to [Servant API Design](./servant-routes.md) — `NamedRoutes`
  records of `MultiVerb` endpoints, auth combinators on the fields that need them —
  fails to compile at the `openTelemetryServantMiddleware` call site. Not a missing
  attribute: a type error.
- `hs-opentelemetry-api >=0.3 && <1.1`, replacing upstream's `==0.3.*`. **No
  `allow-newer` is needed.** The library needed no source change for 1.0.0.0; it uses
  only `OpenTelemetry.Context.lookupSpan`,
  `OpenTelemetry.Instrumentation.Wai.requestContext`, and the
  `OpenTelemetry.Trace.Core` surface, all unchanged in that release — including the
  `HashMap`-valued `SpanArguments.attributes` field the library builds by hand.

Both are upstreamable as-is and the branch is kept PR-ready; the fork exists because we
could not wait, not because we intend to diverge. Every gap it fixes, and the two it
deliberately does not, are recorded in the corpus project's
`mori/upstream-issues.dhall`. Re-check that catalog before upgrading the pin.

Pass the same `Proxy` you pass to `serve`/`serveWithContext`. If the umbrella record
mounts the service under a prefix, the proxy must carry that prefix too, or nothing
matches and no route is ever recorded.

### Know What It Emits

Attach the middleware and a request to `/widgets/9f2c1b` produces a span named
`GET widgets/:widgetId` carrying:

| Attribute | Value | Note |
| --- | --- | --- |
| `http.route` | `widgets/:widgetId` | stable semantic convention |
| `http.method` | `GET` | legacy name, emitted unconditionally |
| `http.framework` | `servant` | not a semantic convention |

Three consequences are worth knowing before dashboards are written against this data.

The route format is servant-shaped: `:name` placeholders and **no leading slash**, so the
span name the WAI layer builds is `GET widgets/:widgetId` rather than the
`GET /widgets/{widgetId}` form most backend documentation shows. This is conformant —
the `http.route` convention requires only low cardinality with static segments preserved
and dynamic ones replaced, and explicitly permits custom route formatting provided the
instrumentation documents it (this section is that documentation). But it does mean
queries, dashboards, and alert rules must match what is actually emitted.

`http.method` is the **legacy** attribute name. Under
`OTEL_SEMCONV_STABILITY_OPT_IN=http` the WAI middleware emits only stable names, but
this middleware adds the legacy one regardless, so spans carry both `http.request.method`
and `http.method`. Harmless duplication; build queries on `http.request.method`.

When no route matches, `getEndpoint` returns `Nothing`, the middleware passes the request
straight through, and the span keeps its method-only name with no `http.route`. That is
the correct outcome — unrouted paths from scanners never become span names — but it means
404s are indistinguishable from each other in trace search.

The middleware does not mark 5xx spans as errors; its source still carries a `TODO` for
that. Nothing is lost, because the WAI middleware already sets span status `Error` and
the `error.type` attribute on 5xx, and it is outside.

### Guard the `Raw` Fallback

`HasEndpoint Raw` matches **unconditionally** — it inspects neither the remaining path
segments nor the method. Any `Raw` alternative that matching actually reaches therefore
claims the request, every alternative declared after it goes unconsulted, and the result
is `http.route = ""` and a span named `GET ` with a trailing space.

Mount `Raw` behind a path literal and declare it last. `"static" :> Raw` recovers the
literal, so the route is `static` for every asset beneath it — bounded cardinality, which
is what you want from a static mount anyway. A bare root-level `Raw` used as an SPA
fallback is the case to avoid: it collapses the routes declared after it into the empty
route.

The fork deliberately leaves this alone. The unconditional match mirrors servant's own
routing, where a `Raw` alternative likewise consumes everything reaching it, so only the
empty route string is clearly wrong. Convention costs nothing here; a patch would need a
judgement call about what an empty route should become. If a service ever genuinely needs
a bare root-level `Raw`, reopen it — that is the trigger recorded against
`hs-opentelemetry-instrumentation-servant-raw-empty-route` in the corpus catalog.

## Pass the Same Tracer into Keiro

Create one application tracer and thread the same value into every runtime surface.
`Keiro.Command.RunCommandOptions` has `tracer :: Maybe Tracer`; all helpers in
`Keiro.Telemetry`, including `withCommandSpan`, `withProducerSpan`, `withConsumerSpan`,
and `withWorkflowSpan`, are pass-throughs under `Nothing`.

```haskell
commandOptionsWithTelemetry :: Maybe OTel.Tracer -> RunCommandOptions
commandOptionsWithTelemetry tracer =
  defaultRunCommandOptions {Command.tracer = tracer}
```

The complete fleet example is
`services/hospital-capacity/src/HospitalCapacity/Store.hs` in
`keiro-runtime-jitsurei`; its worker receives the tracer from `withTelemetry` and uses
that helper for command, workflow, and outbox options. Obtain the global meter provider
once and build `KeiroMetrics` with `Keiro.Telemetry.newKeiroMetrics` in the same place.

A servant handler runs on the request thread while the WAI context is attached. A keiro
command span opened there automatically becomes a child of the HTTP server span—do not
parse or reattach `traceparent` inside each handler.

## Continue Context Across the Outbox

Keiro carries W3C context through its integration boundary. `Keiro.Telemetry` exposes
`traceContextFromCurrentSpan`, `traceContextFromHeaders`, and `injectTraceContext`;
integration-event envelopes carry `traceContext`, and outbox/inbox persistence stores the
`traceparent` and `tracestate` values. The producer and consumer helpers then continue the
trace on the other side of the broker.

The end-to-end invariant is:

```text
incoming traceparent
  -> WAI Server span
  -> keiro command/workflow span
  -> outbox trace context
  -> broker message
  -> consumer span in the receiving service
```

Test that relationship with one uniquely identified trace through a real command and
consumer. A green `/health/live` endpoint proves only that the process answers; it does
not prove telemetry continuity.

## Related Patterns

- [Servant API Design](./servant-routes.md)
- [Production Request Logging](./request-logging.md)
- [Kubernetes Health Endpoints](./health-endpoints.md)
