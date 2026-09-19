-- The reusable taxonomy comes from the authoritative okf-profiles release.
-- This wrapper gives the consumed profile a repository-specific name without
-- forking its field requirements, type vocabulary, or path rules.
let profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.18.0/package.dhall
        sha256:7d3a4a22be12fd0e697d6012ed1eb2efe4cb5dc4700d08fd49aa5e4c0e523df8

in  profiles.documentation.patternCatalog
  with name = "haskell-jitsurei-pattern-catalog"
