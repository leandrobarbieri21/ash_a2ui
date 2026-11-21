# 0006. The JS/Elixir boundary: the server decides meaning, the browser draws, and shared constants are pinned by tests

- Status: proposed
- Date: 2026-11-14
- Plane: AST-187

## Context

The package is half Elixir (83 modules in `lib/`) and half JavaScript (`priv/js/`: the
LiveView hook, two Lit catalogs of about 5,300 and 2,400 lines, a canvas, a shell hook).
The JS cannot be a build product: hosts bundle it, so the package ships source ES modules
for the host's bundler. The Elixir build runs no JS toolchain (`mix js.test` is a separate
alias that calls `node`), and the library must compile without Phoenix (CI job `NO_PHOENIX`, `mix.exs`
`build_path`).

Three decisions had no home:

- what the browser may decide, versus what only the server may;
- which dependencies the shipped JS may import;
- how a value that both sides need (a catalog id, a list of action names) stays equal.

## Decision

1. **The server decides, the browser draws.** Every meaning, including what a button does,
   which rows a user may see, whether a record may be edited, comes from the server as props
   and data-model values. The shipped elements do not hold business logic, and a host swap
   of a stock element (ADR 0001 section 6) is safe because it draws and never carries
   meaning. A prop a renderer does not know must be safe to ignore (ADR 0001 section 8).
   The exceptions are presentation state the server cannot know: the optimistic `pending`
   write to `/ui/feedback`, the slow notice after `actionTimeoutMs`, the `/ui/loading`
   flag, focus and scroll of an opening panel (`priv/js/ash_a2ui_hook.js`).
2. **The JS is split into a pure contract and a side-effecting shell.**
   `priv/js/ash_a2ui_protocol.js` holds the A2UI 1.0 contract with "no DOM or LiveView
   access": the protocol version, the ash_a2ui catalog id and function, the feedback map,
   the quiet actions, `replaceExistingSurfaces`, `panelStateOf`. `ash_a2ui_hook.js` runs
   the effects around it. The pure half is tested with `node --test` (`mix js.test`,
   `test/js/*.test.mjs`, a separate CI job).
3. **The shipped JS imports nothing from the host's world.** `@a2ui/lit`, `@a2ui/web_core`
   and Lit are the host's dependencies, passed in (`configureAshA2ui({MessageProcessor,
   Catalog, catalogs})`, `create<Name>Catalog(deps)`), so one copy of each runs in the page
   (ADR 0001 section 1). `priv/js/package.json` is `{"type": "module"}` and nothing more.
   The hook is written against `@a2ui/lit` and `@a2ui/web_core` 0.15.0, the version
   `mix js.test` pins, with a known gap (the `@`-prefixed envelope keys) closed by the next
   `web_core` release.
4. **One message crosses the LiveView socket in each direction.** Server to browser:
   `"a2ui:messages"` (a list of agent-to-renderer messages). Browser to server:
   `"a2ui:message"`, one renderer-to-agent message verbatim, with any top-level key that
   starts with `_` dropped as the transport's (`AshA2ui.ActionHandler.drop_transport_keys/1`).
   `AshA2ui.LiveRenderer` is the only Elixir module that knows the event names;
   `lib/ash_a2ui/live_renderer.ex` is guarded by `Code.ensure_loaded?(Phoenix.LiveView)` and
   `AshA2ui.ActorPlug` by `Plug.Conn`, so the protocol core is Phoenix-free.
5. **A value both sides need exists once as a literal in each, and a test pins them.**
   - The quiet-action list: `QUIET_ACTIONS` in `ash_a2ui_protocol.js` against
     `ActionHandler.quiet_actions/0` (`test/renderer_messages_test.exs`, regex over the JS).
   - The admin catalog version: ADR 0004.
   - The catalog id: `ASH_A2UI_CATALOG_ID` against `AshA2ui.Encoder.ash_catalog_id/0`. This
     one is **not** pinned by a direct test: the JS tests build calls from the constant, and
     the handler answers a call under another id with `UNKNOWN_FUNCTION`, so a mismatch fails
     only end to end. See the follow-up.
   - Key bindings: `AshA2ui.Shell.keys/0` is the only table; the JS hook reads it from the
     component's data, so there is no second copy in the browser.
6. **Hosts register hooks with `priv/js/hooks.js`** (lazy `load`, with the events to
   subscribe to). `AshA2ui` and `AshA2uiShell` are imported directly, since they need
   `configureAshA2ui` first.

## Consequences

- The Elixir suite proves the wire. The JS suite proves the hook's logic with `node --test`.
  Neither proves a browser rendering the output on a published release
  (`documentation/topics/a2ui-1-0.md`, "What is verified"). That gap is accepted and written
  down, not closed.
- A new renderer (React, a terminal) reuses the protocol and the server, and implements the
  hook's optimistic half itself.
- Duplicated literals are guarded by tests that read source text, and break if the source is
  reformatted. A generator would be better; see ADR 0004 "Reversal".
- A host cannot change what a stock element means, only how it looks.
- The package has no npm release of its own: the JS path is `ash_a2ui/priv/js/...` in a
  host's bundler config. A host that vendors the package pins JS and Elixir together.

## Reversal

Publish the JS as an npm package and make the Elixir side only a dependency of the JS
version. That removes the vendoring path and the source-text tests, and adds a second
release train. It is worth doing when a non-Phoenix host (a terminal or React host that does
not run LiveView) needs the JS without the Elixir.

## Follow-ups

- Add a test that `ASH_A2UI_CATALOG_ID` equals `AshA2ui.Encoder.ash_catalog_id/0` and the
  `catalogId` of `priv/a2ui/v1_0/catalogs/ash_a2ui/catalog.json`.
