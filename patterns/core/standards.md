---
type: Standard
title: "Haskell Core Standards"
description: "Baseline GHC, language-edition, extension, import, and record conventions for Haskell projects"
timestamp: 2026-07-24T09:56:04-07:00
resource: mori://shinzui/haskell-jitsurei/docs/core-standards
tags: [core, haskell, ghc-9.12, ghc2024, cabal, standards]
status: current
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: 2026-07-24T09:56:04-07:00
    document_timestamp: 2026-07-24T09:56:04-07:00
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5
---

# Haskell Core Standards

Baseline requirements for every Haskell project in this codebase. These settings are the minimum — projects may add to them, but should not relax them.

## Minimum GHC Version

**GHC 9.12 or newer.**

GHC 9.12 is required because core packages we depend on only support 9.12 (and newer). The standards below also rely on `MultilineStrings`, which shipped in GHC 9.12; the GHC2024 language edition (first available in GHC 9.10) is likewise assumed.

## Cabal Configuration

Every package must use the `GHC2024` language edition and enable the baseline extensions in a `common` stanza:

```cabal
common common
  default-language: GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
    OverloadedStrings
```

All library, executable, test, and benchmark stanzas should `import: common` so the settings apply uniformly.

### Why these extensions are mandatory

- **`DeriveAnyClass`** — required by the explicit `deriving anyclass (...)` strategy used for typeclasses like `FromJSON`/`ToJSON`. This extension is safe as a global default *only because* deriving strategies are always explicit (see [Record Patterns](./record-patterns.md)): with it enabled, a strategy-less `deriving (C)` can silently choose the anyclass path and produce an empty instance for a class without suitable defaults. Never write a strategy-less deriving clause.
- **`DuplicateRecordFields`** — lets multiple records share field names without prefixes. See [Record Patterns](./record-patterns.md).
- **`OverloadedLabels`** — enables the `#fieldName` syntax used with `generic-lens`. See [Record Patterns](./record-patterns.md).
- **`OverloadedStrings`** — required for `Text` literals throughout the codebase.

GHC2024 already provides `DataKinds`, `DerivingStrategies`, `LambdaCase`, and other commonly needed extensions, so they do not need to be listed.

### Adding more extensions

Projects may add more extensions to the `common` stanza when justified by a documented pattern — for example, `MultilineStrings` per [Multiline String Literals](./multiline-strings.md), or `PackageImports` per [Custom Prelude Pattern](./custom-prelude.md).

## Import Style

**Qualified imports must use postpositive `qualified` syntax.** GHC2024 includes `ImportQualifiedPost`, so this is available everywhere without an extra extension.

```haskell
-- CORRECT: postpositive
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text

-- WRONG: prepositive
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
```

Postpositive `qualified` keeps the module name in the same column as unqualified imports, which makes import blocks easier to scan and sort.

## Related Patterns

For conventions that build on this baseline:

- [Record Patterns](./record-patterns.md) — defining and updating records with `generic-lens` and the `#label` syntax.
- [Custom Prelude Pattern](./custom-prelude.md) — centralizing common imports in a `<Project>.Prelude` module.
- [Multiline String Literals](./multiline-strings.md) — using the `MultilineStrings` extension for embedded SQL, HTML, and JSON.
