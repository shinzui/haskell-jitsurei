# Haskell Core Standards

Baseline requirements for every Haskell project in this codebase. These settings are the minimum — projects may add to them, but should not relax them.

## Minimum GHC Version

**GHC 9.12 or newer.**

GHC 9.12 is required because core packages we depend on only support 9.12 (and newer). The standards below also rely on features available only in that release, notably `MultilineStrings` and the GHC2024 language edition.

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

- **`DeriveAnyClass`** — required by the explicit `deriving anyclass (...)` strategy used for typeclasses like `FromJSON`/`ToJSON`.
- **`DuplicateRecordFields`** — lets multiple records share field names without prefixes. See [Record Patterns](./record-patterns.md).
- **`OverloadedLabels`** — enables the `#fieldName` syntax used with `generic-lens`. See [Record Patterns](./record-patterns.md).
- **`OverloadedStrings`** — required for `Text` literals throughout the codebase.

GHC2024 already provides `DataKinds`, `DerivingStrategies`, `LambdaCase`, and other commonly needed extensions, so they do not need to be listed.

### Adding more extensions

Projects may add more extensions to the `common` stanza when justified by a documented pattern — for example, `MultilineStrings` per [Multiline String Literals](./multiline-strings.md), or `PackageImports` per [Custom Prelude Pattern](./custom-prelude.md).

## Related Patterns

For conventions that build on this baseline:

- [Record Patterns](./record-patterns.md) — defining and updating records with `generic-lens` and the `#label` syntax.
- [Custom Prelude Pattern](./custom-prelude.md) — centralizing common imports in a `<Project>.Prelude` module.
- [Multiline String Literals](./multiline-strings.md) — using the `MultilineStrings` extension for embedded SQL, HTML, and JSON.
