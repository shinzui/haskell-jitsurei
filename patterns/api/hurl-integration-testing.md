---
type: Standard
title: "Black-Box API Integration Testing with Hurl"
description: "Exercise a live Haskell HTTP service with resource-family Hurl suites, explicit assertions, and isolated opt-in scenarios"
timestamp: 2026-07-30T16:01:13-07:00
resource: mori://shinzui/haskell-jitsurei/docs/api-hurl-integration-testing
tags: [api, integration-testing, hurl, black-box, http, servant, ci]
status: current
---

# Black-Box API Integration Testing with Hurl

**Every HTTP service keeps a Hurl suite that runs against a real listening server.
Organize the suite by resource family, assert status in every request block and media
type plus stable wire semantics for every body-bearing response, and list the safe
independent families explicitly in the default runner. Put writes, special
authentication modes, and computed signatures in separate opt-in suites whose
prerequisites are documented.**

Hurl proves the boundary that an in-process Haskell test cannot: the built executable
started, bound a socket, installed its WAI middleware in the right order, loaded its
runtime configuration, and served the expected public HTTP contract. It complements
typed tests and generated OpenAPI; it does not replace either.

The fleet reference implementation is `mori://shinzui/mori/repos/mori`, under
`mori-api/test/hurl/`.

## Keep the Three API Test Layers Distinct

Use each layer for the failure modes it can see:

| Layer | Owns |
| --- | --- |
| In-process Haskell tests | Handler behavior, dependency injection, error branches, route-to-handler wiring, and deterministic database fixtures |
| Generated OpenAPI checks | The route type's declared statuses, parameters, schemas, and media types; regeneration and linting |
| Hurl against a live server | Process startup, socket binding, middleware, authentication, CORS, serialization, headers, and end-to-end read/write visibility |

Do not move detailed domain combinatorics or large JSON snapshots into Hurl. Keep those
fast and deterministic in Haskell. Conversely, a `Wai.Test` request alone is not proof
that the packaged executable listens with the production middleware and configuration.

Every endpoint added or materially changed gets both its appropriate in-process test
and a matching request block in its resource family's `.hurl` file. The Hurl block
asserts the public behavior a client relies on, not merely that some 2xx response
arrived.

## Provide Hurl as a Project Tool

Hurl is an external test executable, not a Cabal dependency. Put it in the reproducible
development and CI environment rather than asking contributors to install an
unrecorded global binary. For a Nix development shell, add `pkgs.hurl` to the existing
tool list:

```nix
packages = [
  pkgs.hurl
];
```

