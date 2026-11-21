# 0003. The ADR baseline for Ash extensions: a threshold rule, and ADRs over DESIGN.md

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

The first-party Ash extensions keep their decision records unevenly:

- `ash_enterprise` keeps 70 ADRs in `docs/adr/` (format in its `docs/adr/README.md`:
  status, date, context, decision, consequences, reversal).
- `ash_a2ui` had one ADR (0001, catalogs) for a package of 83 modules in `lib/`, a
  Spark DSL with 18 verifiers (`lib/ash_a2ui/verifiers/`), two shipped JS catalogs and a
  vendored protocol (`priv/`). It is the shared UI substrate of both flagship hosts.
  Decisions such as "protocol 1.0 only" lived in `AGENTS.md`, moduledocs and `notes/`.
- `ash_bpmn` keeps a 769-line `DESIGN.md` at its root, headed "the binding contract ...
  where code and this file disagree, this file wins until it is amended". It has no
  `docs/adr/`.
- `ash_strangler` has neither. At the time of writing its design lives in
  `documentation/topics/` (checked 2026-11-14: no `DESIGN.md` at HEAD or in history, so
  the second `DESIGN.md` the ticket assumed does not exist).

Two questions have no written answer: which extensions owe ADRs, and where a decision
goes (ADR or `DESIGN.md`).

## Decision

### 1. The threshold rule

An extension **keeps ADRs** (`docs/adr/`, numbered, in this format) if it has either:

1. **a Spark DSL surface**: a section, entity or verifier a host writes against. Its
   shape is a contract hosts compile against, and changing it breaks them; or
2. **its own persistence or registry**: tables or resources it owns, a catalog,
   a registry a host fills in, or a wire format it defines.

An extension with neither, a **leaf utility** (a calculation, a type, a change, a helper
module a host calls), keeps **README + `usage-rules.md` only**. A decision in a leaf
that deserves a record goes in the README under a "Why" heading, or becomes an ADR the day
the extension crosses the threshold.

Crossing the threshold is the event that creates `docs/adr/`. Doing it late is allowed;
the first ADR set is then written from the code, as this one is for `ash_a2ui`.

### 2. ADR, not DESIGN.md

The one convention going forward is **ADRs in `docs/adr/`**. A `DESIGN.md` mixes three
things with different lifetimes: decisions (permanent), a build plan (done once built)
and a description of the code (stale on the next commit). An ADR has a status, a date
and a reversal, so a reader can tell whether it still binds.

What happens to existing `DESIGN.md` files:

- **`ash_bpmn/DESIGN.md`** is **frozen**, not deleted. It is the record of what the
  implementation lanes agreed, and 769 lines of it is real design. Its first lines gain a
  note that it is superseded as the place for *new* decisions by `docs/adr/`. Each
  decision in it that is still load-bearing is lifted into an ADR when `ash_bpmn` is next
  touched for that area, citing the section. The file is deleted only once every section
  is either lifted or marked as description. The "this file wins over code" rule is
  dropped: an ADR does not out-rank passing tests.
- **`ash_strangler`** has no `DESIGN.md`; nothing to migrate. It crosses both threshold
  conditions (a DSL surface and its own change ledger and extension stores), so it owes an
  ADR set.
- A **new** extension never starts a `DESIGN.md`.

### 3. Where this is recorded

This ADR lives in `ash_a2ui`, the first extension to adopt the baseline, and
`ash_a2ui/README.md` points here. Other extensions adopt the rule by linking it from their
own README. The rule is not copied into each repository, so there is one text to amend.

## Consequences

- Extensions over the threshold need an ADR set. For `ash_a2ui` that is ADRs 0001,
  0002 and 0004-0009. For `ash_bpmn` and `ash_strangler` it is follow-up work, not done here.
- A reviewer has a test to apply to a PR: does this change a DSL shape, a persisted
  shape, a catalog or a wire format? Then it needs an ADR or an amendment.
- Leaf utilities carry no ADR overhead.
- `ash_bpmn` carries two places for design until `DESIGN.md` is fully lifted. The freeze
  note limits that to a read-only one.

## Not decided here

- The ADR number sequence is per repository. A shared ecosystem ADR is one that lives in
  `ash_enterprise` (`docs/adr/`), which this ADR is not.
- Whether `ash_bpmn`'s and `ash_strangler`'s ADR sets are written one at a time or in a
  batch.
