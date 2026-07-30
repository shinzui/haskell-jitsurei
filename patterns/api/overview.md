---
type: Overview
title: "Servant API patterns"
description: "Prescriptive route, response, contract, integration testing, observability, pagination, and health conventions"
timestamp: 2026-07-30T16:01:13-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-overview
tags: [api, servant, standards, openapi, integration-testing, hurl, observability]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T10:28:01-07:00
    document_timestamp: 2026-07-24T10:28:01-07:00
    scope: content
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Servant API patterns

These are mutually reinforcing standards for production Servant services.

- [Servant API Design](servant-routes.md) owns route organization and typed responses.
- [RFC 9457 Problem Details](rfc9457-problem-details.md) owns error bodies.
- [Generating OpenAPI from Types](openapi-from-types.md) owns the published contract.
- [Black-Box API Integration Testing with Hurl](hurl-integration-testing.md) owns live-wire acceptance tests.
- [Relay Pagination](relay-pagination.md) owns list endpoints.
- [OpenTelemetry Integration](opentelemetry-integration.md) owns trace and metric setup.
- [Production Request Logging](request-logging.md) owns safe request records.
- [Kubernetes Health Endpoints](health-endpoints.md) owns liveness and readiness.
