---
type: Standard
title: "Review and Change Provenance"
description: "Record material changes and timestamp-bound human and model reviews for every pattern"
timestamp: 2026-07-24T06:57:34-07:00
resource: mori://shinzui/haskell-jitsurei/docs/governance-review-policy
tags: [governance, review, provenance, changelog, agents, okf]
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

# Review and Change Provenance

Every concept keeps content history in Git, change summaries in the nearest
`log.md`, and review provenance in its `reviews` frontmatter list. A review is
valid for exactly the `document_timestamp` it names; after a material change,
old review records remain as history but are reported as stale.

## Material changes

A material change alters advice, examples, supported versions, applicability,
or the route by which a reader selects the pattern. For every material change:

1. Set `timestamp` to the change time in RFC 3339 form.
2. Add a concise entry to the nearest enclosing `log.md`.
3. Keep old review records and append new reviews after the change is reviewed.
4. Regenerate the OKF indexes.
5. Run `mori validate`.
6. Run `okf validate patterns --strict --profile okf/patterns.dhall
   --profile-enforce --log-enforce`.
7. Run `scripts/review-status --check`.

Typographical fixes that do not alter meaning may retain the timestamp, but
still belong in Git history.

## Review record

Each entry in `reviews` has this common shape:

```yaml
- kind: human | model
  reviewer: stable-human-or-agent-identity
  reviewed_at: 2026-07-24T06:57:34-07:00
  document_timestamp: 2026-07-24T06:57:34-07:00
  scope: content | technical-accuracy | editorial | catalog-metadata | content-and-metadata
  outcome: approved | changes-requested | commented
```

A model review also requires:

```yaml
  provider: openai
  model: gpt-5
```

Use the provider that served the model, not the client application. Use the
most specific model identifier actually available; never infer an undisclosed
deployment identifier. A human review uses the person's durable GitHub handle
or organization identity and omits `provider` and `model`.

`scope` is mandatory. In particular, `catalog-metadata` means the reviewer
checked classification, description, tags, links, and OKF placement—not the
technical claims in the body.

## Review states

Run `scripts/review-status` to list current human reviewers, current
`provider/model` reviews, and stale-record counts. Missing review classes appear
as `-`, so “not reviewed” is explicit rather than silently absent.

`okf validate` owns bundle, profile, link, and log validation. The review-status
check only handles the richer structure inside the OKF `reviews` extension:
well-formed records and at least one review tied to the current document
timestamp. It does not pretend that the initial corpus has already received
human review. For a release or other high-trust checkpoint, run:

```sh
scripts/review-status --require-human
```

This fails until every current concept has a current human approval.

## Lifecycle and selection

Use `status: current` for advice recommended for new work, `status: legacy` for
advice retained only for existing adopters, and `status: retired` when the body
exists solely for historical context. A legacy or retired document must explain
the replacement near the top of its body and should use `supersedes` or body
links to make the new route discoverable.
