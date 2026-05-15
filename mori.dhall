let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/1f70781427426c09673d46f8e6733b7e7d0abedc/package.dhall
        sha256:3b79aae9216456678300441ca8616b64a4b4fa520a1286dfcc418f60899d5d4a

in  Schema.Project::{ project =
      Schema.ProjectIdentity::{ name = "haskell-jitsurei"
      , namespace = "shinzui"
      , type = Schema.PackageType.Other "Documentation"
      , description = Some
          "Curated collection of Haskell implementation patterns and recipes"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "haskell", "patterns", "documentation" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{ name = "haskell-jitsurei"
        , github = Some "shinzui/haskell-jitsurei"
        , localPath = Some "."
        }
      ]
    , docs =
      [ Schema.DocRef::{ key = "cli-help-topics"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "CLI help topics pattern with file-embed"
        , location = Schema.DocLocation.LocalFile "cli/help-topics.md"
        }
      , Schema.DocRef::{ key = "cli-fzf-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "FZF integration pattern for interactive CLI selection"
        , location = Schema.DocLocation.LocalFile "cli/fzf-integration.md"
        }
      , Schema.DocRef::{ key = "cli-version-git-sha"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Git SHA version embedding pattern with Nix build support"
        , location =
            Schema.DocLocation.LocalFile "cli/version-with-git-sha.md"
        }
      , Schema.DocRef::{ key = "cli-stdin-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Stdin integration pattern for accepting piped input and argument fallback chains"
        , location =
            Schema.DocLocation.LocalFile "cli/stdin-integration.md"
        }
      , Schema.DocRef::{ key = "cli-shell-completions"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Shell completion generation pattern for Bash, Zsh, and Fish"
        , location =
            Schema.DocLocation.LocalFile "cli/shell-completions.md"
        }
      , Schema.DocRef::{ key = "cli-option-groups"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Option groups pattern for organized --help output with parserOptionGroup"
        , location =
            Schema.DocLocation.LocalFile "cli/option-groups.md"
        }
      , Schema.DocRef::{ key = "cli-command-aliases"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Command aliases pattern via config file pre-parse expansion"
        , location =
            Schema.DocLocation.LocalFile "cli/command-aliases.md"
        }
      , Schema.DocRef::{ key = "cli-command-aliases-kdl"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Command aliases pattern using a KDL config block decoded with KDL.remainingNodesWith"
        , location =
            Schema.DocLocation.LocalFile "cli/command-aliases-kdl.md"
        }
      , Schema.DocRef::{ key = "cli-agent-assist-commands"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Agent assist commands pattern for providing live project context to AI coding assistants"
        , location =
            Schema.DocLocation.LocalFile "cli/agents/agent-assist-commands.md"
        }
      , Schema.DocRef::{ key = "core-record-patterns"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Record definition and manipulation patterns using Generic Lens with #label syntax"
        , location =
            Schema.DocLocation.LocalFile "core/record-patterns.md"
        }
      , Schema.DocRef::{ key = "core-custom-prelude"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Custom prelude pattern for centralizing common re-exports and project-wide utilities"
        , location =
            Schema.DocLocation.LocalFile "core/custom-prelude.md"
        }
      , Schema.DocRef::{ key = "core-multiline-strings"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Multiline string literals with automatic indentation stripping using GHC 9.12 MultilineStrings extension"
        , location =
            Schema.DocLocation.LocalFile "core/multiline-strings.md"
        }
      , Schema.DocRef::{ key = "cli-skill-and-agent-registry"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Distributable skill and agent registry pattern for installing AI skills and subagents from a GitHub repository"
        , location =
            Schema.DocLocation.LocalFile "cli/agents/skill-and-agent-registry.md"
        }
      , Schema.DocRef::{ key = "cli-hierarchical-config"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Hierarchical config pattern with layered Dhall files, precedence-based discovery, and per-layer validation"
        , location =
            Schema.DocLocation.LocalFile "cli/hierarchical-config.md"
        }
      , Schema.DocRef::{ key = "cli-copy-to-clipboard"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Opt-in --copy flag pattern for copying a command's primary output to the system clipboard via pbcopy/xclip"
        , location =
            Schema.DocLocation.LocalFile "cli/copy-to-clipboard.md"
        }
      , Schema.DocRef::{ key = "cli-help-width"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Terminal-aware --width flag for help-topic output: ioctl-based auto-detect with a readability cap, byte-stable verbatim output when piped, indent-aware paragraph wrap, and parser-shape pitfalls that break the FZF picker path"
        , location =
            Schema.DocLocation.LocalFile "cli/help-width.md"
        }
      , Schema.DocRef::{ key = "cli-claude-cli-pitfalls"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Pitfalls when invoking the `claude` CLI as a subprocess from a Haskell CLI: the variadic --add-dir greedily eats the positional prompt without a `--` terminator (errors on short prompts, hangs on large ones); fix, stdin alternative, and a contract test to catch regressions"
        , location =
            Schema.DocLocation.LocalFile "cli/agents/claude-cli-pitfalls.md"
        }
      ]
    }
