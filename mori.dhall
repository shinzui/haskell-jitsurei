let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/58523ea11e120f3be1c978e509d67f51311a8280/package.dhall
        sha256:e4acbb565c9f4e4b3831dabf084e50f8687dda780b7874ced90ae88d6f349f4f

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
      , { key = "core-record-patterns"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Record definition and manipulation patterns using Generic Lens with #label syntax"
        , location =
            Schema.DocLocation.LocalFile "core/record-patterns.md"
        }
      ]
    }
