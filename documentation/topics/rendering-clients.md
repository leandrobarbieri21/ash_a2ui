# Rendering Clients

AshA2ui's protocol core produces plain maps (A2UI v0.9.1 messages, string
camelCase keys, ready for JSON encoding) and consumes plain maps (client
`action` envelopes). *How* those maps travel between your server and a
renderer is the transport's job. This guide covers the two supported
transports and the browser-side renderers.

## The message contract (both directions)

Server → client, in order on first render:

| Message | Purpose |
|---|---|
| `createSurface` | Announce the surface (`surfaceId`, `catalogId`) |
| `updateComponents` | The full component list (one component has id `"root"`) |
| `updateDataModel` | The data the components bind to (records, form state) |
| `deleteSurface` | Tear the surface down (supported by the encoder; rarely needed) |

Data-only refreshes are a single `updateDataModel` message
(`AshA2ui.Info.build_data_model/2`).

Client → server is one envelope shape:

```json
{
  "version": "v0.9.1",
  "action": {
    "name": "submit_form",
    "surfaceId": "tickets",
    "sourceComponentId": "form_submit",
    "timestamp": "2026-07-10T12:00:00Z",
    "context": { "...": "resolved data bindings" }
  }
}
```

The core `action.name` values AshA2ui emits and accepts are `"submit_form"`,
`"invoke"` (generic/row actions), `"prompt"`, `"query"` and the task-panel
actions `"start_create"`, `"view_record"`, `"start_edit"` and
`"cancel_record_task"`; feature-specific names exist only where a surface
declares the feature. See
[Actions and Authorization](actions-and-authorization.md).

## Transport 1: `AshA2ui.LiveRenderer` (LiveView)

The batteries-included option when your renderer host is a Phoenix app.
Requires the optional `phoenix_live_view` dependency (the module simply isn't
compiled without it).

```elixir
defmodule MyAppWeb.TicketA2uiLive do
  use AshA2ui.LiveRenderer,
    ui: MyApp.UI.TicketUI,
    actor_fn: & &1.assigns.current_user
end
```

What it does:

- **mount** — derives the actor via `:actor_fn`, calls
  `AshA2ui.Info.build_surface/2`, and pushes the messages to the JS hook via
  `push_event`. If the resource has `Ash.Notifier.PubSub` configured, it also
  subscribes to the relevant topics.
- **`"a2ui:action"` events** — incoming client envelopes are routed through
  `AshA2ui.ActionHandler.handle/3` with the mounted actor; follow-up messages
  (refreshes, error payloads) are pushed back to the hook.
- **PubSub notifications** — on record changes, it pushes a
  `AshA2ui.Info.build_data_model/2` refresh, so every mounted client stays
  live. Rapid notification bursts are debounced; the refresh is
  whole-data-model in v0 (targeted region refreshes are on the roadmap).

All callbacks are `defoverridable`, so you can layer custom behavior on top
of the generated LiveView when needed.

### The hook contract

The package ships the LiveView JS hook at `priv/js/ash_a2ui_hook.js`. It has
**no bundled dependencies** — your app bundle imports the `@a2ui` renderer
packages and hands the renderer classes to the hook via
`configureAshA2ui({MessageProcessor, catalogs})` before the `LiveSocket`
mounts it:

- Import **`@a2ui/lit/v0_9`** for its side effect: registering the
  `<a2ui-surface>` custom element (and to get `basicCatalog`).
- Import **`MessageProcessor` from `@a2ui/web_core/v0_9`** — message ingest
  in the 0.10.x renderers is `new MessageProcessor(catalogs, actionHandler)`
  + `processor.processMessages(messages)`; the `<a2ui-surface>` element
  itself has **no ingest API** (it only accepts a `SurfaceModel` via its
  `surface` property, which the hook wires up through
  `processor.onSurfaceCreated`).
- Register the hook under the name **`AshA2ui`** in your `LiveSocket` hooks.
- The LiveView renders a container `div` with `phx-hook="AshA2ui"` and
  `phx-update="ignore"`; the hook owns everything inside it.
- Server→client messages arrive on the **`"a2ui:messages"`** `push_event`
  (payload `%{messages: [...]}`); the hook feeds them to the processor.
- User interactions are delivered to the processor's action callback and
  forwarded to the server as the **`"a2ui:action"`** LiveView event, wrapped
  in the A2UI v0.9.1 client envelope.
- Reference-link activations (the admin catalog's `openSurface` function,
  raised as the bubbling, composed `"ash-a2ui:open-surface"` DOM event with
  `detail = {surface, recordId?, query?, href?, surfaceId}`) are forwarded
  as the **`"a2ui:open_surface"`** LiveView event with `{surface, recordId,
  query}`; `AshA2ui.LiveRenderer` navigates to its `:open_surface_url` by
  default. Pass `configureAshA2ui({openSurface: (args, {surfaceId, href})
  => …})` (or `createAshAdminCatalog({…, openSurface})`) to handle it
  client-side instead. Hosts that handle hook events themselves (not via
  `AshA2ui.LiveRenderer`) must add a `handle_event("a2ui:open_surface",
  …)` clause.
