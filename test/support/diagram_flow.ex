defmodule AshA2ui.Test.Diagram.Domain do
  @moduledoc """
  Domain for the live-diagram fixtures (A2UI-108). Kept apart from the
  frozen shared `AshA2ui.Test.Domain`.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.Diagram.Visit
  end
end

defmodule AshA2ui.Test.Diagram.TeamScope do
  @moduledoc "Read preparation scoping visits to the actor's `team` (all without an actor)."

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, %{actor: %{team: team}}), do: Ash.Query.filter(query, team == ^team)
  def prepare(query, _opts, _context), do: query
end

defmodule AshA2ui.Test.Diagram.Visit do
  @moduledoc """
  A visit walking a process: `node` is the diagram node it stands on and
  `status` its token status. Reads are scoped to the actor's `team`.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Diagram.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :patient, :string, public?: true, allow_nil?: false
    attribute :node, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:active, :executing, :waiting, :failed, :done]],
      default: :active

    attribute :team, :string, public?: true, default: "red"
  end

  actions do
    defaults [:destroy, create: :*, update: :*]

    read :read do
      primary? true
      prepare AshA2ui.Test.Diagram.TeamScope
    end
  end
end

defmodule AshA2ui.Test.Diagram.Flow do
  @moduledoc """
  The fixture diagram source: a four-node flowchart, one marker per visit
  the actor can read (the host's own authorized read), each linking to the
  visit's `"visit"` surface. `diagram_for/2` is the `{module, function,
  args}` form; `broken/1` answers `{:error, _}`; `malformed/1` returns a
  marker without a status.
  """

  @behaviour AshA2ui.Diagram.Source

  @source """
  flowchart TD
    start([Start]) --> triage[Triage]
    triage --> exam[Exam]
    exam --> finish([Done])
  """

  @labels %{"start" => "Start", "triage" => "Triage", "exam" => "Exam", "finish" => "Done"}

  def source, do: @source

  @impl true
  def diagram(%{actor: actor}) do
    markers =
      AshA2ui.Test.Diagram.Visit
      |> Ash.read!(actor: actor, authorize?: false)
      |> Enum.sort_by(& &1.patient)
      |> Enum.map(fn visit ->
        %{
          id: visit.id,
          node_id: visit.node,
          label: visit.patient,
          status: visit.status,
          link: {"visit", visit.id},
          node_label: Map.get(@labels, visit.node)
        }
      end)

    {:ok, %{source: @source, markers: markers}}
  end

  def diagram_for(context, :v1), do: diagram(context)

  def broken(_context), do: {:error, :engine_down}

  def malformed(_context),
    do: {:ok, %{source: @source, markers: [%{node_id: "exam", label: "No status"}]}}
end

defmodule AshA2ui.Test.Diagram.FlowUI do
  @moduledoc """
  A v0.9.1 surface with a live diagram (module source) above a visits
  table.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Diagram.Visit
    surface_id "visit_flow"

    diagram :flow do
      label "Visits in flight"
      description "Where every visit is right now."
      source AshA2ui.Test.Diagram.Flow
    end

    component :table do
      fields [:patient, :node, :status]
    end
  end
end

defmodule AshA2ui.Test.Diagram.FlowV1UI do
  @moduledoc """
  A v1.0 diagram-only surface whose source is `{module, function, args}`,
  plus a diagram whose source fails.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Diagram.Visit
    surface_id "visit_flow_v1"
    spec_version "1.0"

    diagram :flow do
      source {AshA2ui.Test.Diagram.Flow, :diagram_for, [:v1]}
    end

    diagram :offline do
      source {AshA2ui.Test.Diagram.Flow, :broken, []}
    end
  end
end

defmodule AshA2ui.Test.Diagram.MalformedUI do
  @moduledoc "A diagram whose source returns a marker without a status."

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Diagram.Visit
    surface_id "visit_flow_malformed"

    diagram :flow do
      source {AshA2ui.Test.Diagram.Flow, :malformed, []}
    end
  end
end

defmodule AshA2ui.Test.Diagram.VetoResolver do
  @moduledoc "A link resolver that vetoes every link for the blue team."

  @behaviour AshA2ui.LinkResolver

  @impl true
  def surface_for(_target, %{actor: %{team: "blue"}}), do: nil
  def surface_for({:surface, key}, _context), do: key
  def surface_for(_target, _context), do: nil
end