The project's Nix lock then pins the delivered build. The examples in this standard
were checked with `hurl` and `hurlfmt` 8.0.1 on 2026-07-30. Re-check the
[official installation guidance](https://hurl.dev/docs/installation.html) and upstream
release before requiring syntax from a newer version.

Do not add `hurl` to a Cabal `build-depends` stanza: no Haskell module imports it, and
ordinary library consumers do not need the test client.

## Use a Resource-Family Layout

Keep black-box assets beside the API package, not mixed into unit-test fixtures:

```text
service-api/test/hurl/
├── README.md
├── vars.env
├── run.sh
├── health.hurl
├── openapi.hurl
├── widgets.hurl
├── commands.hurl          # opt-in: mutates state
└── perimeter/
    ├── README.md
    └── perimeter.hurl     # opt-in: different server configuration
```

The checked-in `vars.env` contains only non-secret defaults:

```properties
base_url=http://127.0.0.1:8080
```

The suite `README.md` is part of the test contract. It states:

- how to start the server and provision its database;
- the required fixture cardinality and identities;
- which files the default runner executes;
- which files mutate state or need a separately configured server;
- how secrets or generated request material are supplied; and
- whether re-running each opt-in flow is idempotent or needs cleanup.

Use one `.hurl` file per resource family, not one file per status code and not one
monolithic file for the entire API. Requests within a file are sequential and may use
captures; different files must be independent because Hurl runs files in parallel in
`--test` mode.

## Make the Default Runner Boring and Explicit

The default runner targets an already-running server. Starting the executable, waiting
for readiness, seeding state, collecting server logs, and stopping it belong to a
higher-level `just`, Nix, or CI orchestration step. This separation keeps the Hurl suite
usable against either a locally started process or an equivalent ephemeral CI service.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

hurlfmt --check \
  health.hurl \
  openapi.hurl \
  widgets.hurl \
  commands.hurl \
  perimeter/perimeter.hurl

hurl --test --variables-file vars.env \
  health.hurl \
  openapi.hurl \
  widgets.hurl
```

Expose that runner through the repository's normal task interface:

```just
# Run the safe black-box API suite against an already-running service.
hurl:
  service-api/test/hurl/run.sh
```

List safe files by name. A broad `*.hurl` glob silently pulls a newly added stateful or
privileged scenario into the default suite. `set -euo pipefail` and Hurl's non-zero
test exit make the script directly usable as a CI gate.

## Assert the Public Contract, Not Incidental Data

Every request block pins the expected status. For structured responses, also assert the
media type and the stable fields or invariants that distinguish a correct response.
Given a database seeded with at least two widgets:

```hurl
# The first page has the Relay envelope and supplies values for this workflow.
GET {{base_url}}/v1/widgets?first=1
HTTP 200
[Captures]
first_widget_id: jsonpath "$.edges[0].node.id"
cursor: jsonpath "$.pageInfo.endCursor"
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.edges" count == 1
jsonpath "$.edges[0].cursor" exists
jsonpath "$.pageInfo.hasNextPage" isBoolean

# Captures are available to later requests in this file.
GET {{base_url}}/v1/widgets/{{first_widget_id}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.id" == "{{first_widget_id}}"

# Following the cursor proves that paging advances rather than repeating a row.
GET {{base_url}}/v1/widgets?first=1&after={{cursor}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.edges" count == 1
jsonpath "$.edges[0].node.id" != "{{first_widget_id}}"
jsonpath "$.pageInfo.hasPreviousPage" == true
```

Capturing a value is better than copying an environment-specific identifier into the
file. Capture only from fixtures whose existence is an explicit suite precondition; a
capture from an arbitrary possibly-empty collection makes the test nondeterministic.

Avoid assertions on volatile timestamps, total counts, database ordering that the API
does not promise, or an entire response body. Assert exact values when the fixture and
contract make them exact; otherwise assert types, shapes, redaction, and semantic
relationships. The official Hurl documentation covers the available
[response assertions](https://hurl.dev/docs/asserting-response.html) and
[captures](https://hurl.dev/docs/capturing-response.html).

## Test Failures and Security Boundaries

A happy path is not enough. For each endpoint family, select the relevant failures:

- malformed path and query parameters;
- missing resources;
- unsupported media types or invalid request bodies;
- unauthenticated and unauthorized requests;
- pagination boundary failures; and
- redaction of credentials or write-only fields.

Pin the error media type and stable machine-readable code, not a prose message that may
be edited:

```hurl
GET {{base_url}}/v1/widgets?first=-1
HTTP 400
[Asserts]
header "Content-Type" contains "application/problem+json"
jsonpath "$.status" == 400
jsonpath "$.code" == "negative_page_size"
jsonpath "$.retryable" == false
```

When the contract intentionally uses a different error type, assert that type instead
of coercing the endpoint to the general problem-details convention. The test should
make an exemption visible.

Security configuration deserves a separate perimeter suite when it requires a
different server instance. Exercise public probes, missing and invalid credentials,
valid credentials, allowed CORS preflights, rejected origins, and CORS headers on the
actual authenticated response. Supply real credentials with `--secret` or
`--secrets-file`, never through the tracked `vars.env`:

```bash
hurl --test \
  --variables-file vars.env \
  --secret auth_token="$SERVICE_API_TOKEN" \
  perimeter/perimeter.hurl
```

Hurl redacts secret values from its diagnostic logs and reports by exact matching, but
does not alter HTTP response bodies written to standard output and may preserve those
bodies in a JSON report. A test server must never echo credentials, and CI must treat
response reports as potentially sensitive. See the official
[template and secret rules](https://hurl.dev/docs/templates.html).

## Isolate Writes and Eventual Consistency

Keep the default suite read-only whenever practical. Put command endpoints in an
explicit opt-in file when they need a writable database, filesystem path, queue, or
other persistent side effect. Prove a write through a subsequent public read rather
than by querying the database behind the service.

For an eventually consistent read model, retry only the read that observes the write:

```hurl
GET {{base_url}}/v1/widgets/{{widget_id}}
[Options]
retry: 10
retry-interval: 300ms
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.id" == "{{widget_id}}"
jsonpath "$.state" == "active"
```

Do not add an unconditional sleep. Entry-level retries stop as soon as the status and
assertions pass and make the consistency boundary explicit. Do not apply global retries
to the entire suite merely to hide server-startup races; the orchestration layer waits
for `/health/ready` before starting Hurl.

`--test` executes input files in parallel, while requests within one file remain
sequential. Therefore:

- never depend on a capture or mutation from another `.hurl` file;
- give parallel write flows distinct fixture identities;
- make setup idempotent and document cleanup; and
- use `--jobs 1` only when unavoidable shared state genuinely requires serial files.

The official [test runner documentation](https://hurl.dev/docs/running-tests.html)
describes this execution model, and the [entry documentation](https://hurl.dev/docs/entry.html)
defines retry behavior.

## Precompute Unsupported Request Material

Hurl templates substitute values but are not a general computation language. When a
protocol needs data that cannot be expressed in the file—for example, a timestamped
HMAC over the exact request bytes—use a small helper before Hurl runs:

1. construct the body once as bytes;
2. write those exact bytes to an ignored generated file;
3. compute the signature over that file; and
4. emit Hurl variables or secrets consumed by the request.

The `.hurl` entry sends the generated file rather than reconstructing similar-looking
JSON:

```hurl
POST {{base_url}}/v1/ingest/webhook
webhook-id: {{webhook_id}}
webhook-timestamp: {{webhook_timestamp}}
webhook-signature: {{webhook_signature}}
Content-Type: application/octet-stream
file,ingest.body.json;
HTTP 202
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.accepted" isInteger
```

The request body and signed bytes must be the same file. Keep generated bodies out of
Git, make the helper's inputs explicit, and keep this family opt-in if it depends on a
real registered entity or secret. Hurl's official FAQ likewise recommends performing
[calculations before execution](https://hurl.dev/docs/frequently-asked-questions.html)
when templates are insufficient.

## Wire It into CI Without Hiding Failures

The CI job follows this lifecycle:

1. build the service and provision an isolated database;
2. start the packaged executable with test configuration;
3. poll its readiness endpoint with a bounded timeout;
4. run `hurlfmt --check` and the safe Hurl suite;
5. run explicitly authorized opt-in suites, if the job provisioned their prerequisites;
6. retain Hurl and server logs on failure; and
7. stop the process and dispose of the database even when a test fails.

Use `--report-junit <file>` when the CI system renders JUnit results. Do not point a
stateful suite at production, and do not let a default `base_url` come from an ambient
shell variable that can silently redirect destructive requests.

The checked-in OpenAPI artifact still gets its regeneration and lint gate. A small
`openapi.hurl` file should only prove that the live server exposes the expected OpenAPI
version and representative paths; it is not a second hand-written schema.

## Review Checklist

Before accepting an API change, verify:

- the resource family's `.hurl` file covers the new or changed operation;
- every block asserts status, and every body-bearing response asserts media type and
  stable public semantics;
- relevant negative, authentication, pagination, and redaction behavior is present;
- fixtures and minimum cardinality are documented;
- no file depends on ordering or captures from another file;
- stateful or specially configured families are excluded from the explicit default list;
- secrets are injected as secrets and generated artifacts are ignored;
- eventual consistency uses a bounded entry retry, not a sleep; and
- `hurlfmt --check`, the live suite, in-process tests, and OpenAPI checks all pass.

## Related Patterns

- [Servant API Design](./servant-routes.md)
- [Generating the OpenAPI Document from Servant Types](./openapi-from-types.md)
- [RFC 9457 Problem Details for Error Bodies](./rfc9457-problem-details.md)
- [Relay Pagination for List Endpoints](./relay-pagination.md)
- [Kubernetes Health Endpoints](./health-endpoints.md)
