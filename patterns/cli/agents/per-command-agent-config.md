---
type: Pattern
title: "Per-Command Agent Configuration"
description: "Resolve provider, model, and reasoning effort per subcommand through one provenance-tracked precedence chain"
timestamp: 2026-10-02T13:18:57Z
generated:
  by: human:nadeem
  at: 2026-07-20T19:23:48Z
resource: mori://shinzui/haskell-jitsurei/docs/cli-per-command-agent-config
tags: [cli, agents, provider, model, reasoning, configuration, baikai]
status: current
---

# Per-Command Agent Configuration (Provider, Model, Reasoning Effort)

**Resolve provider, model, and reasoning effort per command, retain their
provenance, and apply them through [Baikai](mori://shinzui/baikai).**

A CLI that launches AI agents (`mycli agent assist`, `mycli agent run`, …) usually
starts with a single global provider/model pair. Sooner or later a user wants a
*fast, cheap* model for `assist` but a *strong* model for `run`, and to think
harder on some commands than others. This pattern makes each of those knobs
configurable per command, resolved through a precedence chain that a user can
audit at a glance.

It is written config-language-agnostic on purpose: the *keys* and the *resolution
order* are the pattern; whether you store them in Dhall, KDL, TOML, or JSON is an
implementation detail. The Haskell in the Baikai section is concrete because the
API wiring must match the consuming Baikai version. For new fleet CLIs, use
the [Settei CLI standard](mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard)
for loading and source diagnostics. The eight-tier chain below describes a
tool that already exposes project/user defaults and parent/subcommand flags;
retain that chain only when it is the tool's documented contract. Do not add a
second file loader or silently replace Settei's source ordering to copy it.

## Problem

An agent CLI grows a family of subcommands that each launch a model. Three
independent knobs want per-command control:

- **provider** — which integration talks to the model (a local CLI such as
  `claude`/`codex`, or an HTTP API such as Anthropic's or OpenAI's).
- **model** — a provider-compatible model identifier, checked against the current
  [Baikai model catalog](mori://shinzui/baikai/docs/models-and-providers).
- **reasoning effort** — how hard a reasoning-capable model deliberates before
  answering (a coarse dial from `minimal` to `max`).

A single global pair (`agent.provider` + `agent.model`) forces the same choice on
every command. Per-invocation flags work but vanish when the command exits. Users
end up wanting all of:

1. A **shared default** that applies to every command.
2. A **per-command override** that beats the shared default for one command.
3. **Two scopes** — a project-local config that overrides the user's global config.
4. **Env vars** and **flags** on top, for one-off overrides.
5. A way to **see the resolved value and *why*** — which scope, which key, or which
   flag won — without reverse-engineering the precedence rules in their head.

And when you add the *third* knob (effort) after shipping the first two, you do not
want to re-plumb everything.

## The Resolution Model

The whole pattern is one ordered precedence chain per field. Read it top to bottom;
the first source that yields a non-blank value wins.

```text
Precedence, highest first:
  1. --<field> flag on the subcommand         (mycli agent run --model X)
  2. --<field> flag on the parent `agent`      (mycli agent --model X run)
  3. MYCLI_AGENT_<FIELD> environment variable
  4. local   scope   agent.<command>.<field>   ← per-command, project
  5. local   scope   agent.<field>             ← shared default, project
  6. global  scope   agent.<command>.<field>   ← per-command, user
  7. global  scope   agent.<field>             ← shared default, user
  8. built-in default
```

The chain encodes **two orthogonal axes** and one rule for how they interact:

- **Scope** — local (project) versus global (user).
- **Specificity** — per-command key versus the shared default key.

> **The rule: scope dominates *across* scopes; specificity dominates *within* a
> scope.** Any local value beats any global value (tiers 4–5 both precede 6–7).
> Inside one scope, the more specific per-command key beats the shared default
> (tier 4 before 5, tier 6 before 7).

That ordering is the least-surprising reading of "projects override global, and a
per-command setting is a more deliberate statement than the shared default." It is
worth writing down as a decision, because the alternative — specificity dominating
across scopes, so a global per-command key beats a local default — is equally
defensible and quietly different. Pick one and make the inspection command prove it.

### Key shape (any config language)

Two logical keys per field: a shared default and a per-command override.

```text
agent.<field>              # shared default, e.g. agent.model
agent.<command>.<field>    # per-command,   e.g. agent.run.model
```

`<command>` is the command's own token (`assist`, `run`, `prompt-run`); pick a
single hyphenated segment for multi-word commands so the key stays flat. This maps
onto whatever your config format is:

| Config language | Shared default | Per-command override |
|-----------------|----------------|----------------------|
| Flat dotted keys | `agent.model = "…"` | `agent.run.model = "…"` |
| Nested (TOML/YAML) | `[agent] model = "…"` | `[agent.run] model = "…"` |
| Dhall record | `agent.model` field | `agent.run.model`, or a `Map Text Text` of dotted keys |

The resolver below treats config as a flat `Map Text Text` of dotted keys, which is
the lowest common denominator — a nested format just flattens into it on load.

## Implementation

### 1. Enumerate the commands as a closed type

Give the set of agent commands a real type. It is the domain of every key builder,
the argument that selects a per-command candidate, and the thing the inspection
command folds over.

```haskell
data AgentCommandName
  = AgentCmdAssist
  | AgentCmdBootstrap
  | AgentCmdSetup
  | AgentCmdRun
  | AgentCmdPromptRun
  deriving stock (Eq, Show, Enum, Bounded)

-- The token used inside config keys: "assist", "run", "prompt-run".
agentCommandSegment :: AgentCommandName -> Text
agentCommandSegment = \case
  AgentCmdAssist    -> "assist"
  AgentCmdBootstrap -> "bootstrap"
  AgentCmdSetup     -> "setup"
  AgentCmdRun       -> "run"
  AgentCmdPromptRun -> "prompt-run"

allAgentCommands :: [AgentCommandName]
allAgentCommands = [minBound .. maxBound]      -- inspection iterates this

agentModelConfigKey        :: Text
agentModelConfigKey        = "agent.model"
agentCommandModelConfigKey :: AgentCommandName -> Text
agentCommandModelConfigKey c = "agent." <> agentCommandSegment c <> ".model"
```

`Enum`/`Bounded` gives you `allAgentCommands` for free, so the inspection command and
any exhaustiveness check stay correct when you add a command.

### 2. Model provenance, not just the value

Resolution returns *where the value came from*, alongside the value. Provenance is
what turns "here is your model" into "here is your model, and it won because
`agent.run.model` is set in your project config" — the difference between a config
system users trust and one they fight.

```haskell
data AgentConfigSource
  = SourceCliSubcommand      -- --model on the subcommand
  | SourceCliParent          -- --model on `agent`
  | SourceEnv                -- MYCLI_AGENT_MODEL
  | SourceLocalCommand       -- local  agent.<cmd>.<field>
  | SourceLocalDefault       -- local  agent.<field>
  | SourceGlobalCommand      -- global agent.<cmd>.<field>
  | SourceGlobalDefault      -- global agent.<field>
  | SourceBuiltinDefault     -- hard-coded fallback
  deriving stock (Eq, Show)

data ResolvedField a = ResolvedField
  { resolvedValue  :: a
  , resolvedSource :: AgentConfigSource
  }
  deriving stock (Eq, Show)
```

A label function turns a source into the human string the inspection command prints.
Pass the field so it can name the exact winning key:

```haskell
data AgentField = ProviderField | ModelField | EffortField

sourceLabel :: AgentCommandName -> AgentField -> AgentConfigSource -> Text
sourceLabel cmd field = \case
  SourceLocalCommand  -> "local: "  <> commandKey cmd field
  SourceLocalDefault  -> "local: "  <> defaultKey field
  SourceGlobalCommand -> "global: " <> commandKey cmd field
  SourceGlobalDefault -> "global: " <> defaultKey field
  SourceEnv           -> "env: "    <> envVar field
  SourceCliSubcommand -> "--" <> fieldFlag field <> " flag"
  SourceCliParent     -> "--" <> fieldFlag field <> " flag (agent)"
  SourceBuiltinDefault -> "built-in default"
```

### 3. The resolver is a candidate list

Model each field's resolution as an ordered list of `(Maybe Text, AgentConfigSource)`
candidates. Walk it; the first entry whose text is present and non-blank wins,
carrying its source. This is the entire precedence chain expressed as data — and the
reason adding a field later is trivial (step 5).

```haskell
data AgentConfigInputs = AgentConfigInputs
  { cliValue        :: Maybe Text   -- winning flag (subcommand <|> parent)
  , cliFromSub      :: Bool         -- did the subcommand flag win? (labelling)
  , envValue        :: Maybe Text
  , localConfig     :: Map Text Text
  , globalConfig    :: Map Text Text
  }

-- Ordered candidates for one field of one command.
candidates :: AgentCommandName -> AgentField -> AgentConfigInputs -> [(Maybe Text, AgentConfigSource)]
candidates cmd field i =
  [ (i.cliValue, if i.cliFromSub then SourceCliSubcommand else SourceCliParent)
  , (i.envValue, SourceEnv)
  , (Map.lookup (commandKey cmd field) i.localConfig,  SourceLocalCommand)
  , (Map.lookup (defaultKey field)     i.localConfig,  SourceLocalDefault)
  , (Map.lookup (commandKey cmd field) i.globalConfig, SourceGlobalCommand)
  , (Map.lookup (defaultKey field)     i.globalConfig, SourceGlobalDefault)
  ]

-- First non-blank candidate wins; treat "  " as absent.
resolve :: [(Maybe Text, AgentConfigSource)] -> Maybe (Text, AgentConfigSource)
resolve = listToMaybe . mapMaybe keepNonBlank
  where
    keepNonBlank (mv, src) = case T.strip <$> mv of
      Just v | not (T.null v) -> Just (v, src)
      _                       -> Nothing
```

The per-field resolvers differ only in their built-in default and in how they parse
the winning text:

- **provider** parses to a closed enum; a bad value is a hard error listing the valid
  set. Built-in default: your baseline provider (`claude-cli`), `SourceBuiltinDefault`.
- **model** is free text; built-in default may be `Nothing` (let the provider pick) or
  a value pinned *per provider* if you need determinism (see Design Decisions).
- **effort** parses to Baikai's `ThinkingLevel` (next section); built-in default
  `Nothing`.

Keep any pre-existing flat resolver as a thin adapter over the same walker with the
per-command tiers omitted, so old callers and their tests are byte-for-byte unchanged.
The new tiers are purely additive: a config with no per-command keys collapses to the
old chain.

### 4. A provenance-aware inspection command

Add a read-only command — `mycli agent config` — that resolves *every* command with
no flags and prints each value with its source label. This is the payoff of tracking
provenance and the fastest way for a user (or you, debugging) to answer "why this
model?"

```text
$ mycli agent config
  run          provider  claude-cli       [built-in default]
               model     <claude-model>  [local: agent.run.model]
               effort    max              [local: agent.run.effort]
  assist       provider  codex-cli        [global: agent.assist.provider]
               model     <codex-model>       [global: agent.assist.model]
               effort    high             [global: agent.effort]
  …
Precedence, highest first:
  1. --<field> flag on the subcommand   … 8. built-in default
```

Make the formatter a pure function of the resolved list so it is unit-testable
without touching disk, and print the precedence legend underneath so the rules live
next to the output that obeys them. Iterate `allAgentCommands` to build the rows —
adding a command extends the table automatically.

### 5. Adding a field is additive — effort as the worked example

Because resolution is a candidate list keyed by an `AgentField`, a *new* configurable
dial is a bounded, mechanical change. Reasoning effort went in without touching the
precedence logic at all:

1. Add `EffortField` to `AgentField` and the two key builders
   (`agent.effort`, `agent.<command>.effort`) plus the env var.
2. Add an `effort` candidate list — *identical shape* to provider/model.
3. Parse the winning text to a level; wire the flag and env var; add a row to the
   inspection command.

No new precedence rules, no new scopes, no re-plumbing. If your fields multiply, the
resolver, the inputs record, and the inspection command each grow by one parallel
case — that regularity is the point.

## Apply resolved values through Baikai

### Parse the shared effort vocabulary

Use the library parser instead of maintaining a second spelling table:

```haskell
import Baikai.ThinkingLevel
import Data.Text qualified as Text

parseEffort :: Text.Text -> Maybe ThinkingLevel
parseEffort = parseThinkingLevel . Text.toLower . Text.strip
```

The six levels are `minimal`, `low`, `medium`, `high`, `xhigh`, and
`max`. Normalize at the application's input boundary; `parseThinkingLevel`
itself accepts the canonical lowercase names. A nonblank invalid value is an
error with provenance, rather than a reason to try a lower-priority source.
If no value is configured, keep `Nothing`.

### Choose the correct request surface

Baikai has three distinct launch contracts:

| Workflow | Request and effort field | Owner |
|---|---|---|
| Terminal session | `InteractiveLaunchRequest.effort` | `Baikai.Interactive` and vendor interactive launchers |
| One returned response, over HTTP or a batch CLI | `Options.thinking` on a `Request` | Core API and provider packages |
| Unattended workspace editing | `AgentRunRequest.effort` | `Baikai.Agent`, vendor command renderers, and `baikai-agent` runner |

Build requests through smart constructors, then set the resolved values. The
core request constructors are abstract in current Baikai; copying old record
definitions into the application does not represent its API.

```haskell
import Baikai.Agent qualified as Agent
import Baikai.Interactive qualified as Interactive
import Baikai.Options qualified as Options

setInteractiveEffort
  :: Maybe ThinkingLevel
  -> Interactive.InteractiveLaunchRequest
  -> Interactive.InteractiveLaunchRequest
setInteractiveEffort level request =
  request { Interactive.effort = level }

setResponseEffort :: Maybe ThinkingLevel -> Options.Options -> Options.Options
setResponseEffort level options =
  options { Options.thinking = level }

setRunEffort
  :: Maybe ThinkingLevel -> Agent.AgentRunRequest -> Agent.AgentRunRequest
setRunEffort level request =
  request { Agent.effort = level }
```

Use `interactiveLaunchRequest`, `emptyOptions`, and `agentRunRequest`
as the starting values on those paths. Model configuration likewise belongs
on the corresponding request, with a compatible provider selected by the
application. HTTP response generation and workspace-editing runs do not share
one process or policy contract.

### Translation is provider- and model-aware

The library owns translation. Claude CLI maps `minimal` to `low`;
Codex renders the canonical name through `model_reasoning_effort`.
Anthropic Messages may use adaptive thinking or a token budget according to
the model's compatibility facts. Native OpenAI paths preserve supported
higher levels, while some compatible endpoints clamp them to `high`.
Unsupported models can drop a requested setting. Do not promise that one
level means the same token budget or wire field on every provider.

`Nothing` expresses no application preference. On CLI launch paths it emits
no effort override; on API paths consult the current model/transport
compatibility rules. It is not an explicit provider `none` value.
Use [model-call evidence](mori://shinzui/baikai/docs/model-call-evidence)
when the workflow must record how a requested setting was translated,
clamped, or dropped.

### Attach kit assets after resolving configuration

Use one `KitConfig` for install and launch. Claude interactive requests get
`agentDirsForSession` in `extraDirs`; Codex launches, including batch
`codex exec`, need `codexSessionArgs` in their extra arguments to expose
tool-only skills. Preserve existing arguments when appending. See
[Skill and Agent Registry](skill-and-agent-registry.md) for the unreleased
0.4 visibility API boundary and the complete adapter.

Provider renderers can refuse an incompatible safety policy before spawn.
Handle render refusal and preserve the selected policy. Keep safety and kit
visibility separate from the provider/model/effort precedence chain.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Scope dominates across scopes; specificity dominates within a scope | "Projects override global" is the explicit requirement; within one file the per-command key is the more deliberate statement. Least-surprising, and worth stating because the inverse is equally coherent. |
| New per-command tiers inserted *around* the existing default tiers | Strictly additive: a config without per-command keys collapses to the pre-existing chain, so every old resolution and its tests are unchanged. |
| Resolve to `(value, source)`, never a bare value | Provenance is what makes `agent config` auditable and turns "why this model?" into a one-line answer. |
| Env vars stay cross-command (no `MYCLI_AGENT_RUN_MODEL`) | Env is already a coarse global override; ten per-command vars bloat the surface for little gain. Per-command control lives in config. |
| Inspection is a *separate* read-only command, not folded into `config set` | The generic config editor is a raw key/value tool with no notion of agent resolution; the inspection view is a distinct, agent-specific *resolution* concern. |
| Effort built-in default = unset (`Nothing`) | Effort is a cost/latency dial the user opts into; forcing a default risks surprise token spend. Contrast: if you need deterministic local-CLI runs, *pin* a model per provider so a session never inherits whatever model the ambient CLI has active. |
| Reasoning effort expressed as Baikai's `ThinkingLevel`, wired into every supported request surface | One vocabulary with provider/model-aware translation; include interactive, response, and unattended paths the tool exposes. |
| Watch out for separate command trees | A command like `prompt run` that lives outside the `agent` group has its own parser, dispatch arm, and handler — thread every new field through it explicitly, and test it, or it silently misses the feature. |

## When to Use

- Your CLI launches AI agents across several subcommands and users want different
  provider/model/effort per command.
- You already have (or can adopt) a two-scope config (project over user) and want the
  agent settings to ride the same hierarchy.
- You expect the set of configurable knobs to grow — the candidate-list resolver keeps
  each addition additive.

## When NOT to Use

- A single global provider/model pair genuinely suffices — don't build an eight-tier
  chain for a knob nobody varies.
- You target exactly one provider and never will — the Baikai leverage (the largest
  time-saving here) doesn't apply, though the resolution/provenance pattern still can.
- Your config has no scope hierarchy and no plan for one; the pattern's value is mostly
  in the local-over-global × per-command-over-default interaction.

## References

- [Baikai interactive launches](mori://shinzui/baikai/docs/interactive-launches)
- [Baikai response providers](mori://shinzui/baikai/docs/cli-providers)
- [Baikai unattended runs](mori://shinzui/baikai/docs/unattended-agent-runs)
- [Baikai model-call evidence](mori://shinzui/baikai/docs/model-call-evidence)
- [Settei CLI configuration](mori://shinzui/keiro-runtime-patterns/docs/config-settei-cli-standard)

Related catalog patterns:
[Agent Assist Commands](agent-assist-commands.md) assembles the launch context;
[Skill and Agent Registry](skill-and-agent-registry.md) supplies installed
assets and session discovery.
