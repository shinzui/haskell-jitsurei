---
type: Overview
title: "Haskell CLI patterns"
description: "Interaction, configuration, help, completion, distribution, and coding-agent patterns for Haskell CLIs"
timestamp: 2026-10-02T13:18:57Z
generated:
  by: human:nadeem
  at: 2026-07-24T13:57:34Z
resource: mori://shinzui/haskell-jitsurei/docs/cli-overview
tags: [cli, haskell, patterns, optparse-applicative, agents]
status: current
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
- [Settei CLI Configuration](mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard)

## Coding agents

- [Agent Assist Commands](agents/agent-assist-commands.md)
- [Per-Command Agent Configuration](agents/per-command-agent-config.md)
- [Skill and Agent Registry](agents/skill-and-agent-registry.md) — shared
  `baikai-kit` installer and session discovery, including upstream 0.4 visibility

The assist and configuration patterns delegate provider launch construction
to Baikai. The obsolete standalone Claude subprocess workaround and layered
Dhall configuration implementation have been removed.
