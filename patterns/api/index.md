# Overview

- [Servant API patterns](overview.md) - Prescriptive route, response, contract, observability, pagination, and health conventions

# Standard

- [Kubernetes Health Endpoints](health-endpoints.md) - Separate in-process liveness from dependency-aware readiness in Servant services
- [Generating the OpenAPI Document from Servant Types](openapi-from-types.md) - Derive OpenAPI 3.1 from Servant route types and enforce the generated artifact in CI
- [OpenTelemetry Integration for Servant Services](opentelemetry-integration.md) - Wire one OpenTelemetry SDK lifecycle through WAI, Servant, Keiro, and the outbox
- [Relay Pagination for List Endpoints](relay-pagination.md) - Implement typed Relay cursor pagination with keyset SQL and conformance tests
- [Production Request Logging](request-logging.md) - Emit bounded structured WAI request logs with trace correlation and strict data minimization
- [RFC 9457 Problem Details for Error Bodies](rfc9457-problem-details.md) - Standardize Servant error responses on application/problem+json with stable extension fields
- [Servant API Design](servant-routes.md) - Organize Servant APIs as vertical NamedRoutes slices with typed MultiVerb responses

