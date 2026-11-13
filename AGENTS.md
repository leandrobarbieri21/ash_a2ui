# AGENTS.md

This is `ash_a2ui`, an Ash extension that generates A2UI (Agent to UI)
protocol payloads directly from Ash resources.

## Agent constitution

This repository follows `AGENT_PRINCIPLES.md` v1.5, the agent constitution of
the ai-sdlc platform:
<https://github.com/lukegalea/ai-sdlc/blob/master/AGENT_PRINCIPLES.md>.
That file is the root policy for every agent session here. This file adds the
rules of this repository only. It does not replace or weaken the root policy.
If a rule here contradicts a security rule there, stop and ask a human. The
link opens only for people with access to the ai-sdlc repository. If you cannot
open it, these rules from it still apply:

- Do not approve your own work. A human approves every merge and every release.
- Do not put a secret in a file, a commit, a log, or a prompt.
- Do not publish anything outside this repository without human approval.
- Do not say that work is verified unless a CI result shows it.

## Project guidelines

- The protocol core depends only on `ash`. The pipeline from the DSL to
  `ResolvedView`, the encoder, and `ActionHandler` is transport-agnostic plain
  functions. The LiveView transport is optional.
- The vendored A2UI JSON Schemas in `priv/a2ui/v1_0/` are the executable spec
  (upstream pin in `priv/a2ui/v1_0/NOTES.md`). Every change that produces a
  payload must keep the schema-validation suite green.
- ash_a2ui speaks A2UI 1.0 only. There is no version option and no
  compatibility layer for earlier protocol versions; a new protocol version
  is a re-vendor of the schemas and one change to the encoder.
- `usage-rules.md` and `usage-rules/` are the rules that this package ships to
  the applications that use it. They are not the rules for work in this
  repository.

## Before you finish

CI runs `mix compile --warnings-as-errors` and `mix test`. Run both before
you finish.

## Generated sections

This repository does not run `mix usage_rules.sync` today. If it starts to, the
task adds its own section at the end of this file, between its
`usage-rules-start` and `usage-rules-end` markers. Do not edit text inside
those markers. Keep the rules of this repository above them.
