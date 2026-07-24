-- The reusable taxonomy comes from the authoritative okf-profiles release.
-- This wrapper adds repository-specific provenance fields without forking the
-- shared type vocabulary or path rules.
let profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.2.0/package.dhall
        sha256:88441b239d99b3dd1cd3e641c882de1c401849e26504c5d76d3da106436034d6

let base = profiles.documentation.patternCatalog

let frontmatter =
      base.frontmatter
      with required = base.frontmatter.required # [ "reviews" ]

in  base
  with name = "haskell-jitsurei-pattern-catalog"
  with frontmatter = frontmatter
