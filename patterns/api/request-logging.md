---
type: Standard
title: "Production Request Logging"
description: "Emit bounded structured WAI request logs with trace correlation and strict data minimization"
timestamp: 2026-08-05T05:39:05-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-request-logging
tags: [api, wai, logging, opentelemetry, security, observability]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T15:48:14-07:00
    document_timestamp: 2026-07-24T15:48:14-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Production Request Logging

**`logStdoutDev` is for local development; a production service emits one bounded JSON
line per included request, carries the trace and span IDs that served it, and never logs
bodies, credentials, or the raw query string.** Put this logger inside the OpenTelemetry
WAI middleware and outside the servant application.

The implementation below was compiled and exercised against
`hs-opentelemetry-{api,instrumentation-wai,sdk}` 1.0.0.0 on 2026-07-22. Re-check the
released cohort before changing dependency bounds.

## Do Not Promote wai-extra's JSON Formatter

`wai-extra` supplies `logStdoutDev`, `mkRequestLogger`, and
`Network.Wai.Middleware.RequestLogger.JSON.formatAsJSON`. They are useful development
tools, but the JSON formatter's released source has the wrong production security
boundary:

- it concatenates and logs the complete request body;
- it logs 4xx and 5xx response bodies;
- it logs every request header while redacting only `Cookie`;
- its header-aware response variant redacts only `Set-Cookie`;
- it includes the full parsed query string;
- it has no OpenTelemetry correlation; and
- its own Haddock says the JSON representation is not a stable API.

An `Authorization` header, reset token in a query parameter, or identifier echoed in a
problem-details body therefore reaches logs unchanged. Configuration around
`formatAsJSON` cannot repair its body-capture-shaped callback contract.

The hs-opentelemetry co-log, katip, and monad-logger instrumentation packages are the
right bridges for application log records and automatic OTel Logs correlation. They do
not emit a per-request access record. Keep application logging and request logging as two
separate concerns.

## Vendor This Small Middleware

The logger deliberately uses only `wai`, `aeson`, `time`, `bytestring`, and the public
OpenTelemetry API. Keep it in the service's server package until the fleet has a real
shared package; do not invent a utility package around one unproven copy.

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Service.Server.RequestLog
  ( requestLogMiddleware,
    defaultRequestLogPredicate,
  )
where

import Control.Monad (when)
import Data.Aeson (encode, object, (.=))
import Data.Aeson.Types (Pair)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LBS
import Data.Text.Encoding qualified as Text
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Clock (getCurrentTime)
import GHC.Clock (getMonotonicTimeNSec)
import Network.HTTP.Types (hUserAgent, statusCode)
import Network.Wai
  ( Middleware,
    Request,
    rawPathInfo,
    requestHeaders,
    requestMethod,
    responseStatus,
  )
import OpenTelemetry.Context (lookupSpan)
import OpenTelemetry.Instrumentation.Wai (requestContext)
import OpenTelemetry.Trace.Core
  ( SpanContext (spanId, traceId),
    getSpanContext,
  )
import OpenTelemetry.Trace.Id
  ( Base (Base16),
    spanIdBaseEncodedText,
    traceIdBaseEncodedText,
  )
import System.IO (stdout)

requestLogMiddleware :: (Request -> Bool) -> Middleware
requestLogMiddleware include app request respond = do
  started <- getMonotonicTimeNSec
  app request $ \response -> do
    finished <- getMonotonicTimeNSec
    when (include request) $ do
      now <- getCurrentTime
      correlation <- correlationFields request
      let durationMs = fromIntegral (finished - started) / 1_000_000 :: Double
          fields =
            [ "time" .= now,
              "method" .= decode (requestMethod request),
              "path" .= decode (rawPathInfo request),
              "status" .= statusCode (responseStatus response),
              "duration_ms" .= durationMs,
              "user_agent" .= fmap decode (lookup hUserAgent (requestHeaders request))
            ]
              <> correlation
          -- Render first, then make one Handle operation. The Handle lock keeps
          -- concurrent requests from interleaving bytes within this process.
          line = LBS.toStrict (encode (object fields)) <> "\n"
      ByteString.hPutStr stdout line
    respond response
  where
    decode = Text.decodeUtf8With lenientDecode

