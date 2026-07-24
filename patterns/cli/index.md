# Subdirectories

- [agents/](agents/index.md)

# Overview

- [Haskell CLI patterns](overview.md) - Interaction, configuration, help, completion, distribution, and coding-agent patterns for Haskell CLIs

# Pattern

- [Command Aliases via KDL Config File](command-aliases-kdl.md) - Expand KDL-defined CLI aliases safely before optparse-applicative parsing
- [Command Aliases via Config File](command-aliases.md) - Expand user-defined CLI aliases safely before optparse-applicative parsing
- [Copy Command Result to System Clipboard](copy-to-clipboard.md) - Add an opt-in clipboard side channel without breaking stdout composition
- [FZF Integration for Interactive CLI Selection](fzf-integration.md) - Integrate fzf as a composable interactive selector for Haskell CLIs
- [CLI Help Topics with file-embed](help-topics.md) - Ship standalone Markdown help topics inside an optparse-applicative executable
- [Terminal-Aware Help Output Width](help-width.md) - Render help topics at a readable terminal width while keeping piped output byte-stable
- [Hierarchical Config with Dhall](hierarchical-config.md) - Layer user and project Dhall configuration for legacy CLIs; superseded by Settei for new work
- [Option Groups for Organized --help Output](option-groups.md) - Group optparse-applicative flags into readable labeled help sections
- [Shell Completion Generation](shell-completions.md) - Generate Bash, Zsh, and Fish completions from optparse-applicative parsers
- [Stdin Integration for CLI Commands](stdin-integration.md) - Resolve CLI text input through arguments, piped stdin, files, editors, and prompts
- [Embedding Git SHA in CLI Version Output](version-with-git-sha.md) - Embed a Git revision in local Cabal and reproducible Nix version output

