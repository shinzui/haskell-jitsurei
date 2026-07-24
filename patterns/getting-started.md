---
type: Navigation
title: "Find the right Haskell pattern"
description: "Task-oriented routes into the Haskell standards, API conventions, CLI patterns, and agent guidance"
timestamp: 2026-07-24T06:57:34-07:00
resource: mori://shinzui/haskell-jitsurei/docs/patterns-getting-started
tags: [navigation, haskell, patterns, standards, discovery]
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

# Find the right Haskell pattern

Start from the task, not from a guessed filename. Every document is written for
both humans and coding agents and carries a concise description, search tags,
lifecycle status, and timestamp-bound review provenance.

## Starting or standardizing a Haskell project

Read [Core Haskell patterns](core/overview.md). Begin with
[Haskell Core Standards](core/standards.md), then choose the record, custom
prelude, and multiline-string patterns that apply.

## Designing or operating a Servant API

Read [Servant API patterns](api/overview.md). The usual order is:

1. [Servant API Design](api/servant-routes.md) for route and response types.
2. [RFC 7807 Problem Details](api/rfc7807-problem-details.md) for error bodies.
3. [Generating OpenAPI from Types](api/openapi-from-types.md) for the published contract.
4. [OpenTelemetry](api/opentelemetry-integration.md) and
   [request logging](api/request-logging.md) for observability.
5. [Health endpoints](api/health-endpoints.md) for deployment behavior.

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

The [layered Dhall configuration pattern](cli/hierarchical-config.md) is
`legacy`; use it only for tools that already adopted that design.

## Building agent-aware tooling

The agent-specific CLI patterns live under `cli/agents/`:

- [Agent Assist Commands](cli/agents/agent-assist-commands.md) for live context;
- [Per-Command Agent Configuration](cli/agents/per-command-agent-config.md) for
  provider, model, and reasoning selection;
- [Skill and Agent Registry](cli/agents/skill-and-agent-registry.md) for
  distributing reusable capabilities;
- [Claude CLI subprocess gotchas](cli/agents/claude-cli-pitfalls.md) before
  invoking Claude Code from Haskell.

## Inspecting trust and change history

Read the [Review and Change Provenance Standard](governance/review-policy.md)
before approving or materially changing a concept. Run:

```sh
scripts/review-status
```

The report names current human reviewers and model reviews as
`provider/model`; `-` means that review class is still pending. Dated
`log.md` files record changes for the nearest directory scope.
