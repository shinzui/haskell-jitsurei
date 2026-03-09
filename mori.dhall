let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/4412469f2960b8faa48c123451bf90c0d3400db3/package.dhall
        sha256:2e416c2d8c28c0b3b217cab47cc6d9e8bb9bec34b87d476edbb0d6d0863d1401

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
      ]
    }
