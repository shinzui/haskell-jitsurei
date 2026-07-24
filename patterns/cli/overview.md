---
type: Overview
title: "Haskell CLI patterns"
description: "Interaction, configuration, help, completion, distribution, and coding-agent patterns for Haskell CLIs"
timestamp: 2026-07-24T06:57:34-07:00
resource: mori://shinzui/haskell-jitsurei/docs/cli-overview
tags: [cli, haskell, patterns, optparse-applicative, agents]
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

# Haskell CLI patterns

Choose the smallest patterns that match the command's interaction surface.

## Input and selection

- [Stdin Integration](stdin-integration.md)
- [FZF Integration](fzf-integration.md)
- [Copy to Clipboard](copy-to-clipboard.md)

## Help and discovery

- [Embedded Help Topics](help-topics.md)
- [Terminal-Aware Help Width](help-width.md)
- [Option Groups](option-groups.md)
- [Shell Completions](shell-completions.md)

## Configuration and release identity

- [Command Aliases](command-aliases.md)
- [Command Aliases with KDL](command-aliases-kdl.md)
- [Git SHA Version Output](version-with-git-sha.md)
- [Hierarchical Dhall Config](hierarchical-config.md) — legacy only

## Coding agents

- [Agent Assist Commands](agents/agent-assist-commands.md)
- [Per-Command Agent Configuration](agents/per-command-agent-config.md)
- [Skill and Agent Registry](agents/skill-and-agent-registry.md)
- [Claude CLI Subprocess Gotchas](agents/claude-cli-pitfalls.md)
