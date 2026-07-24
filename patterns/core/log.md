# core Update Log

## 2026-07-24
* **Correction**: multiline-strings — the closing delimiter does not set the indentation baseline; the least-indented content line does (whitespace-only lines are excluded from the common-prefix computation, verified against the GHC 9.12 users guide and parser source)
* **Correction**: custom-prelude — `camelTo2` comes from aeson's `Data.Aeson.Types`, not a `Data.Aeson.Casing` module; generic-lens bound raised to `^>=2.3` (2.2 excluded the current 2.3.0.0)
* **Correction**: record-patterns — the keiki `IsLabel` failure mode is instance shadowing that breaks bare-`#name` reads (per keiki's own docs), not overlapping-instance errors; `setOf` import corrected to `Data.Set.Lens`; example imports made postpositive per Core Standards
* **Correction**: record-patterns — all references to the deprecated tan packages removed: Aeson options now come from the project prelude instead of tan-aeson, the `TanES.Decider` framework wiring is gone from the decider example, and legacy Tan naming is dropped from example types
* **Correction**: standards — GHC2024 first shipped in GHC 9.10 (only MultilineStrings is 9.12-specific)
* **Nuance**: standards notes the `DeriveAnyClass` strategy-less-deriving footgun; record-patterns adds the GHC 9.4 `DuplicateRecordFields` selector/update ambiguity rationale for lens preference, clarifies that pattern matching and record construction are not the access anti-pattern, and documents transitive orphan-instance propagation
* **Review**: Recorded model reviews (anthropic/claude-fable-5) for all core concepts after verifying claims against generic-lens, lens, keiki, tan-commons, the GHC users guide, and Hackage
* **Correction**: Removed migration-time metadata approvals; core guidance now remains explicitly unreviewed until an actual review occurs
* **Migration**: Classified the core Haskell guidance and added searchable OKF metadata and review provenance
