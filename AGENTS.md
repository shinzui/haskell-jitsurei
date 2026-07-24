# Agent instructions

## Dependency lookup

Always use Mori to locate dependency source and documentation before relying on
memory. Verify released versions against the authoritative package registry and
upstream tags before choosing bounds, pins, or workarounds. Never traverse
`/nix/store` or the filesystem root.

## Pattern catalog

Before guessing which document contains a convention, discover the registered
bundle and concepts:

```sh
mori registry bundles shinzui/haskell-jitsurei
mori registry concepts shinzui/haskell-jitsurei --bundle patterns
```

Use `okf show patterns <concept-id>` for focused context. Concept IDs are
bundle-relative paths without `.md`, such as `api/servant-routes`. Start broad
tasks with `patterns/getting-started.md`.

When materially changing a concept under `patterns/`:

1. Update its RFC 3339 `timestamp`.
2. Preserve old `reviews` entries and add a record only after an actual review.
3. Add a concise entry to the nearest enclosing `log.md`.
4. Regenerate indexes with `okf index patterns --write`.
5. Run `mori validate`.
6. Run `okf validate patterns --strict --profile okf/patterns.dhall
   --profile-enforce --log-enforce`.
7. Run `scripts/review-status --check`.

Review entries follow `patterns/governance/review-policy.md`. A model review
must record provider and model; a human review must record a durable human
identity. Never record authorship, migration, or automated validation as a
review. Always record scope so a metadata review cannot be read as technical
approval.

Generated `index.md` files are owned by OKF and must not be edited by hand.

## Git

Use Conventional Commits. Commit directly to the current branch unless the user
explicitly requests a feature branch.
