let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/93104153ecf8817547229a867302a70a25c4b3d8/package.dhall
        sha256:5e00bba267f27069df1d3caadfec2ec6a8c4e797ce652d78c09528f981b71b42

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
    , dependencies = [ "shinzui/okf" ]
    , okfBundles =
      [ Schema.OkfBundle::{ name = "patterns"
        , path = "patterns"
        , profile = Some "okf/patterns.dhall"
        , okfVersion = "0.1"
        , description = Some
            "Haskell standards and implementation patterns for humans and coding agents"
        }
      ]
    , docs =
      [ Schema.DocRef::{ key = "patterns-getting-started"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Task-oriented routes into the Haskell standards, API conventions, CLI patterns, and agent guidance"
        , location =
            Schema.DocLocation.LocalFile "patterns/getting-started.md"
        }
      , Schema.DocRef::{ key = "core-overview"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some
            "Overview of the baseline language, record, prelude, and multiline-string conventions"
        , location =
            Schema.DocLocation.LocalFile "patterns/core/overview.md"
        }
      , Schema.DocRef::{ key = "api-overview"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.Module
        , description = Some
            "Overview of the route, response, contract, integration-testing, observability, pagination, and health standards for Servant APIs"
        , location =
            Schema.DocLocation.LocalFile "patterns/api/overview.md"
        }
      , Schema.DocRef::{ key = "cli-overview"
        , kind = Schema.DocKind.Guide
        , audience = Schema.DocAudience.User
        , description = Some
            "Overview of interaction, configuration, help, distribution, and coding-agent patterns for Haskell CLIs"
        , location =
            Schema.DocLocation.LocalFile "patterns/cli/overview.md"
        }
      , Schema.DocRef::{ key = "governance-review-policy"
        , kind = Schema.DocKind.BestPractice
        , audience = Schema.DocAudience.User
        , description = Some
            "Timestamp-bound human and model review provenance and OKF change-log policy"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/governance/review-policy.md"
        }
      , Schema.DocRef::{ key = "cli-help-topics"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "CLI help topics pattern with file-embed"
        , location =
            Schema.DocLocation.LocalFile "patterns/cli/help-topics.md"
        }
      , Schema.DocRef::{ key = "cli-fzf-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "FZF integration pattern for interactive CLI selection"
        , location =
            Schema.DocLocation.LocalFile "patterns/cli/fzf-integration.md"
        }
      , Schema.DocRef::{ key = "cli-version-git-sha"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Git SHA version embedding pattern with Nix build support"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/version-with-git-sha.md"
        }
      , Schema.DocRef::{ key = "cli-stdin-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Stdin integration pattern for accepting piped input and argument fallback chains"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/stdin-integration.md"
        }
      , Schema.DocRef::{ key = "cli-shell-completions"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Shell completion generation pattern for Bash, Zsh, and Fish"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/shell-completions.md"
        }
      , Schema.DocRef::{ key = "cli-option-groups"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Option groups pattern for organized --help output with parserOptionGroup"
        , location =
            Schema.DocLocation.LocalFile "patterns/cli/option-groups.md"
        }
      , Schema.DocRef::{ key = "cli-command-aliases"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Command aliases pattern via config file pre-parse expansion"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/command-aliases.md"
        }
      , Schema.DocRef::{ key = "cli-command-aliases-kdl"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Command aliases pattern using a KDL config block decoded with KDL.remainingNodesWith"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/command-aliases-kdl.md"
        }
      , Schema.DocRef::{ key = "cli-agent-assist-commands"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Agent assist commands pattern for providing live project context to AI coding assistants"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/agents/agent-assist-commands.md"
        }
      , Schema.DocRef::{ key = "cli-per-command-agent-config"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Per-command agent configuration: resolve an AI agent's provider, model, and reasoning effort per subcommand through one hierarchical, provenance-tracked precedence chain (CLI flag > env > local per-command > local default > global per-command > global default > built-in), with a read-only `agent config` inspection command; a candidate-list resolver that makes each new dial additive; and how Baikai's provider-neutral ThinkingLevel plus its single effort/thinking fields absorb every per-vendor translation so a new knob costs an afternoon"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/agents/per-command-agent-config.md"
        }
      , Schema.DocRef::{ key = "core-record-patterns"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Record definition and manipulation patterns using Generic Lens with #label syntax"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/core/record-patterns.md"
        }
      , Schema.DocRef::{ key = "core-custom-prelude"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Custom prelude pattern for centralizing common re-exports and project-wide utilities"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/core/custom-prelude.md"
        }
      , Schema.DocRef::{ key = "core-multiline-strings"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Multiline string literals with automatic indentation stripping using GHC 9.12 MultilineStrings extension"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/core/multiline-strings.md"
        }
      , Schema.DocRef::{ key = "cli-skill-and-agent-registry"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Distributable skill and agent registry pattern for installing AI skills and subagents from a GitHub repository"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/agents/skill-and-agent-registry.md"
        }
      , Schema.DocRef::{ key = "cli-hierarchical-config"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Hierarchical config pattern with layered Dhall files, precedence-based discovery, and per-layer validation"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/hierarchical-config.md"
        }
      , Schema.DocRef::{ key = "cli-copy-to-clipboard"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Opt-in --copy flag pattern for copying a command's primary output to the system clipboard via pbcopy/xclip"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/copy-to-clipboard.md"
        }
      , Schema.DocRef::{ key = "cli-help-width"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Terminal-aware --width flag for help-topic output: ioctl-based auto-detect with a readability cap, byte-stable verbatim output when piped, indent-aware paragraph wrap, and parser-shape pitfalls that break the FZF picker path"
        , location =
            Schema.DocLocation.LocalFile "patterns/cli/help-width.md"
        }
      , Schema.DocRef::{ key = "cli-claude-cli-pitfalls"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.User
        , description = Some
            "Pitfalls when invoking the `claude` CLI as a subprocess from a Haskell CLI: the variadic --add-dir greedily eats the positional prompt without a `--` terminator (errors on short prompts, hangs on large ones); fix, stdin alternative, and a contract test to catch regressions"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/cli/agents/claude-cli-pitfalls.md"
        }
      , Schema.DocRef::{ key = "core-standards"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Baseline Haskell standards: minimum GHC 9.12, GHC2024 language edition, and the mandatory default-extensions (DeriveAnyClass, DuplicateRecordFields, OverloadedLabels, OverloadedStrings) every package must enable"
        , location =
            Schema.DocLocation.LocalFile "patterns/core/standards.md"
        }
      , Schema.DocRef::{ key = "api-servant-routes"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Servant API design: organize modules as vertical slices per domain aggregate (layer is the leaf of the module path, never the root) and use a NamedRoutes record -- not a positional :<|> chain -- so each aggregate owns its own route and handler records and several may share a URL prefix; plus MultiVerb response lists that declare each operation's error statuses, with a hand-written AsUnion instance and its exhaustiveness witness"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/servant-routes.md"
        }
      , Schema.DocRef::{ key = "api-openapi-from-types"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Derive the OpenAPI 3.1 document from the servant route types with toOpenApi and never hand-write or hand-edit openapi.json; use one compatible released openapi-hs/servant-openapi-hs cohort because openapi3/servant-openapi3 carry no HasOpenApi instance for MultiVerb so a MultiVerb API cannot derive a document from them at all; emit the artifact from an executable, check it in, and enforce it in CI with git diff --exit-code"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/openapi-from-types.md"
        }
      , Schema.DocRef::{ key = "api-rfc9457-problem-details"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "RFC 9457 (obsoletes RFC 7807, identical wire format) problem details as the one error-body shape fleet-wide, served as application/problem+json: type pinned to about:blank, stable title per code, status/detail, plus code and retryable extension members clients branch on; a ProblemJSON content type with RespondAs for MultiVerb APIs, a single problemError renderer plus ProblemSpec catalog for ServerError-style APIs, ErrorFormatters for servant's own rejections (405 needs WAI middleware or an explicit exemption), the OAuth/probe/non-JSON exemptions, and the ToSchema-shares-the-codec-Options rule for the OpenAPI document"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/rfc9457-problem-details.md"
        }
      , Schema.DocRef::{ key = "api-opentelemetry-integration"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "OpenTelemetry 1.0 service integration: bracket the SDK providers, run with -threaded, put WAI instrumentation outside request logging, share its tracer with keiro, and preserve trace context through the transactional outbox"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/opentelemetry-integration.md"
        }
      , Schema.DocRef::{ key = "api-request-logging"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Production WAI request logging as one bounded JSON line with OpenTelemetry trace correlation, explicit health-probe exclusion, and a strict prohibition on bodies, credentials, arbitrary headers, and raw query strings"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/request-logging.md"
        }
      , Schema.DocRef::{ key = "api-relay-pagination"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Relay cursor pagination with typed MultiVerb responses, fingerprinted keyset cursors, trusted SortSpec SQL, explicit OpenAPI cohort compatibility, and a mandatory six-invariant conformance test for every endpoint"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/relay-pagination.md"
        }
      , Schema.DocRef::{ key = "api-health-endpoints"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Kubernetes liveness and readiness semantics for servant services: in-process liveness, dependency and subscription readiness, typed 200/503 status reports, probe-noise logging exclusion, and rollout-time configuration validation"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/health-endpoints.md"
        }
      , Schema.DocRef::{ key = "api-hurl-integration-testing"
        , kind = Schema.DocKind.Cookbook
        , audience = Schema.DocAudience.Module
        , description = Some
            "Black-box API integration testing with Hurl: run resource-family suites against a live Haskell service, keep the default runner safe and explicit, assert stable wire contracts and negative behavior, isolate stateful and specially configured flows, and handle eventual consistency, signatures, secrets, and CI orchestration deliberately"
        , location =
            Schema.DocLocation.LocalFile
              "patterns/api/hurl-integration-testing.md"
        }
      ]
    }