correlationFields :: Request -> IO [Pair]
correlationFields request =
  case requestContext request >>= lookupSpan of
    Nothing -> pure []
    Just span' -> do
      context <- getSpanContext span'
      pure
        [ "trace_id" .= traceIdBaseEncodedText Base16 (traceId context),
          "span_id" .= spanIdBaseEncodedText Base16 (spanId context)
        ]

defaultRequestLogPredicate :: Request -> Bool
defaultRequestLogPredicate request =
  rawPathInfo request /= "/health/live"
    && rawPathInfo request /= "/health/ready"
```

A service that mounts its probes from `servant-health` (per [Kubernetes Health
Endpoints](./health-endpoints.md)) should build this predicate from
`Servant.Health.Paths.healthRawPaths` instead of restating the literals, so the
exclusion cannot drift from the actual routes.

The `respond` continuation observes the actual response status without consuming the
response body. If an application deliberately allows exceptions to escape past servant,
put one exception-to-response boundary between this logger and the servant application:
`otelMiddleware (requestLogMiddleware include (exceptionBoundary servantApp))`. The
access logger should observe the standard 500 response rather than invent a second error
renderer.

## Compose It Under the Server Span

`requestContext` reads the context that
`OpenTelemetry.Instrumentation.Wai.newOpenTelemetryWaiMiddleware` stored in the request
vault. It is available only inside that middleware.

```haskell
-- CORRECT: access record sees the server span.
otelMiddleware (requestLogMiddleware defaultRequestLogPredicate servantApp)

-- WRONG: no WAI span exists when the logger runs.
requestLogMiddleware defaultRequestLogPredicate (otelMiddleware servantApp)
```

A Servant service also runs `openTelemetryServantMiddleware` between the two, so the
full stack is `otelMiddleware (openTelemetryServantMiddleware provider api
(requestLogMiddleware ... servantApp))`. That layer only annotates the existing span, so
it changes nothing this logger reads; see [OpenTelemetry
Integration](./opentelemetry-integration.md) for its pin and required instances.

With an incoming header:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

the request line carries the same trace ID and the server's child span ID:

```json
{"duration_ms":0,"method":"GET","path":"/hello","span_id":"10a3e37aac7ffcd5","status":200,"time":"2026-07-22T19:11:41.355741Z","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","user_agent":"curl/8.20.0"}
```

A request without `traceparent` receives a fresh trace ID when the SDK is recording. If
telemetry is disabled or sampling drops a root span before it has a usable context, omit
the correlation fields rather than writing fake zero IDs.

## Keep the Field Set Bounded

The required fields are:

- `time`: UTC ISO-8601 timestamp at response time;
- `method`: HTTP method;
- `path`: `rawPathInfo`, without the query string;
- `status`: numeric HTTP status;
- `duration_ms`: monotonic elapsed time;
- `trace_id` and `span_id`: lowercase Base16 when present; and
- `user_agent`: the only header allowed by default.

Never read or log request bodies. Never capture response bodies. Never log
`Authorization`, `Cookie`, `Set-Cookie`, or arbitrary headers. Never log the raw query
string by default: credentials and one-time tokens routinely arrive there despite API
rules. If an endpoint needs one query value for operations, add that named field after a
security review and normalize it to a bounded value.

Do not add unbounded high-cardinality values such as full error messages, request bodies,
or arbitrary customer labels to the access record. Put diagnostic details in structured
application logs correlated by `trace_id`.

## Exclude Probe Noise Deliberately

Kubernetes can call liveness and readiness endpoints every few seconds per pod. Exclude
the exact `/health/live` and `/health/ready` paths by predicate, as above. Keep probe
failures observable through metrics, Kubernetes events, and the structured probe response;
turning every successful probe into an access line only hides real traffic.

Other exclusions require a recorded reason. In particular, do not exclude authenticated
application endpoints merely because their traffic volume is high.

## Migration Rule

`danwa-server/src/Danwa/Server/Boot.hs` currently demonstrates the development-only
shape:

```haskell
-- WRONG for production
app = logStdoutDev (serveWithContext api context server)
```

Replace it with the tracing middleware outside this bounded logger. Delete the
`wai-extra` dependency if the service no longer uses it elsewhere; the production
standard does not require `wai-extra`.

## Related Patterns

- [OpenTelemetry Integration for Servant Services](./opentelemetry-integration.md)
- [Servant API Design](./servant-routes.md)
- [Kubernetes Health Endpoints](./health-endpoints.md)
