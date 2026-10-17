defmodule AshA2ui.Diagram do
  @moduledoc """
  Live diagrams: a mermaid diagram with markers placed on its nodes, whose
  markers move as the host's state changes (the `diagram` DSL entity).

      a2ui do
        for_resource MyApp.Visits.Appointment

        diagram :flight do
          label "Visits in flight"
          source MyApp.FlightDiagram
        end
      end

  ash_a2ui knows nothing about what the diagram shows. The host's `source`
  (an `AshA2ui.Diagram.Source` module, or `{module, function, args}`)
  returns the mermaid source and the markers for each render, as the
  render's actor. A host adapts a process engine (for example ash_bpmn's
  `AshBpmn.FlightView`) or a lineage graph to it; see the Live Diagrams
  topic for a worked adapter.

  ## Markers

  Each marker the source returns is a map:

    * `:node_id` (required) — the mermaid node id the marker sits on;
    * `:label` (required) — who or what the marker is ("Ada Lovelace");
    * `:status` (required) — `:active`, `:executing`, `:waiting`, `:failed`
      or `:done` (strings accepted);
    * `:initials` — the marker's text; defaults to the initials of `label`;
    * `:tone` — `:neutral`, `:info`, `:success`, `:warning`, `:danger` or
      `:accent`; defaults by status (active `:info`, executing `:accent`,
      waiting `:warning`, failed `:danger`, done `:success`);
    * `:link` — what the marker opens: `{surface_key, record_id}` or
      `{ResourceModule, record_id}`. The link is resolved on the server
      through the configured `AshA2ui.LinkResolver` (which may veto it, so
      the marker renders without one), and its `href` comes from
      `config :ash_a2ui, :open_surface_url`. The client never supplies a
      link;
    * `:node_label` — the node's label in the fallback list (defaults to
      the node id);
    * `:id` — a stable marker id (defaults to `<node_id>:<index>`).

  A malformed marker raises `ArgumentError`: it is a bug in the source.

  ## Data model

  The diagram's state lives at `/diagram/<name>`:

      %{
        "markers" => %{"review" => [%{"id" => _, "nodeId" => "review", "label" => _,
                                       "initials" => "AL", "status" => "waiting",
                                       "statusLabel" => "Waiting", "tone" => "warning",
                                       "link" => %{"surface" => _, "recordId" => _,
                                                   "label" => _, "href" => _}}]},
        "nodes" => [%{"id" => "review", "label" => "Review", "count" => 1,
                      "markers" => [...]}],
        "error" => ""
      }

  `markers` is keyed by node id (what the diagram renderer places);
  `nodes` lists the nodes that hold markers, in first-seen order (the
  basic-catalog fallback list, and the order of a source's `nodes` when it
  returns them). The mermaid source is a static component prop, not data.

  Every surface build and full data-model refresh calls the source again,
  so a host that refreshes on PubSub (`AshA2ui.LiveRenderer`'s `:pubsub`
  option, subscribed to its engine's topics) moves the markers with plain
  `updateDataModel` pushes. `refresh_messages/2` builds just the
  `/diagram/<name>` writes for other transports.
  """

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  # `rendered_source` and `link_buttons?` are render annotations the
  # encoder sets for its component pass (the DSL never sets them).
  defstruct [
    :name,
    :label,
    :description,
    :source,
    rendered_source: "",
    link_buttons?: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          description: String.t() | nil,
          source: module | {module, atom, list},
          rendered_source: String.t(),
          link_buttons?: boolean
        }

  @typedoc "A marker as the source returns it (see the moduledoc)."
  @type marker :: %{
          required(:node_id) => String.t(),
          required(:label) => String.t(),
          required(:status) => atom | String.t(),
          optional(:initials) => String.t(),
          optional(:tone) => atom | String.t(),
          optional(:link) => {String.t() | module, term},
          optional(:node_label) => String.t(),
          optional(:id) => String.t()
        }

  @typedoc "One loaded diagram: the source text and the wire-shaped state."
  @type loaded :: %{source: String.t(), state: map}

  @statuses [:active, :executing, :waiting, :failed, :done]
  @default_tones %{
    active: :info,
    executing: :accent,
    waiting: :warning,
    failed: :danger,
    done: :success
  }
  @unavailable "This diagram is unavailable."

  @doc "The marker statuses."
  @spec statuses() :: [atom]
  def statuses, do: @statuses

  @doc "The reserved data-model path of a diagram's state."
  @spec data_path(atom | String.t()) :: String.t()
  def data_path(name), do: "/diagram/#{name}"

  @doc "The heading of a diagram: its `label`, else the humanized name."
  @spec label(t()) :: String.t()
  def label(%__MODULE__{label: label}) when is_binary(label) and label != "", do: label

  def label(%__MODULE__{name: name}) do
    name |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  @doc "The empty state of a diagram (no markers, no error)."
  @spec empty_state() :: map
  def empty_state, do: %{"markers" => %{}, "nodes" => [], "error" => ""}

  @doc """
  The initial `/diagram` state of a view: one empty state per diagram.
  `%{}` on surfaces without diagrams.
  """
  @spec initial_state(ResolvedView.t()) :: %{String.t() => map}
  def initial_state(%ResolvedView{diagrams: diagrams}) do
    Map.new(diagrams, &{to_string(&1.name), empty_state()})
  end

  @doc """
  Calls every diagram's source for one render and returns
  `%{name => loaded}`. `selected` is the surface's context selection
  (`AshA2ui.ContextRunner.selected/2`); `opts` carries `:actor` and
  `:tenant`.
  """
  @spec load_all(ResolvedView.t(), map, keyword) :: %{atom => loaded}
  def load_all(%ResolvedView{diagrams: diagrams} = view, selected, opts) do
    Map.new(diagrams, &{&1.name, load(&1, view, selected, opts)})
  end

  @doc "Calls one diagram's source (see `load_all/3`)."
  @spec load(t(), ResolvedView.t(), map, keyword) :: loaded
  def load(%__MODULE__{} = diagram, view, selected, opts) do
    context = %{
      name: diagram.name,
      surface_id: view.surface_id,
      actor: opts[:actor],
      tenant: opts[:tenant],
      contexts: Map.new(view.context_order, &{&1, get_in(selected, [&1, :value])})
    }

    case call(diagram.source, context) do
      {:ok, %{source: source, markers: markers} = result}
      when is_binary(source) and is_list(markers) ->
        link_context = %{actor: opts[:actor], tenant: opts[:tenant]}
        wire = markers |> Enum.with_index() |> Enum.map(&normalize(&1, diagram, link_context))
        %{source: source, state: state(wire, Map.get(result, :nodes))}

      {:ok, other} ->
        raise ArgumentError,
              "diagram #{inspect(diagram.name)}: the source must return " <>
                "{:ok, %{source: binary, markers: list}}, got: {:ok, #{inspect(other)}}"

      {:error, _reason} ->
        %{source: "", state: %{empty_state() | "error" => @unavailable}}

      other ->
        raise ArgumentError,
              "diagram #{inspect(diagram.name)}: the source must return {:ok, map} or " <>
                "{:error, reason}, got: #{inspect(other)}"
    end
  end

  defp call({module, function, args}, context), do: apply(module, function, [context | args])
  defp call(module, context) when is_atom(module), do: module.diagram(context)

  @doc """
  The `/diagram/<name>` writes of every diagram (in declaration order),
  re-read as the actor in
  `opts` — for transports that push marker moves without a full data-model
  refresh. `opts` takes `build_surface/2`'s `:actor`, `:tenant` and
  `:context_state`.
  """
  @spec refresh_messages(module | Spark.Dsl.t(), keyword) :: [map]
  def refresh_messages(resource_or_ui_module, opts \\ []) do
    view = ResolvedView.resolve(resource_or_ui_module, Keyword.take(opts, [:actor, :tenant]))
    selected = AshA2ui.ContextRunner.selected(view, opts[:context_state])

    loaded_by_name = load_all(view, selected, opts)

    Enum.map(view.diagrams, fn %{name: name} ->
      loaded = Map.fetch!(loaded_by_name, name)

      %{
        "version" => if(view.spec_version == :v1_0, do: "v1.0", else: "v0.9.1"),
        "updateDataModel" => %{
          "surfaceId" => view.surface_id,
          "path" => data_path(name),
          "value" => loaded.state
        }
      }
    end)
  end

  @doc """
  The surfaces the markers of the diagram named `name` (a client string)
  link to for this render — what an `"open_surface"` from that diagram may
  open. Unknown names link nowhere.
  """
  @spec link_surfaces(ResolvedView.t(), String.t(), map, keyword) :: [String.t()]
  def link_surfaces(view, name, selected, opts) do
    case Enum.find(view.diagrams, &(to_string(&1.name) == name)) do
      nil ->
        []

      diagram ->
        loaded = load(diagram, view, selected, opts)

        for {_node, markers} <- loaded.state["markers"],
            %{"link" => %{"surface" => surface}} <- markers,
            uniq: true,
            do: surface
    end
  end

  # --- normalization ----------------------------------------------------------

  defp normalize({marker, index}, diagram, link_context) when is_map(marker) do
    node_id = required_string(marker, :node_id, diagram)
    label = required_string(marker, :label, diagram)
    status = status!(fetch(marker, :status), diagram)

    %{
      "id" => optional_string(marker, :id) || "#{node_id}:#{index}",
      "nodeId" => node_id,
      "nodeLabel" => optional_string(marker, :node_label) || node_id,
      "label" => label,
      "initials" => optional_string(marker, :initials) || initials(label),
      "status" => Atom.to_string(status),
      "statusLabel" => status |> Atom.to_string() |> String.capitalize(),
      "tone" => tone!(fetch(marker, :tone), status, diagram)
    }
    |> put_link(fetch(marker, :link), label, link_context, diagram)
  end

  defp normalize({marker, _index}, diagram, _link_context) do
    raise ArgumentError,
          "diagram #{inspect(diagram.name)}: a marker must be a map, got: #{inspect(marker)}"
  end

  defp fetch(marker, key), do: Map.get(marker, key, Map.get(marker, Atom.to_string(key)))

  defp required_string(marker, key, diagram) do
    case optional_string(marker, key) do
      nil ->
        raise ArgumentError,
              "diagram #{inspect(diagram.name)}: every marker needs a #{inspect(key)}, got: " <>
                inspect(marker)

      value ->
        value
    end
  end

  defp optional_string(marker, key) do
    case fetch(marker, key) do
      nil -> nil
      "" -> nil
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value when is_number(value) -> to_string(value)
      _other -> nil
    end
  end

  defp status!(status, diagram) do
    case Enum.find(@statuses, &(to_string(&1) == to_string(status))) do
      nil ->
        raise ArgumentError,
              "diagram #{inspect(diagram.name)}: marker status must be one of " <>
                "#{inspect(@statuses)}, got: #{inspect(status)}"

      found ->
        found
    end
  end

  defp tone!(nil, status, _diagram), do: Atom.to_string(@default_tones[status])

  defp tone!(tone, _status, diagram) do
    case Enum.find(AshA2ui.RowLayout.tones(), &(to_string(&1) == to_string(tone))) do
      nil ->
        raise ArgumentError,
              "diagram #{inspect(diagram.name)}: marker tone must be one of " <>
                "#{inspect(AshA2ui.RowLayout.tones())}, got: #{inspect(tone)}"

      found ->
        Atom.to_string(found)
    end
  end

  # The link target resolves like a field's reference link: a surface key
  # (`{:surface, key}`) or a resource (`{:resource, module}`), mapped by the
  # configured AshA2ui.LinkResolver, which may veto it for this actor.
  defp put_link(wire, nil, _label, _link_context, _diagram), do: wire

  defp put_link(wire, {target, record_id}, label, link_context, diagram)
       when not is_nil(record_id) do
    case target |> link_target(diagram) |> AshA2ui.LinkResolver.resolve(link_context) do
      nil ->
        wire

      surface ->
        record_id = to_string(record_id)
        link = %{"surface" => surface, "recordId" => record_id, "label" => label}

        link =
          case Application.get_env(:ash_a2ui, :open_surface_url) do
            template when is_binary(template) ->
              Map.put(link, "href", AshA2ui.Links.href(template, surface, record_id))

            _none ->
              link
          end

        Map.put(wire, "link", link)
    end
  end

  defp put_link(_wire, link, _label, _link_context, diagram) do
    raise ArgumentError,
          "diagram #{inspect(diagram.name)}: a marker link must be {surface_key, record_id} or " <>
            "{ResourceModule, record_id}, got: #{inspect(link)}"
  end

  defp link_target(surface, _diagram) when is_binary(surface) and surface != "",
    do: {:surface, surface}

  defp link_target(module, diagram) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and ResourceInfo.resource?(module),
      do: {:resource, module},
      else: link_target(Atom.to_string(module), diagram)
  end

  defp link_target(other, diagram) do
    raise ArgumentError,
          "diagram #{inspect(diagram.name)}: a marker link target must be a surface key or an " <>
            "Ash resource, got: #{inspect(other)}"
  end

  @doc "The initials of a label: the first letters of its first two words, upcased."
  @spec initials(String.t()) :: String.t()
  def initials(label) do
    label
    |> to_string()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &(&1 |> String.first() |> String.upcase()))
    |> case do
      "" -> "?"
      letters -> letters
    end
  end

  # --- state ------------------------------------------------------------------

  defp state(markers, declared_nodes) do
    by_node = Enum.group_by(markers, & &1["nodeId"])

    order =
      (declared_ids(declared_nodes) ++ Enum.map(markers, & &1["nodeId"]))
      |> Enum.uniq()

    labels = declared_labels(declared_nodes)

    nodes =
      order
      |> Enum.filter(&Map.has_key?(by_node, &1))
      |> Enum.map(fn node_id ->
        node_markers = Map.fetch!(by_node, node_id)

        %{
          "id" => node_id,
          "label" => Map.get(labels, node_id) || hd(node_markers)["nodeLabel"],
          "count" => length(node_markers),
          "markers" => node_markers
        }
      end)

    %{"markers" => by_node, "nodes" => nodes, "error" => ""}
  end

  defp declared_ids(nodes) when is_list(nodes),
    do: for(%{id: id} <- nodes, do: to_string(id))

  defp declared_ids(_none), do: []

  defp declared_labels(nodes) when is_list(nodes),
    do: for(%{id: id, label: label} <- nodes, into: %{}, do: {to_string(id), to_string(label)})

  defp declared_labels(_none), do: %{}
end
