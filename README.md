# Haskell Jitsurei

This repository is a curated catalog of prescriptive Haskell implementation
patterns for humans and coding agents. Start with
[Find the right Haskell pattern](patterns/getting-started.md), or browse the
[generated catalog index](patterns/index.md).

## Discover with OKF and Mori

The Open Knowledge Format bundle is named `patterns`. After registering this
checkout with `mori register --local`, discover concepts without guessing paths:

```sh
mori registry bundles shinzui/haskell-jitsurei
mori registry concepts shinzui/haskell-jitsurei --bundle patterns
okf show patterns api/servant-routes
okf graph patterns --json
```

Descriptions, types, lifecycle status, and tags live with each document. Use
`scripts/review-status` to see which humans and which provider/model pairs have
reviewed the current version of every concept.

## Update contract

When materially changing a concept:

1. update its `timestamp`;
2. preserve old review records and add a new one only after an actual review;
3. add an entry to the nearest `log.md`;
4. regenerate indexes with `okf index patterns --write`;
5. validate with:

   ```sh
   mori validate
   okf validate patterns --strict \
     --profile okf/patterns.dhall --profile-enforce --log-enforce
   scripts/review-status --check
   ```

Generated `index.md` files are owned by OKF and must not be edited by hand. The
full provenance rules live in
[Review and Change Provenance](patterns/governance/review-policy.md).
