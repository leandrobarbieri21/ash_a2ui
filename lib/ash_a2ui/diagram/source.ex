defmodule AshA2ui.Diagram.Source do
  @moduledoc """
  The host side of a `diagram` entity: returns the diagram source and its
  markers for one render.

      defmodule MyApp.FlightDiagram do
        @behaviour AshA2ui.Diagram.Source

        @impl true
        def diagram(%{actor: actor}) do
          {:ok,
           %{
             source: "flowchart TD\\n  start([Start]) --> review[Review]",
             markers: [
               %{node_id: "review", label: "Ada Lovelace", status: :waiting,
                 link: {"appointment", "8f0c…"}}
             ]
           }}
        end
      end

  The callback runs on every surface build and data-model refresh, as the
  render's actor. It returns `{:ok, %{source: source, markers: markers}}`
  (optionally with `nodes: [%{id: id, label: label}]`, the node labels of
  the basic-catalog fallback list), or `{:error, reason}`, which renders
  the diagram as unavailable. See `AshA2ui.Diagram` for the marker shape.

  A diagram's `source` option may instead name `{module, function, args}`,
  called as `apply(module, function, [context | args])`.
  """

  @typedoc """
  The render the callback answers: the diagram's name, the surface id, the
  actor and tenant, and the surface's selected contexts (`%{name => value}`,
  `nil` when unselected).
  """
  @type context :: %{
          name: atom,
          surface_id: String.t(),
          actor: term,
          tenant: term,
          contexts: %{atom => String.t() | nil}
        }

  @typedoc "The callback's answer (see `AshA2ui.Diagram` for `t:AshA2ui.Diagram.marker/0`)."
  @type result :: %{
          required(:source) => String.t(),
          required(:markers) => [AshA2ui.Diagram.marker()],
          optional(:nodes) => [%{id: String.t(), label: String.t()}]
        }

  @doc "The diagram source and markers for this render."
  @callback diagram(context) :: {:ok, result} | {:error, term}
end
