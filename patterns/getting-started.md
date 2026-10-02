---
type: Navigation
title: "Find the right Haskell pattern"
description: "Task-oriented routes into the Haskell standards, API conventions, CLI patterns, and agent guidance"
timestamp: 2026-10-02T13:18:57Z
generated:
  by: human:nadeem
  at: 2026-07-30T23:01:13Z
resource: mori://shinzui/haskell-jitsurei/docs/patterns-getting-started
tags: [navigation, haskell, patterns, standards, discovery]
status: current
---

# Find the right Haskell pattern

Start from the task, not from a guessed filename. Every document is written for
both humans and coding agents and carries a concise description, search tags,
and lifecycle status. Review status is explicit, including when no human or
model has reviewed the current version.

## Starting or standardizing a Haskell project

Read [Core Haskell patterns](core/overview.md). Begin with
[Haskell Core Standards](core/standards.md), then choose the record, custom
prelude, and multiline-string patterns that apply.

## Designing or operating a Servant API

Read [Servant API patterns](api/overview.md). The usual order is:

1. [Servant API Design](api/servant-routes.md) for route and response types.
2. [RFC 9457 Problem Details](api/rfc9457-problem-details.md) for error bodies.
3. [Generating OpenAPI from Types](api/openapi-from-types.md) for the published contract.
4. [OpenTelemetry](api/opentelemetry-integration.md) and
   [request logging](api/request-logging.md) for observability.
5. [Health endpoints](api/health-endpoints.md) for deployment behavior.
6. [Black-box API integration testing with Hurl](api/hurl-integration-testing.md)
   for the live HTTP contract.

Use [Relay Pagination](api/relay-pagination.md) when an endpoint returns a
collection.

## Building a Haskell CLI

Read [Haskell CLI patterns](cli/overview.md). Choose by user interaction:

- input: [stdin integration](cli/stdin-integration.md);
- selection: [fzf integration](cli/fzf-integration.md);
- help: [embedded help topics](cli/help-topics.md),
  [terminal-aware width](cli/help-width.md), and
  [option groups](cli/option-groups.md);
- configuration: [command aliases](cli/command-aliases.md) or the
  [KDL variant](cli/command-aliases-kdl.md);
- distribution: [shell completions](cli/shell-completions.md) and
  [version output](cli/version-with-git-sha.md).

For configuration loading and diagnostics, use the
[Settei CLI standard](mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard).
The superseded layered-Dhall implementation has been removed from this catalog.

## Building agent-aware tooling

The agent-specific CLI patterns live under `cli/agents/`:

- [Agent Assist Commands](cli/agents/agent-assist-commands.md) for live context;
- [Per-Command Agent Configuration](cli/agents/per-command-agent-config.md) for
  provider, model, and reasoning selection;
- [Skill and Agent Registry](cli/agents/skill-and-agent-registry.md) for the
  shared `baikai-kit` lifecycle, provider-native assets, scope/visibility,
  and session discovery. Its version boundary distinguishes published 0.3
  from upstream's unreleased 0.4 visibility support.

Use Baikai's provider launchers for subprocess construction; the assist
pattern explains the three request surfaces and handling of render refusals.

## Inspecting trust and change history

Read the [Review and Change Provenance Standard](governance/review-policy.md)
before approving or materially changing a concept. Run:

```sh
scripts/review-status
```

The report names current human reviewers and model reviews as
`provider/model`; `-` means no review of that class is recorded. Dated
`log.md` files record changes for the nearest directory scope.
