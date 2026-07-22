# OpenTelemetry Integration for Servant Services

**Every service initializes one tracer provider and one meter provider in brackets in
`main`, creates the WAI middleware only after installing those providers globally, and
passes the same tracer into keiro.** That ordering gives one distributed trace from the
incoming `traceparent`, through the servant handler and keiro command, to the outbox row
and the consuming service.

This standard was verified against the released `hs-opentelemetry` 1.0.0.0 cohort and
the upstream 1.0.0.0 tags on 2026-07-22. Re-check Hackage and the upstream tags before
changing a pin; keep the API, SDK, exporter, propagator, semantic-conventions, and WAI
instrumentation packages on one compatible cohort. Keiro 0.3.0.0 requires
`hs-opentelemetry-api >=1.0 && <1.1`.

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
```

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
import OpenTelemetry.Attributes qualified as Attributes
import OpenTelemetry.Instrumentation.Wai (newOpenTelemetryWaiMiddleware)
import OpenTelemetry.Metric qualified as OTelMetric
import OpenTelemetry.Trace qualified as OTel
import Network.Wai.Handler.Warp qualified as Warp

main :: IO ()
main =
  bracket OTel.initializeGlobalTracerProvider flushAndShutdown $ \provider ->
    bracket
      OTelMetric.initializeGlobalMeterProvider
      (\mp -> void (OTelMetric.shutdownMeterProvider mp Nothing))
      $ \_ -> do
        let tracer = OTel.makeTracer provider instrumentationLibrary OTel.tracerOptions
        otelMiddleware <- newOpenTelemetryWaiMiddleware
        Warp.run 8080 (otelMiddleware (requestLogMiddleware (serviceApp tracer)))
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

HTTP OTLP has two different endpoint contracts in 1.0.0.0:

- `OTEL_EXPORTER_OTLP_ENDPOINT` is a base URL. The exporter appends `/v1/traces`,
  `/v1/metrics`, or `/v1/logs` for the selected signal.
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is a complete per-signal URL and is used as-is.
  For HTTP/protobuf it therefore normally ends in `/v1/traces`.

```text
# CORRECT: generic base URL
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318

# CORRECT: complete per-signal URL
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces

# WRONG: the per-signal value omits the path; no suffix is added
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318
```

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
-- CORRECT: the logger and servant handlers run with the server span attached.
otelMiddleware (requestLogMiddleware (serviceApp tracer))

-- WRONG: request logging runs before a server span exists and cannot correlate.
requestLogMiddleware (otelMiddleware (serviceApp tracer))
```

Set `OTEL_SEMCONV_STABILITY_OPT_IN=http`. The released middleware still defaults to the
legacy HTTP attribute names; `http` selects only stable names such as
`http.request.method`, `url.path`, and `http.response.status_code`. The middleware also
records `http.server.request.duration`, `http.server.active_requests`, and
`http.server.request.count`.

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
