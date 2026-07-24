---
type: Standard
title: "Kubernetes Health Endpoints"
description: "Separate in-process liveness from dependency-aware readiness in Servant services"
timestamp: 2026-07-24T10:28:01-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-health-endpoints
tags: [api, servant, kubernetes, health, liveness, readiness]
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

# Kubernetes Health Endpoints

**Every service serves `/health/live` (is the process alive) and `/health/ready`
(should it receive traffic); liveness never checks dependencies, while readiness checks
exactly the dependencies whose failure this pod's restart cannot fix.**

These endpoints have different consequences. Treating them as two spellings of the same
check turns a recoverable dependency outage into an orchestrator-induced incident.

## Liveness: Can This Process Respond?

A failed liveness probe tells Kubernetes to restart the container. The check must
therefore stay in-process and answer only whether the process is responsive. Give it a
short timeout so a deadlocked or starved process fails, but do not make it depend on
PostgreSQL, Kafka, DNS, or another service.

```haskell
-- WRONG: a database outage now restarts every otherwise healthy service pod.
liveCheck = postgresPing store
```

The useful precedent is
`kiroku-metrics/src/Kiroku/Metrics/Health.hs`. Its `checkLiveness` asks whether
`snapshotMetrics` can read the in-process metrics state within `livenessTimeoutUs`.
That proves the process and collector can still make progress without turning an
external failure into a restart storm.

## Readiness: Can This Pod Serve Its Traffic?

A failed readiness probe removes the pod from Kubernetes service endpoints without
restarting it. Check the resources that must work for an incoming request to succeed:

- ping the service's database through its real pool;
- for an event-sourced service, require every subscription to remain below its
  configured lag threshold; and
- fail when a subscription stopped because its bounded buffer overflowed.

Kiroku supplies concrete prior art in the same module. `postgresPing` issues `SELECT 1`
through the store pool. `checkReadiness` rejects an overflow-stopped subscription, a
subscription whose lag exceeds `readinessMaxLag`, or a configured dependency check that
reports unhealthy. `kiroku-metrics/src/Kiroku/Metrics/Config.hs` defaults
`readinessMaxLag` to 10,000 events, the Kiroku analogue of Marten's `maxEventLag`.
`kiroku-metrics/src/Kiroku/Metrics/Server.hs` exposes the resulting `/health`,
`/health/live`, and `/health/ready` routes with 200/503 status selection.

Do not add downstream HTTP services or Kafka brokers merely because the process calls
them. A downstream readiness dependency can cascade one service's outage across the
fleet. The transactional outbox is specifically the buffer for broker outages; making
Kafka a readiness condition defeats that boundary. Add a dependency only when this pod
cannot serve its contracted request semantics while that dependency is unavailable.

## Declare Both Outcomes in the Route Type

Mount a `HealthApi` record under `"health"` on the service's umbrella `NamedRoutes`
record. Both operations return a small status report: 200 when the check passes, or 503
with the failing check and the time it began failing. A probe report describes current
system state; it is not an RFC 9457 error document. Exempt these named routes from the
problem-details conformance test.

Use the same explicit `MultiVerb` result mapping prescribed for application routes. The
following excerpt includes the route, the injected check seam, and the readiness
handler; the liveness handler is identical except for the supplied check.

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

import Data.Aeson (FromJSON, ToJSON)
import Data.SOP (I (..), NS (S, Z))
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Servant.API (JSON, NamedRoutes, StdMethod (GET), (:>))
import Servant.API.Generic ((:-))
import Servant.API.MultiVerb (AsUnion (..), MultiVerb, Respond)
import Servant.Server.Generic (AsServerT)

data ProbeStatus = ProbeStatus
  { status :: !Text,
    check :: !Text,
    failingSince :: !(Maybe UTCTime)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromJSON, ToJSON)

type ProbeResponses =
  '[ Respond 200 "Probe passed" ProbeStatus,
     Respond 503 "Probe failed" ProbeStatus
   ]

data ProbeResult
  = ProbePassed !ProbeStatus
  | ProbeFailed !ProbeStatus

instance AsUnion ProbeResponses ProbeResult where
  toUnion = \case
    ProbePassed body -> Z (I body)
    ProbeFailed body -> S (Z (I body))
  fromUnion = \case
    Z (I body) -> ProbePassed body
    S (Z (I body)) -> ProbeFailed body
    S (S impossible) -> case impossible of {}

data HealthApi mode = HealthApi
  { live :: mode :- "live" :> MultiVerb 'GET '[JSON] ProbeResponses ProbeResult,
    ready :: mode :- "ready" :> MultiVerb 'GET '[JSON] ProbeResponses ProbeResult
  }
  deriving stock (Generic)

data ServiceApi mode = ServiceApi
  { health :: mode :- "health" :> NamedRoutes HealthApi
    -- application routes follow
  }
  deriving stock (Generic)

data ProbeVerdict
  = Healthy
  | Unhealthy {failedCheck :: !Text, since :: !UTCTime}

type ProbeCheck = IO ProbeVerdict

healthServer :: ProbeCheck -> ProbeCheck -> HealthApi (AsServerT IO)
healthServer liveCheck readyCheck =
  HealthApi
    { live = runProbe liveCheck,
      ready = runProbe readyCheck
    }

runProbe :: ProbeCheck -> IO ProbeResult
runProbe checkAction =
  checkAction >>= \case
    Healthy ->
      pure (ProbePassed (ProbeStatus "ok" "all" Nothing))
    Unhealthy failed since ->
      pure (ProbeFailed (ProbeStatus "failed" failed (Just since)))
```

Inject the two `IO` checks at the server boundary. Tests can then force passing and
failing verdicts and assert both the status and body without a real database or a
stalled subscription. The production readiness action may compose `postgresPing`, lag,
and overflow checks; the liveness action must remain in-process.

Exclude `/health/live` and `/health/ready` from the production request logger's path
predicate. Kubernetes already records probe results, and logging every successful probe
obscures real request traffic. See [Production Request Logging](./request-logging.md).

## Configure Kubernetes for the Two Semantics

```yaml
containers:
  - name: service
    ports:
      - name: http
        containerPort: 8080
    livenessProbe:
      httpGet:
        path: /health/live
        port: http
      periodSeconds: 10
      timeoutSeconds: 2
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /health/ready
        port: http
      periodSeconds: 5
      timeoutSeconds: 2
      failureThreshold: 2
```

Prefer a `startupProbe` for services with a genuinely long or variable boot. If the
platform does not provide one, set `initialDelaySeconds` from measured startup time;
do not inflate liveness thresholds to disguise startup behavior.

Probes are the runtime gate. Configuration is a rollout gate: the settei configuration
and Kubernetes operational standard requires a check-config command to parse and
validate the complete deployment configuration before a rollout proceeds. A pod should
not need to become live merely to reveal that its configuration is invalid.

## Related Patterns

- [Servant Route Standards](./servant-routes.md)
- [RFC 9457 Problem Details for Error Bodies](./rfc9457-problem-details.md)
- [Production Request Logging](./request-logging.md)
- [OpenTelemetry Integration](./opentelemetry-integration.md)
