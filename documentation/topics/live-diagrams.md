# Live Diagrams

A surface can show a diagram with live markers on its nodes: visits
walking a process, jobs moving through a pipeline, datasets in a lineage
graph. You declare a `diagram` and give it a `source`, a host callback that
returns the mermaid source and the markers for each render. ash_a2ui knows
nothing about what the diagram shows. It places the markers, resolves their
links on the server, and moves them when the data model changes.

## Declaring a diagram

```elixir
defmodule MyApp.UI.FlightUI do
  use AshA2ui.Standalone

  a2ui do
    for_resource MyApp.Scheduling.Appointment

    diagram :flight do
      label "Visits in flight"
      description "Every visit, live."
      source MyApp.FlightDiagram
    end

    component :table do
      fields [:patient_name, :status]
    end
  end
end
```

- `source` is a module implementing `AshA2ui.Diagram.Source`
  (`diagram/1`), or `{module, function, args}`, called as
  `apply(module, function, [context | args])`.
- Diagram names are unique lowercase identifiers. The verifier checks that
  the source exports the callback.
- Diagrams render after the context pickers and before the tables, in
  declaration order.

## The source callback

```elixir
@callback diagram(context) :: {:ok, %{source: String.t(), markers: [marker]}} | {:error, term}
```

`context` carries `:name`, `:surface_id`, `:actor`, `:tenant` and
`:contexts` (the surface's selected context values). The callback runs on
every surface build and every full data-model refresh, as the render's
actor. Read the host's state through its own authorized reads, so an
actor only gets markers they may see.

Each marker is a map:

| Key | Meaning |
|---|---|
| `:node_id` | Required. The mermaid node id the marker sits on. |
| `:label` | Required. Who or what the marker is. |
| `:status` | Required. `:active`, `:executing`, `:waiting`, `:failed` or `:done`. |
| `:initials` | The marker's text. Defaults to the label's initials. |
| `:tone` | `:neutral`, `:info`, `:success`, `:warning`, `:danger` or `:accent`. Defaults by status. |
| `:link` | `{surface_key, record_id}` or `{ResourceModule, record_id}`. |
| `:node_label` | The node's label in the fallback list. Defaults to the node id. |
| `:id` | A stable marker id. Defaults to `<node_id>:<index>`. |

A malformed marker raises `ArgumentError`, because it is a bug in the
source. `{:error, reason}` renders the diagram as unavailable.

### Links

A marker link is resolved on the server, the way reference links are (see
the Relationships topic). The target goes through the configured
`AshA2ui.LinkResolver`, which maps it to a surface key or vetoes it for
this actor. The `href` comes from `config :ash_a2ui, :open_surface_url`.
The client never supplies a link:

- The admin catalog renders a linked marker as an anchor with the
  server's `href`. Activating it hands `{surface, recordId}` to the host
  through `openSurface`, as admin link columns do.
- The basic composition (with `link_buttons: true`) renders the marker's
  label as a link Button that dispatches `"open_surface"` with the diagram
  name. `AshA2ui.ActionHandler` calls the source again as the actor and
  accepts the request only when one of the diagram's markers links to that
  surface.

## Data model

```json
{
  "diagram": {
    "flight": {
      "markers": {
        "review": [{"id": "…", "nodeId": "review", "nodeLabel": "Review",
                    "label": "Ada Lovelace", "initials": "AL",
                    "status": "waiting", "statusLabel": "Waiting", "tone": "warning",
                    "link": {"surface": "appointment", "recordId": "…",
                             "label": "Ada Lovelace", "href": "/appointments/…"}}]
      },
      "nodes": [{"id": "review", "label": "Review", "count": 1, "markers": ["…"]}],
      "error": ""
    }
  }
}
```

`markers` is keyed by node id. `nodes` lists the nodes that hold markers,
in the order their first marker appears. The mermaid source is a static
component prop, not data.

## Rendering

### Admin catalog

Under `config :ash_a2ui, :catalog, :admin_v1` (admin catalog 1.4) a
diagram is a `liveDiagram`:

```json
{"id": "diagram_flight", "component": "liveDiagram", "label": "Visits in flight",
 "source": "flowchart TD\n  …", "markers": {"path": "/diagram/flight/markers"},
 "nodes": {"path": "/diagram/flight/nodes"}, "error": {"path": "/diagram/flight/error"}}
```

The renderer draws the source once with mermaid, using
`securityLevel: "strict"`, and places each marker on the top edge of the
node it names. When the markers change it moves them without drawing the
diagram again.

Status styling uses the BPMN viewer's marker conventions:

| Status | Style |
|---|---|
| `waiting` | dashed and hollow |
| `executing` | pulses (no animation under reduced motion) |
| `active` | solid |
| `failed` | the danger fill |
| `done` | muted |

Tones color the fill and the ink. The pairs are the
`--a2ui-marker-<tone>-background` and `--a2ui-marker-<tone>-color` tokens
in `ash_a2ui_theme.css`, set for light and dark at a contrast of at least
6.9:1. Override a tone with `--ash-admin-diagram-<tone>` and
`--ash-admin-diagram-<tone>-ink`.

### Loading mermaid

Mermaid is several megabytes. The catalog loads it the first time a
diagram is drawn, through the `loadMermaid` dependency of
`createAshAdminCatalog`, and never when no diagram appears.
`priv/js/ash_a2ui_mermaid.js` is the module to load: it is the only file
that imports `mermaid`. The host adds the `mermaid` npm package, like
`lit`, and bundles that file separately from `app.js`:

- **An ESM bundle with code splitting** (`esbuild --format=esm --splitting`):

  ```js
  createAshAdminCatalog({
    // ...the usual deps
    loadMermaid: () => import("../../deps/ash_a2ui/priv/js/ash_a2ui_mermaid.js"),
  })
  ```

- **A classic (IIFE) app.js**: add the file as a second esbuild entry point,
  keep `/assets/*` external, and load it by URL. The entry also publishes
  itself on `window.AshA2uiMermaid`, because an IIFE bundle has no exports:

  ```elixir
  # config/config.exs
  args: ~w(js/app.js ../deps/ash_a2ui/priv/js/ash_a2ui_mermaid.js --bundle
           --target=es2022 --outdir=../priv/static/assets/js --external:/assets/* ...)
  ```

  ```js
  createAshAdminCatalog({
    // ...the usual deps
    loadMermaid: () => import("/assets/js/ash_a2ui_mermaid.js").then(() => window.AshA2uiMermaid),
  })
  ```

Without `loadMermaid`, or when mermaid cannot draw the source, the
`liveDiagram` renders the bound node list instead.

### Basic catalog

The basic composition is a heading, the unavailable message, and a List of
the nodes that hold markers. Each node is a Card with the node label over
its markers (initials, label, status). Any basic-catalog renderer shows it.

## Moving markers

Status changes are plain data-model writes, so whatever refreshes the data
model moves the markers:

- **`AshA2ui.LiveRenderer`** refreshes the full data model on any message
  it receives while `:pubsub` is configured. Subscribe the LiveView to your
  engine's topics, and each broadcast (debounced) calls the source again
  and pushes the new markers.
- **Other transports** call `AshA2ui.Diagram.refresh_messages/2`, which
  returns just the `/diagram/<name>` writes, re-read as the actor.

## Worked example: an AshBpmn.FlightView adapter

ash_a2ui does not depend on ash_bpmn. This adapter is host code. It
combines `AshBpmn.FlightView`'s three APIs: `mermaid/2` for the source,
`token_positions/2` for where the tokens are, and the PubSub topics for
when they move.

```elixir
defmodule MyApp.FlightDiagram do
  @moduledoc "The appointment_visit process with one marker per live token."

  @behaviour AshA2ui.Diagram.Source

  require Ash.Query

  alias MyApp.Scheduling.Appointment

  @impl true
  def diagram(%{actor: actor}) do
    # The host's own read of the latest published definition.
    with {:ok, [definition | _]} <- MyApp.Visits.latest_published_process("appointment_visit"),
         {:ok, source} <- AshBpmn.FlightView.mermaid(definition),
         {:ok, positions} <-
           AshBpmn.FlightView.token_positions(MyApp.Visits, definition: definition, actor: actor) do
      appointments = appointments(positions, actor)
      {:ok, %{source: source, markers: Enum.map(positions, &marker(&1, appointments))}}
    else
      _no_definition_or_graph -> {:error, :no_process}
    end
  end

  # token_positions/2 hands back subject join keys; the host resolves them
  # with one authorized read, as the actor.
  defp appointments(positions, actor) do
    ids = positions |> Enum.map(& &1.subject_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Appointment
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.load(:patient)
    |> Ash.read!(actor: actor)
    |> Map.new(&{&1.id, &1})
  end

  defp marker(position, appointments) do
    appointment = appointments[position.subject_id]

    %{
      id: position.token_id,
      # FlightView's mermaid node ids are the definition's element ids.
      node_id: position.node_id,
      node_label: position.node_name || position.node_id,
      label: (appointment && appointment.patient.name) || "Visit",
      # "active" | "executing" | "waiting": the marker statuses.
      status: position.status,
      link: appointment && {"appointment", appointment.id}
    }
  end
end
```

Wire the refresh to the engine's broadcasts. The LiveView subscribes to the
definition topic when it connects. `:pubsub` is set, so every message it
receives triggers a debounced refresh:

```elixir
defmodule MyAppWeb.FlightLive do
  use MyAppWeb, :live_view

  use AshA2ui.LiveRenderer,
    ui: MyApp.UI.FlightUI,
    actor_fn: &MyAppWeb.Auth.actor/1,
    pubsub: [module: MyApp.PubSub, topics: []]

  def mount(params, session, socket) do
    if connected?(socket) do
      {:ok, [definition | _]} = MyApp.Visits.latest_published_process("appointment_visit")
      AshBpmn.FlightView.subscribe(AshBpmn.FlightView.definition_topic(definition.id))
    end

    super(params, session, socket)
  end
end
```

AshBpmn's broadcasts are a hint, and the source's read is the truth: each
refresh calls `token_positions/2` again. Without PubSub, poll instead. Any
message the LiveView receives is a refresh signal, so a timer it sends
itself works too. Re-arm the timer from an overridden `handle_info/2` that
calls `super`.

An OpenLineage graph adapts the same way. Render the job/dataset graph as
a mermaid flowchart whose node ids are the dataset names, and return one
marker per running or failed run, with `status: :executing` or
`status: :failed`.
