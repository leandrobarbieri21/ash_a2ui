# 0008. The DSL resolves to one plain struct, and the compile-time verifiers are the only validator

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

ash_a2ui is a Spark DSL extension: `AshA2ui` (`lib/ash_a2ui.ex`, 2,474 lines, almost all
of it option schemas and their docs) adds an `a2ui` section to an Ash resource or, with
`AshA2ui.Standalone`, to a separate UI module. Its output is a wire payload, so a
mistake in the DSL (a field that does not exist, an action that is not an update) becomes a
broken page or a wrong write at runtime. The same vocabulary also has two other writers: an
agent composing a surface at runtime (ADR 0009) and, in the Elixir tests, fixtures.

Three structural decisions follow from that and none was written down.

## Decision

1. **The encoder and the handler never read DSL state.** `AshA2ui.ResolvedView.resolve/2`
   (`lib/ash_a2ui/resolved_view.ex`) is "the normalization seam between the DSL and the
   encoder": it takes the resource or standalone module plus request options and returns a
   plain struct with defaulted fields, effective read/create/update actions, resolved queries
   and loads, and per-table scopes. `AshA2ui.Encoder`, `ActionHandler`, `Manifest` and the
   rest consume that struct. A declared surface, a dynamic one and a manifest therefore
   agree by construction.
2. **Validation is compile-time verifiers, and there is one set.** The 18 modules in
   `lib/ash_a2ui/verifiers/` (`verify_fields`, `verify_actions`, `verify_queries`,
   `verify_contexts`, `verify_relationships`, ...) fail the host's compile with a message
   that lists what *is* available. The handler does not re-validate DSL structure at
   request time; it enforces what only a request can break (ADR 0007). A new DSL option
   ships with its verifier in the same change.
3. **Runtime-composed surfaces run the same verifiers.** `AshA2ui.Dynamic` runs the
   verifier modules "over a synthetic standalone-style DSL state ... the same modules, the
   same messages" (`lib/ash_a2ui/dynamic.ex` moduledoc). There is no second rule set for
   agents. A verifier is written to be shared that way (`verify_calendar.ex` and
   `verify_table_displays.ex` say in their docs that `Dynamic` runs them over every spec).
4. **Transformers are two, and small.** `Transformers.InferFields` fills field metadata
   from Ash attributes and types (`AshA2ui.TypeMapper`); `Transformers.AddRenderAction`
   adds the `render_a2ui` action and runs last (`after?/1` is `true`) so it can see the
   action names that already exist. Behaviour belongs in `ResolvedView` and the encoder,
   not in a transformer, so that the standalone and dynamic paths share it.
5. **The protocol core depends only on `ash` (and Spark).** Everything that needs Phoenix,
   LiveView, Plug or Gettext is behind `Code.ensure_loaded?/1`: `LiveRenderer`, `ActorPlug`,
   `ActorPickerLive`, `PresenceBar`, `Shell.Component`, `Web.ComposerLive`. CI job "mix test
   (without phoenix_live_view)" (`NO_PHOENIX=1`, `mix.exs` `build_path`) proves the core
   compiles and passes without them. A transport is an optional layer over plain
   functions: `Info.build_surface/2` and `ActionHandler.handle/3`.

## Consequences

- A DSL error is a compile error in the host, with the available names in the message.
  That costs compile time (18 verifiers) and makes every DSL option expensive to add: an
  option schema, a verifier, a `ResolvedView` field, an encoder branch, a handler branch and
  a doc. The size of `encoder.ex` (5,600 lines), `action_handler.ex` (3,900) and
  `ash_a2ui.ex` (2,500) is the cost of this.
- The same option has one meaning in a declared surface, a composed one and a manifest.
- `ResolvedView` is the right place to look when a surface and its manifest disagree.
- A plain JSON controller and a LiveView use the same functions. A host on another transport
  (terminal, ACP) needs no change in the core.
- The `NO_PHOENIX` job is the proof that no optional dependency crept into the core. It
  has to stay in CI.

## Reversal

Moving validation to request time would let hosts change a surface without recompiling,
and lose the compile-time guarantee. It is the choice dynamic surfaces already make, with
the verifiers run per resolve (ADR 0009). Do not do it for declared surfaces without a
design for the error messages, which today are the main documentation of the DSL.

## Follow-ups

- The three files over 2,000 lines are the main maintenance risk of the package (health
  score 7.83 at 369 files). Splitting `encoder.ex` along the component kinds it already
  names (table, form, calendar, diagram) is the obvious cut; it needs an ADR because it
  changes where a catalog change lands.
