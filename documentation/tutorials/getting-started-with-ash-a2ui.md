# Get Started with AshA2ui

This tutorial takes you from an existing Ash resource to a live, interactive
UI rendered by [`@a2ui/lit`](https://www.npmjs.com/package/@a2ui/lit) in a
Phoenix app — using the batteries-included LiveView transport. By the end you
will have:

1. Installed AshA2ui
2. Declared an `a2ui` surface for a resource
3. Built the A2UI message stream with `AshA2ui.Info.build_surface/2`
4. Wired up `AshA2ui.LiveRenderer` and the shipped JS hook
5. Handled client actions (form submits, row actions) through Ash actions

It assumes a working Phoenix app with Ash already set up. If you're new to
Ash, start with
[Ash's Get Started guide](https://hexdocs.pm/ash/get-started.html) first.

## Step 1: Install

With [igniter](https://hexdocs.pm/igniter):

```bash
mix igniter.install ash_a2ui
```

This adds the dependency and configures your `.formatter.exs` (adds
`:ash_a2ui` to `import_deps` and ensures the `Spark.Formatter` plugin), so
`mix format` understands the DSL.

Manual alternative — add to `mix.exs`:

```elixir
def deps do
  [
    {:ash_a2ui, "~> 0.1"},
    # required for the LiveView transport used in this tutorial:
    {:phoenix_live_view, "~> 1.0"}
  ]
end
```

and to `.formatter.exs`:

```elixir
[
  import_deps: [:ash_a2ui],
  plugins: [Spark.Formatter]
]
```

`phoenix_live_view` is an *optional* dependency of AshA2ui: the protocol core
works without it (see
[Rendering Clients](../topics/rendering-clients.md) for the plain-JSON
transport). This tutorial uses the LiveView transport, so it must be present —
in a Phoenix app it already is.

## Step 2: Annotate a resource

We'll build a support-ticket admin surface. Add the `AshA2ui` extension and an
`a2ui` block to a resource:

```elixir
defmodule MyApp.Support.Ticket do
  use Ash.Resource,
    domain: MyApp.Support,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshA2ui]

  attributes do
    uuid_primary_key :id
    attribute :subject, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :closed]],
      default: :open

    create_timestamp :inserted_at, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "tickets"

    component :table do
      fields [:subject, :status, :inserted_at]
      read_action :read
      row_actions [:update, :destroy]
    end

    component :form do
      fields [:subject, :status]
      create_action :create
      update_action :update
    end

    field :inserted_at do
      label "Created"
      format :date
    end
  end
end
```

What each part does:

- `surface_id` names the A2UI surface. Omit it and it defaults to the
  underscored resource short name (`"ticket"` here).
- `component :table` renders records from `read_action`. Omit `fields` and
  they're inferred from the resource's public attributes.
- `row_actions` lists the actions rendered as per-row buttons — this is also
  the **allowlist** of actions a client may invoke per row. Nothing outside
  this list is callable through the surface.
- `component :form` renders a create/edit form. Omit `fields` and they're
  inferred from the action's `accept` list.
- `field` blocks hold per-field presentation overrides (`label`, `widget`,
  `order`, `hidden`, `format`), shared by all components of the surface.

Everything you reference is checked at compile time: a typo'd field or a
nonexistent action is a compile error, not a runtime surprise.

Widgets default from attribute types via `AshA2ui.TypeMapper.widget_for/2`
(which takes the Ash type and its constraints) — `:string` → `TextField`,
`:boolean` → `CheckBox`, an `:atom` with `one_of` constraints or an
`Ash.Type.Enum` implementation → `ChoicePicker` (enum options come from the
module's `values/0`, labeled via `label/1` when declared), datetimes →
`DateTimeInput` — and can be overridden per field with `widget`.

Prefer to keep UI metadata out of the domain resource? Put the same block in a
standalone module instead:

```elixir
defmodule MyApp.UI.TicketUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Support.Ticket
    # ... same section as above ...
  end
end
```

Both authoring modes are equivalent; standalone modules are accepted anywhere
a resource is expected below.

## Step 3: Build the surface

Try it in IEx:

```elixir
iex> AshA2ui.Info.build_surface(MyApp.Support.Ticket, actor: some_admin)
[
  %{"version" => "1.0",
    "createSurface" => %{
      "surfaceId" => "tickets",
      "catalogId" => "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json",
      "components" => [...],
      "dataModel" => %{"records" => [...], ...}
    }}
]
```

That one message *is* the UI: any A2UI 1.0 renderer can consume it. Records are loaded through the resource's read action with
`authorize?: true` and your `actor:` — policies apply. There's also
`AshA2ui.Info.build_data_model/2` for data-only refreshes (a single
`updateDataModel` message).

## Step 4: Wire the LiveView transport

### The LiveView

```elixir
defmodule MyAppWeb.TicketA2uiLive do
  use AshA2ui.LiveRenderer,
    ui: MyApp.Support.Ticket,
    actor_fn: & &1.assigns.current_user
end
```

- `:ui` — the resource (or standalone UI module) whose `a2ui` section defines
  the surface.
- `:actor_fn` — a 1-arity function from the socket to the actor, evaluated on
  mount and for every incoming action. Pair it with your existing
  `live_session`/`on_mount` auth so the assign is present.

Add a route inside your authenticated `live_session`:

```elixir
scope "/admin", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :admin, on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}] do
    live "/tickets", TicketA2uiLive
  end
end
```

### The JavaScript side

Install the renderer packages in your assets:

```bash
cd assets && npm install @a2ui/lit @a2ui/web_core
```

Then register the shipped hook and hand it the renderer classes in your app
bundle (`assets/js/app.js`), alongside your existing hooks:

```javascript
// Registers the <a2ui-surface> custom element:
import "@a2ui/lit";
// The protocol message processor, the Catalog class and the basic catalog:
import { Catalog, MessageProcessor } from "@a2ui/web_core";
import { basicCatalog } from "@a2ui/web_core/catalogs/basic/v1";
// The hook shipped inside the ash_a2ui package:
import { AshA2ui, configureAshA2ui } from "../../deps/ash_a2ui/priv/js/ash_a2ui_hook.js";

configureAshA2ui({ MessageProcessor, Catalog, catalogs: [basicCatalog] });

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { AshA2ui /* , ...your other hooks */ },
  params: { _csrf_token: csrfToken },
});
```

> #### Renderer versions {: .info}
>
> AshA2ui emits the A2UI 1.0 protocol, and the `@a2ui/lit` and
> `@a2ui/web_core` root entry points carry its runtime. The surfaces use
> features that the published 0.15.0 release predates (the `@`-prefixed
> component keys, for one), so use a release that implements the pinned
> specification text. [The A2UI 1.0 wire contract](../topics/a2ui-1-0.md#what-the-renderer-must-support)
> lists exactly what to look for.

That's all the client code. The `LiveRenderer` renders a container `div` with
`phx-hook="AshA2ui"`; the hook mounts an `<a2ui-surface>` element inside it,
feeds it every A2UI message the server pushes, and forwards each message
the renderer sends back (`callAgentFunction`, `action`, `rendererFunctionResponse`,
`error`) to the server as the `"a2ui:message"` LiveView event.

Out of the box the basic catalog looks like unstyled browser defaults —
before shipping, follow the [Theming](../topics/theming.md) guide to import
the shipped CSS-variable theme, swap in the merged catalog (native
`<select>`s for single-choice pickers), and wire `@a2ui/markdown-it` so
headings render as headings.

## Step 5: Handle actions

You already did — there's no step 5 code to write.

When a user submits the form or clicks a row button, the renderer sends a
`callAgentFunction` for the `ashAction` function, the hook forwards it as
`"a2ui:message"`, and `AshA2ui.LiveRenderer` routes it through
`AshA2ui.ActionHandler`, which:

1. Validates the action name against what the surface declared
   (`row_actions`, the form's `create_action`/`update_action`) — the DSL is
   the allowlist.
2. Invokes the corresponding Ash action with the mounted actor and
   `authorize?: true`.
3. On success, pushes an `updateDataModel` refresh (and writes the typed
   `/ui/feedback` outcome).
4. On validation errors, pushes the error text onto the reserved
   `/errors/<field>` data-model paths so the renderer can show them inline.
5. Ends its reply with an `agentFunctionResponse` for the call, so the
   renderer knows which click the outcome belongs to.

See [Actions and Authorization](../topics/actions-and-authorization.md) for
the details, and
[Data Model Conventions](../topics/data-model-conventions.md) for the
reserved paths.

### Bonus: live refresh

If the resource has `Ash.Notifier.PubSub` configured (create/update/destroy
topics), the LiveView subscribes on mount and pushes a data-model refresh
whenever records change — open the page in two tabs, create a ticket in one,
and watch the other update.

## Where to go next

- [What is AshA2ui?](../topics/what-is-ash-a2ui.md) — the concept, and when
  *not* to use it
- [Rendering Clients](../topics/rendering-clients.md) — JSON transport,
  the full hook contract, other renderers
- [Actions and Authorization](../topics/actions-and-authorization.md)
- [Data Model Conventions](../topics/data-model-conventions.md)
- [DSL reference](../dsls/DSL-AshA2ui.md)
