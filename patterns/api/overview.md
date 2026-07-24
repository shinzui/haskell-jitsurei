---
type: Overview
title: "Servant API patterns"
description: "Prescriptive route, response, contract, observability, pagination, and health conventions"
timestamp: 2026-07-24T06:57:34-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-overview
tags: [api, servant, standards, openapi, observability]
status: current
reviews:
  - kind: model
    reviewer: codex
    provider: openai
    model: gpt-5
    reviewed_at: 2026-07-24T06:57:34-07:00
    document_timestamp: 2026-07-24T06:57:34-07:00
    scope: content-and-metadata
    outcome: approved
---

# Servant API patterns

These are mutually reinforcing standards for production Servant services.

- [Servant API Design](servant-routes.md) owns route organization and typed responses.
- [RFC 7807 Problem Details](rfc7807-problem-details.md) owns error bodies.
- [Generating OpenAPI from Types](openapi-from-types.md) owns the published contract.
- [Relay Pagination](relay-pagination.md) owns list endpoints.
- [OpenTelemetry Integration](opentelemetry-integration.md) owns trace and metric setup.
- [Production Request Logging](request-logging.md) owns safe request records.
- [Kubernetes Health Endpoints](health-endpoints.md) owns liveness and readiness.
