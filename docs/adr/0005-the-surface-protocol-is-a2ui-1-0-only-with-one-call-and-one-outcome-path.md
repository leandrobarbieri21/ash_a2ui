# 0005. The surface protocol: A2UI 1.0 only, one inline surface, one call path, one outcome map

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

A2UI is a young protocol. Version 0.9 had `event` actions with no response, several
reserved response paths and a streamed surface. 1.0 changed envelopes (`@path`, `@call`,
`@catalogId`), made actions fire-and-forget, and added function calls as the correlated
channel. A server that emits two versions needs a version switch through the encoder,
handler and catalogs, and every test has to run twice. The package was on 0.9 on `main`
until the 1.0 re-vendor (`documentation/topics/a2ui-1-0.md`).

Two hosts depend on the wire shape, so a loose protocol is an expensive thing to be wrong
about. And the protocol has to say how a user learns whether a click worked, which 1.0 does
not answer for actions.

## Decision

1. **ash_a2ui speaks 1.0 only. There is no version option.** A new protocol version is a
   re-vendor of the schemas and one change to the encoder (`AGENTS.md`,
   `lib/ash_a2ui/encoder.ex`). The version string is the bare `"1.0"`.
2. **The vendored 1.0 JSON Schemas are the executable spec.** `priv/a2ui/v1_0/json/`,
   `catalogs/basic/v1/catalog.json` and the upstream test cases are copied verbatim at a pin
   (`priv/a2ui/v1_0/NOTES.md`: commit `8bf644a`, 2026-11-12). `test/v1_0_conformance_test.exs`
   runs the upstream corpus; the suite validates every message the encoder and the handler
   emit through `AshA2ui.Test.SchemaHelper` (JSV, draft 2020-12, never the network). The
   one non-upstream file, `catalogs/ash_a2ui/catalog.json`, is marked so in `NOTES.md`.
3. **A surface is one inline `createSurface`** carrying the component list and the initial
   data model (`AshA2ui.Encoder.encode_surface/3`). One payload paints a surface, so an
   HTTP response or an agent tool result is self-contained. Data-only refreshes are one
   `updateDataModel` (`encode_data_model/3`).
4. **Every server-handled interaction is one function call: `ashAction`** of the ash_a2ui
   catalog. The renderer sends `callAgentFunction`; `AshA2ui.ActionHandler.handle/3`
   (`lib/ash_a2ui/action_handler.ex`) answers with data-model writes ending in one
   `agentFunctionResponse` carrying the same `functionCallId`. A plain `action` message is
   refused (`UNKNOWN_FUNCTION`), and the encoder never emits `event` actions. The
   renderer has one way to drive a surface.
5. **Every outcome goes to one reserved map, `/ui/feedback`, written whole in one
   `updateDataModel`** (`AshA2ui.Experience.feedback/3`, `lib/ash_a2ui/experience.ex`). Never
   a sub-path, so a stale `pending` cannot outlive a settled write. Field errors stay at
   `/errors/<field>`. The shipped hook adds the optimistic `pending` locally and a slow
   notice after `actionTimeoutMs` (ADR 0006).
6. **A "quiet" set of actions reports no outcome**
   (`AshA2ui.ActionHandler.quiet_actions/0`: `query`, `option_search`, `context_search`,
   `option_select`, `nested_add`, `nested_remove`, `bulk_select`, `prompt`, `wizard_next`,
   `wizard_back`, `open_surface`). A page turn or a keystroke never replaces the last
   outcome. The set exists in Elixir and in JS and is kept equal by a test.
7. **Reserved data-model state lives under `/ui`, and the generated ids and names are ASCII
   snake_case**, a subset of the UAX #31 identifiers the catalog schema requires.
   `AshA2ui.Experience.initial_ui_state/1` writes `/ui/intent`, `/ui/panel`,
   `/ui/feedback` and `/ui/feedback_text`.

## Consequences

- One encoder path, one handler path and one catalog vocabulary. A protocol change shows up
  as a failing schema test, not as a browser report.
- A host on a renderer that implements an older draft cannot use the package. The README
  says the first release waits for the `@a2ui/lit` and `@a2ui/web_core` release that
  implements the 1.0 text.
- The browser, not the server, can see latency. The 0-RTT `pending` write is a hook
  feature, so a non-browser renderer must implement it itself or show no pending state.
- The test suite is the proof. What it does not prove is a published renderer drawing the
  output (`documentation/topics/a2ui-1-0.md`, "What is verified").
- Wire changes in the `/ui` region are breaking for hosts that read them. They follow the
  catalog rules in ADR 0004.

## Reversal

Support a second protocol version by introducing the version option and a second encoder
module. That is a large change (the encoder is 5,600 lines and the handler 3,800) and is the
reason this ADR says no. Prefer a major release that drops the old version.
