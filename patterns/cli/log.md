# cli Update Log

## 2026-10-02
* **Removal**: Removed the deprecated hierarchical Dhall configuration pattern; new configuration guidance routes to the Settei CLI standard at `mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard`
* **Removal**: Removed the standalone Claude subprocess workaround; agent-assist-commands now delegates argument construction and prompt separation to Baikai's maintained launchers
* **Rewrite**: skill-and-agent-registry now integrates `mori://shinzui/baikai/packages/baikai-kit` through configuration, parser, engine, and session helpers instead of copying installer code; records the published 0.3.0.0 versus unreleased 0.4.0.0 boundary, visibility, local-edit protection, JSON, ownership, and migration behavior
* **Correction**: Kit guidance follows the current source where its guide differs: status attempts refresh but tolerates offline failure, and upstream hash drift can coexist with a version change
* **Update**: agent-assist-commands and per-command-agent-config now use Baikai's current smart constructors, separate interactive/response/unattended surfaces, model-aware effort translation, render refusals, and required Codex kit session arguments
* **Navigation**: CLI overview routes configuration to Settei and kit integration to the shared package, removing links to deleted patterns

## 2026-09-19
* **Update**: Marked the hierarchical Dhall configuration pattern `deprecated`, the shared profile's term for advice kept only for existing adopters

## 2026-07-24
* **Correction**: Removed migration-time metadata approvals; CLI patterns now remain explicitly unreviewed until an actual review occurs
* **Migration**: Classified the CLI and coding-agent patterns and added searchable OKF metadata and review provenance
