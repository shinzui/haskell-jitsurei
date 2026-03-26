let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/229cb855bca7918e1f0fbed75be4e073eff943b4/package.dhall
        sha256:d19ae156d6c357d982a1aea0f1b6ba1f01d76d2d848545b150db75ed4c39a8a9

in  { project =
      { name = "haskell-jitsurei"
      , namespace = "shinzui"
      , type = Schema.PackageType.Other "Documentation"
      , description = Some
          "Curated collection of Haskell implementation patterns and recipes"
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , domains = [ "haskell", "patterns", "documentation" ]
      , owners = [ "shinzui" ]
      , origin = Schema.Origin.Own
      }
    , repos =
      [ { name = "haskell-jitsurei"
        , github = Some "shinzui/haskell-jitsurei"
        , gitlab = None Text
        , git = None Text
        , localPath = Some "."
        }
      ]
    , packages = [] : List Schema.Package
    , bundles = [] : List Schema.PackageBundle
    , dependencies = [] : List Text
    , apis = [] : List Schema.Api
    , agents = [] : List Schema.AgentHint
    , skills = [] : List Schema.Skill
    , subagents = [] : List Schema.Subagent
    , standards = [] : List Text
    , docs =
      [ { key = "cli-help-topics"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "CLI help topics pattern with file-embed"
        , location = Schema.DocLocation.LocalFile "cli/help-topics.md"
        }
      , { key = "cli-fzf-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "FZF integration pattern for interactive CLI selection"
        , location = Schema.DocLocation.LocalFile "cli/fzf-integration.md"
        }
      , { key = "cli-version-git-sha"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Git SHA version embedding pattern with Nix build support"
        , location =
            Schema.DocLocation.LocalFile "cli/version-with-git-sha.md"
        }
      , { key = "cli-stdin-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Stdin integration pattern for accepting piped input and argument fallback chains"
        , location =
            Schema.DocLocation.LocalFile "cli/stdin-integration.md"
        }
      , { key = "cli-shell-completions"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Shell completion generation pattern for Bash, Zsh, and Fish"
        , location =
            Schema.DocLocation.LocalFile "cli/shell-completions.md"
        }
      , { key = "cli-option-groups"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Option groups pattern for organized --help output with parserOptionGroup"
        , location =
            Schema.DocLocation.LocalFile "cli/option-groups.md"
        }
      , { key = "cli-command-aliases"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Command aliases pattern via config file pre-parse expansion"
        , location =
            Schema.DocLocation.LocalFile "cli/command-aliases.md"
        }
      , { key = "cli-agent-assist-commands"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Agent assist commands pattern for providing live project context to AI coding assistants"
        , location =
            Schema.DocLocation.LocalFile "cli/agents/agent-assist-commands.md"
        }
      , { key = "core-record-patterns"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Record definition and manipulation patterns using Generic Lens with #label syntax"
        , location =
            Schema.DocLocation.LocalFile "core/record-patterns.md"
        }
      , { key = "core-custom-prelude"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Custom prelude pattern for centralizing common re-exports and project-wide utilities"
        , location =
            Schema.DocLocation.LocalFile "core/custom-prelude.md"
        }
      ]
    }