- Basic-catalog reference links are ordinary `"a2ui:action"` envelopes
  named `"open_surface"` (context `{field, surface, recordId}`).
  `AshA2ui.LiveRenderer` passes them to the action handler and, once the
  handler accepted the field/surface pair, navigates through the same
  `:open_surface` / `:open_surface_url` path. Hosts with their own
  `"a2ui:action"` handling do the same: call the handler, and on `{:ok,
  _}` for an `"open_surface"` action, navigate. The Buttons only render
  when the surface is built with `link_buttons: true`, which the
  LiveRenderer passes when it has `:open_surface` or `:open_surface_url`;
  other hosts pass it once they navigate.

Wiring in `assets/js/app.js` (minimal — see the
[Theming](theming.md) guide for the recommended full setup with the merged
catalog and markdown renderer):

```javascript
import "@a2ui/lit/v0_9"; // registers <a2ui-surface>
import { basicCatalog } from "@a2ui/lit/v0_9";
import { MessageProcessor } from "@a2ui/web_core/v0_9";
import { AshA2ui, configureAshA2ui } from "../../deps/ash_a2ui/priv/js/ash_a2ui_hook.js";

configureAshA2ui({ MessageProcessor, catalogs: [basicCatalog] });

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { AshA2ui },
  params: { _csrf_token: csrfToken },
});
```

(Bundling the hook separately from your app code? Setting
`globalThis.__ASH_A2UI_DEPS__ = {MessageProcessor, catalogs}` works as an
alternative to calling `configureAshA2ui`.)

`configureAshA2ui` also accepts an optional `markdown` entry
(`{ContextProvider, context, render}`) that wires a markdown renderer into
the surface — without it, Text headings render as literal `## ...`
markdown. The package additionally ships a neutral CSS-variable theme
(`priv/js/ash_a2ui_theme.css`) and a merged component catalog
(`priv/js/ash_a2ui_catalog.js`) whose ChoicePicker is a native `<select>`
and whose Column upgrades AshA2ui's search-picker composites to a
typeahead combobox with an anchored results overlay. All three are covered
in [Theming](theming.md).

## Transport 2: plain JSON endpoints

The protocol core is transport-agnostic — a read-only surface is one
controller action:

```elixir
defmodule MyAppWeb.A2uiController do
  use MyAppWeb, :controller

  def tickets(conn, _params) do
    messages =
      AshA2ui.Info.build_surface(MyApp.UI.TicketUI,
        actor: conn.assigns.current_user
      )

    json(conn, messages)
  end
end
```

For mutations, accept the client `action` envelope on a POST endpoint and
hand it to the handler:

```elixir
def action(conn, envelope) do
  case AshA2ui.ActionHandler.handle(MyApp.UI.TicketUI, envelope,
         actor: conn.assigns.current_user
       ) do
    {:ok, messages} -> json(conn, messages)
    {:error, messages} -> conn |> put_status(422) |> json(messages)
  end
end
```

Both branches return valid server→client A2UI messages — the error branch
carries validation errors on the reserved `/errors/<field>` data-model paths
(see [Data Model Conventions](data-model-conventions.md)), so the renderer
treats them like any other data update.

JSON endpoints don't get PubSub live refresh (there's no persistent
connection); pair them with polling or use the LiveView transport when you
need liveness. For serving surfaces to AG-UI clients (CopilotKit chat UIs
and other external consumers) over SSE, see
[External Transports](external-transports.md); raw WebSocket remains
roadmap.

## Browser renderers: `@a2ui/lit` and `@a2ui/react`

The published renderer packages are **0.10.x** and expose **`/v0_9` entry
points** compatible with the v0.9.x protocol AshA2ui emits:

- [`@a2ui/lit`](https://www.npmjs.com/package/@a2ui/lit) — web components;
  the `<a2ui-surface>` element renders a surface from a message feed. This is
  what the shipped hook targets, and works in any framework (or none).
- [`@a2ui/react`](https://www.npmjs.com/package/@a2ui/react) — React
  bindings, useful when the consuming client is a React app talking to the
  JSON transport.

Notes:

- Check each package's README for the exact `/v0_9` import path in the
  version you install — the packages version independently from the spec.
- `@a2ui/lit`'s `A2uiController` class is only needed for registering
  *custom* components; plain embedding is `<a2ui-surface>` plus the message
  feed.
- AshA2ui emits the **basic catalog** (`Text`, `TextField`, `CheckBox`,
  `ChoicePicker`, `DateTimeInput`, `Button`, `List`, `Row`, `Column`, `Card`,
  ...). Tables are `List` templated over Card-wrapped `Row`s of labeled
  cells — the basic catalog has no Table component.
- Styling is CSS-custom-property driven (the components render in shadow
  DOM), and the package ships a starter theme plus a merged catalog with a
  `<select>`-based ChoicePicker — see [Theming](theming.md).

Anything else that speaks A2UI v0.9.x — including agent canvases that accept
A2UI surfaces — can consume the same messages without changes on the server.
