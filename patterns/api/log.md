# api Update Log

## 2026-07-24
* **Consistency**: servant-routes' common stanza now lists the full Core Standards extension baseline (adds OverloadedLabels)
* **Correction**: servant-routes — fixed the router-order claim (literals are not hoisted above sibling captures; declaration order with backtracking decides), scoped the MultiVerb rule with named exemptions (Raw, streaming, cannot-fail single-status) while keeping NamedRoutes unconditional, aligned the umbrella/health examples with the health standard, added the `-Werror=missing-fields` caveat and a UVerb note
* **Correction**: openapi-from-types — the upstream `servant-openapi3` failure mode is a compile error (no MultiVerb instance), not silent omission; added the 4.1-cohort rule for relay consumers and the servant >= 0.20.3 gate
* **Correction**: opentelemetry-integration — per-signal OTLP endpoint variables get the signal path appended by the released 1.0.0.0 exporters, so only the base endpoint is safe; request-log middleware calls now pass the predicate argument
* **Correction**: rfc7807-problem-details — kotei's MultiVerb adoption marked as an unimplemented plan; shomei's 405 rewrite is unconditional
* **Nuance**: relay-pagination — added "When a Plain List Is Allowed" (bounded-by-design snapshots, capped batch lookups, paginate-when-in-doubt)
* **Review**: Recorded model reviews (anthropic/claude-fable-5, technical-accuracy) for all API standards after verifying claims against servant 0.20.3, relay-pagination 0.1.0.0, hs-opentelemetry 1.0.0.0, openapi-hs 5.0.0/servant-openapi-hs 5.1.0, wai-extra, keiro, kiroku, and shomei sources
* **Correction**: Removed migration-time metadata approvals; API standards now remain explicitly unreviewed until an actual review occurs
* **Migration**: Classified the Servant API standards and added searchable OKF metadata and review provenance
