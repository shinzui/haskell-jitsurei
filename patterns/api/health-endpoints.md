---
type: Standard
title: "Kubernetes Health Endpoints"
description: "Separate in-process liveness from dependency-aware readiness in Servant services"
timestamp: 2026-07-24T15:48:14-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-health-endpoints
tags: [api, servant, kubernetes, health, liveness, readiness, servant-health]
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

# Kubernetes Health Endpoints

**Every service serves `/health/live` (is the process alive) and `/health/ready`
(should it receive traffic); liveness never checks dependencies, while readiness checks
exactly the dependencies whose failure this pod's restart cannot fix. The typed probe
surface comes from the released `servant-health` package — services supply checks and
mount the routes; they never re-implement the probe code.**

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

Do not add downstream HTTP services or Kafka brokers merely because the process calls
them. A downstream readiness dependency can cascade one service's outage across the
fleet. The transactional outbox is specifically the buffer for broker outages; making
Kafka a readiness condition defeats that boundary. Add a dependency only when this pod
cannot serve its contracted request semantics while that dependency is unavailable.

## Mount servant-health; Never Vendor the Probe Code

The typed probe surface is the released **`servant-health`** package (Hackage 0.1.0.0,
verified 2026-07-24). It owns the wire contract and the one dangerous piece of code:
the `AsUnion` instance mapping a passed probe to 200 and a failed probe to 503. Both
alternatives carry the same body type, so that instance is the only place the mapping
exists — which is exactly why it lives in one tested package and **must never be
re-implemented in a service**. An earlier revision of this standard embedded the full
probe code for vendoring; that is superseded.

```cabal
build-depends:
    servant-health ^>=0.1

test-suite service-test
  build-depends:
      servant-health:testkit ^>=0.1
```

The package provides, from `Servant.Health`: the `ProbeStatus` wire type (exactly
`status`, `check`, `failingSince`; a closed contract with a non-orphan `ToSchema` that
always matches the JSON codec), the 200/503 `MultiVerb` response list, the `HealthApi`
record (fields `live` and `ready`), the check seam (`ProbeCheck = IO ProbeVerdict`),
and a `MonadIO`-general `healthServer`. Mount it under `"health"` on the umbrella
record and wire the two checks:

```haskell
import Servant.Health (HealthApi, ProbeCheck, healthServer)
import Servant.Health.Check
  ( boolCheck,
    newFailureTracker,
    safeCheck,
    sequenceChecks,
    withProbeTimeout,
  )

data ServiceApi mode = ServiceApi
  { health :: mode :- "health" :> NamedRoutes HealthApi
    -- application routes follow
  }
  deriving stock (Generic)

mkProbes :: IO (ProbeCheck, ProbeCheck)
mkProbes = do
  trackLive <- newFailureTracker
  trackReady <- newFailureTracker
  let liveness =
        trackLive
          . withProbeTimeout 2_000_000 "liveness"
          . safeCheck "liveness"
          $ boolCheck "liveness" inProcessResponsive
      readiness =
        trackReady . sequenceChecks $
          [ safeCheck "postgres" (boolCheck "postgres" postgresPingOk),
            safeCheck "subscription-lag" (boolCheck "subscription-lag" lagBelowLimit)
          ]
  pure (liveness, readiness)

-- at server assembly:
--   (liveness, readiness) <- mkProbes
--   ... ServiceApi {health = healthServer liveness readiness, ...}
```

The checks themselves stay service-owned (kiroku's `postgresPing` and lag checks are
the prior art above); the combinators are the package's. Wrap **every** check in
`safeCheck` so a thrown exception becomes a failed probe rather than a 500; bound the
liveness check with `withProbeTimeout` (microseconds, matching kiroku's
`livenessTimeoutUs`); compose readiness with `sequenceChecks` (first failure wins); and
wrap each probe with `newFailureTracker` so the wire field `failingSince` reports when
the failure *began* across repeated probe calls, not the current instant.

A probe report describes current system state; it is not an RFC 9457 error document.
Exempt these named routes from the problem-details conformance test.

## Prove the Wiring with the Test Kit

Mounting the routes is three lines, and the two routes share one handler type — so a
service that swaps its liveness and readiness checks still compiles. The package ships
the proof as `servant-health:testkit`; using it is the required per-service test:

```haskell
import Servant.Health.TestKit (probeContractTests)

probeTests :: TestTree
probeTests = probeContractTests "service probes" $ \liveCheck readyCheck ->
  pure (serviceApp testEnv liveCheck readyCheck)
```

The kit owns the two checks, flips them between cases, and asserts the full matrix:
both healthy (200s with the `ok` body), each probe failing alone (503 with the failing
check's name and onset, while the *other* probe stays 200 — the cross-assertions that
catch swapped wiring), and the `application/json` content type.

## Exclude Probe Noise via the Path Constants

Exclude `/health/live` and `/health/ready` from the production request logger's path
predicate — Kubernetes already records probe results, and logging every successful
probe obscures real request traffic. Build the predicate from the package's constants
rather than restating string literals that can drift from the actual routes:

```haskell
import Network.Wai (rawPathInfo)
import Servant.Health.Paths (healthRawPaths)

requestLogPredicate :: Request -> Bool
requestLogPredicate request = rawPathInfo request `notElem` healthRawPaths
```

Use the same constants to name these routes in the problem-details conformance
exemption list. See [Production Request Logging](./request-logging.md).

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
