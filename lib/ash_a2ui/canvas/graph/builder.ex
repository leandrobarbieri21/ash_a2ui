defmodule AshA2ui.Canvas.Graph.Builder do
  @moduledoc """
  Builds the canonical graph from a registry by direct Ash introspection.

  One upstream truth: the Ash metadata itself. Domains through
  `Ash.Domain.Info`, resources/relationships/actions through
  `Ash.Resource.Info`, policies through `Ash.Policy.Info`, and state
  machines through `AshStateMachine.Info` when the optional extension is
  loaded. No Mermaid strings, no SVG, no parsing of rendered output — and
  no record reads anywhere: the structural layer is declared metadata only
  (`A2UI-103/AC-4`).

  Determinism rules:

    * domains are traversed sorted by their (compile-known) short names;
    * resources sorted by short name within their domain;
    * relationship edges point at the destination's *canonical* resource id
      (the first registered domain, in sorted order, that lists it);
    * sub-entity lists are sorted by stable id.

  Combined with the canonical revision hash on `AshA2ui.Canvas.Graph`, none
  of this ordering can move the revision.
  """

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Canvas.Graph
  alias AshA2ui.Canvas.Graph.Edge
  alias AshA2ui.Canvas.Graph.Node
  alias AshA2ui.Canvas.Registry
  alias AshA2ui.Label

  @doc "Builds the graph for `registry`."
  @spec build(module()) :: Graph.t()
  def build(registry) do
    domains = Registry.domains(registry)
    app_id = Registry.application_id(registry)

    domain_entries =
      domains
      |> Enum.map(&{domain_short(&1), &1})
      |> Enum.sort_by(&elem(&1, 0))

    resource_ids = resource_index(domain_entries)

    app_node = %Node{
      id: app_id,
      kind: :application,
      label: Registry.label(registry, :application) || Label.humanize(short_name_of(app_id)),
      metadata: %{}
    }

    app_edges =
      Enum.map(domain_entries, fn {short, _domain} ->
        containment(app_id, "domain:" <> short)
      end)

    domain_nodes =
      Enum.map(domain_entries, fn {short, domain} ->
        %Node{
          id: "domain:" <> short,
          kind: :domain,
          label: Registry.label(registry, domain) || Label.humanize(short),
          metadata: %{}
        }
      end)

    {resource_nodes, resource_edges} =
      domain_entries
      |> Enum.map(&domain_section(registry, &1, resource_ids))
      |> Enum.unzip()

    edges =
      (app_edges ++ Enum.flat_map(resource_edges, & &1))
      |> Enum.sort_by(&{&1.from, &1.to, &1.kind, &1.name})

    nodes =
      ([app_node | domain_nodes] ++ List.flatten(resource_nodes))
      |> Map.new(&{&1.id, &1})

    graph = %Graph{revision: nil, roots: [app_id], nodes: nodes, edges: edges}
    %Graph{graph | revision: Graph.revision(graph)}
  end

  # --- domain sections --------------------------------------------------------

  # One domain's contribution: its resource nodes, the containment edges to
  # them, and its registered relationship edges.
  defp domain_section(registry, {domain_short_name, domain}, resource_ids) do
    domain_id = "domain:" <> domain_short_name

    resources =
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.map(&{resource_short(&1), &1})
      |> Enum.sort_by(&elem(&1, 0))

    resource_nodes =
      Enum.map(resources, fn {short, resource} ->
        %Node{
          id: Map.fetch!(resource_ids, resource),
          kind: :resource,
          label: Registry.label(registry, resource) || Label.humanize(short),
          metadata: resource_metadata(resource_id(resource_ids, resource), resource)
        }
      end)

    containment_edges =
      Enum.map(resources, fn {_short, resource} ->
        containment(domain_id, resource_id(resource_ids, resource))
      end)

    edges = containment_edges ++ relationship_edges(domain, resource_ids)

    {resource_nodes, edges}
  end

  defp resource_id(resource_ids, resource), do: Map.fetch!(resource_ids, resource)

  # --- resources --------------------------------------------------------------

  defp resource_metadata(resource_id, resource) do
    metadata = %{
      "actions" => action_sub_entities(resource_id, resource),
      "policies" => policy_sub_entities(resource_id, resource),
      "authorizer" => ResourceInfo.authorizers(resource) != []
    }

    case state_machine_sub_entity(resource_id, resource) do
      nil -> metadata
      state_machine -> Map.put(metadata, "state_machine", state_machine)
    end
  end

  defp action_sub_entities(resource_id, resource) do
    resource
    |> ResourceInfo.actions()
    |> Enum.sort_by(&to_string(&1.name))
    |> Enum.map(fn action ->
      %{
        "id" => "#{resource_id}#action:#{action.name}",
        "name" => to_string(action.name),
        "type" => to_string(action.type)
      }
    end)
  end

  defp policy_sub_entities(resource_id, resource) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.with_index()
    |> Enum.map(fn {policy, index} ->
      %{
        "id" => "#{resource_id}#policy:#{index}",
        "bypass" => Map.get(policy, :bypass?) == true
      }
    end)
  end

  # The optional-dependency degradation: when ash_state_machine is absent,
  # the state-machine sub-entity is omitted entirely (documented on
  # `AshA2ui.Canvas.Graph`); the rest of the graph is unaffected.
  defp state_machine_sub_entity(resource_id, resource) do
    with {:extension_available?, true} <-
           {:extension_available?, Code.ensure_loaded?(AshStateMachine)},
         true <- AshStateMachine in ResourceInfo.extensions(resource),
         states = AshStateMachine.Info.state_machine_all_states(resource),
         false <- states == [] do
      %{
        "id" => "#{resource_id}#state_machine",
        "states" => states |> Enum.map(&to_string/1) |> Enum.sort()
      }
    else
      _not_a_state_machine -> nil
    end
  end

  # --- relationships ----------------------------------------------------------

  # A relationship produces an edge only when its destination resolves
  # inside the registry. A resource that exists but is not registered is
  # invisible to the canvas — the edge, and therefore the connection, does
  # not exist.
  defp relationship_edges(domain, resource_ids) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.flat_map(fn resource ->
      source_id = resource_id(resource_ids, resource)

      resource
      |> ResourceInfo.relationships()
      |> Enum.filter(&Map.has_key?(resource_ids, &1.destination))
      |> Enum.map(fn relationship ->
        %Edge{
          kind: :relationship,
          from: source_id,
          to: resource_id(resource_ids, relationship.destination),
          name: relationship.name
        }
      end)
    end)
  end

  # --- naming -----------------------------------------------------------------

  defp domain_short(domain), do: domain |> Ash.Domain.Info.short_name() |> Atom.to_string()

  defp resource_short(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  # The canonical id of every registered resource:
  # `"resource:<domain>.<resource>"`. When a resource is listed by more than
  # one registered domain, the alphabetically-first domain short name wins —
  # so the id is stable no matter which relationship led to it.
  defp resource_index(domain_entries) do
    Enum.reduce(domain_entries, %{}, fn {domain_short_name, domain}, index ->
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.reduce(index, fn resource, acc ->
        Map.put_new(acc, resource, "resource:#{domain_short_name}.#{resource_short(resource)}")
      end)
    end)
  end

  defp containment(from, to),
    do: %Edge{kind: :contains, from: from, to: to, name: nil}

  defp short_name_of("application:" <> short), do: short
end
