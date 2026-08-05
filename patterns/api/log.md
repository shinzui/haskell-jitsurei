# api Update Log

## 2026-08-05
* **Adoption**: opentelemetry-integration now requires `cachix/hs-opentelemetry-instrumentation-servant` 0.3.0.0 in every Servant service — without it the WAI middleware names every server span after the bare HTTP method and its `http.server.*` metrics carry no route dimension; records the Git pin (not on Hackage, no 0.3.0.0 tag), the `allow-newer` needed against the 1.0.0.0 cohort, the `HasEndpoint` orphan instances for `MultiVerb` and `AuthProtect` that fleet-shaped APIs will not compile without, the emitted attributes and their deviations from the semantic conventions, and the unconditional-match trap in the `Raw` instance
* **Consistency**: request-logging points at the servant middleware layer that now sits between the WAI middleware and the request logger; the api overview names route naming as part of what the OpenTelemetry standard owns

## 2026-07-30
* **Addition**: Added a Hurl black-box integration-testing standard based on the Mori API suite: resource-family files, an explicit read-only default runner, status/media/shape and negative assertions, capture-based workflows, isolated stateful and perimeter suites, entry-level retries for eventual consistency, precomputed signed bodies, secret handling, and CI lifecycle guidance

## 2026-07-24
* **Adoption**: health-endpoints now prescribes the released `servant-health` 0.1.0.0 package (mount `HealthApi`, wire checks through the `Servant.Health.Check` combinators, prove wiring with `servant-health:testkit`, build logger exclusions from `Servant.Health.Paths`) instead of vendoring the probe code; the `AsUnion` mapping lives in the package and must not be re-implemented
* **Correction**: relay-pagination and openapi-from-types updated for `relay-pagination` 0.1.1.0, which targets the 5.x OpenAPI cohort — the 4.1-cohort decision rule is retired; request-logging points servant-health consumers at `healthRawPaths` for the probe exclusion
* **Rename**: The problem-details standard now targets RFC 9457 by name (obsoletes RFC 7807, identical wire format) — concept renamed to `api/rfc9457-problem-details`, all cross-references, section citations, and the mori.dhall DocRef updated; the body records the 7807 history for readers of older fleet code
* **Consistency**: servant-routes' common stanza now lists the full Core Standards extension baseline (adds OverloadedLabels)
* **Correction**: servant-routes — fixed the router-order claim (literals are not hoisted above sibling captures; declaration order with backtracking decides), scoped the MultiVerb rule with named exemptions (Raw, streaming, cannot-fail single-status) while keeping NamedRoutes unconditional, aligned the umbrella/health examples with the health standard, added the `-Werror=missing-fields` caveat and a UVerb note
* **Correction**: openapi-from-types — the upstream `servant-openapi3` failure mode is a compile error (no MultiVerb instance), not silent omission; added the 4.1-cohort rule for relay consumers and the servant >= 0.20.3 gate
* **Correction**: opentelemetry-integration — per-signal OTLP endpoint variables get the signal path appended by the released 1.0.0.0 exporters, so only the base endpoint is safe; request-log middleware calls now pass the predicate argument
* **Correction**: rfc7807-problem-details — kotei's MultiVerb adoption marked as an unimplemented plan; shomei's 405 rewrite is unconditional
* **Nuance**: relay-pagination — added "When a Plain List Is Allowed" (bounded-by-design snapshots, capped batch lookups, paginate-when-in-doubt)
* **Review**: Recorded model reviews (anthropic/claude-fable-5, technical-accuracy) for all API standards after verifying claims against servant 0.20.3, relay-pagination 0.1.0.0, hs-opentelemetry 1.0.0.0, openapi-hs 5.0.0/servant-openapi-hs 5.1.0, wai-extra, keiro, kiroku, and shomei sources
* **Correction**: Removed migration-time metadata approvals; API standards now remain explicitly unreviewed until an actual review occurs
* **Migration**: Classified the Servant API standards and added searchable OKF metadata and review provenance
