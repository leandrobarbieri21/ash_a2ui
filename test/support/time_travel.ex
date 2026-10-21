defmodule AshA2ui.Test.TimeTravel.Domain do
  @moduledoc false

  # Its own domain, so the temporal fixture does not extend the frozen
  # shared one.
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.TimeTravel.Plan
  end
end

defmodule AshA2ui.Test.TimeTravel.Plan do
  @moduledoc false

  # A temporal ETS resource: every write versions the row, and a read
  # returns the version valid at its `as_of`.
  use Ash.Resource,
    domain: AshA2ui.Test.TimeTravel.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? false
  end

  temporal do
    strategy :context
    attribute :valid_at
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :tier, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:name, :tier]]

    update :change_tier do
      accept [:tier]
    end
  end
end

defmodule AshA2ui.Test.TimeTravel.PlanUI do
  @moduledoc false

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.TimeTravel.Plan
    surface_id "time_travel_plans"

    component :table do
      fields [:name, :tier]
      read_action :read
      row_actions [:change_tier]
    end
  end
end

if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshA2ui.Test.TimeTravelLive do
    @moduledoc false

    # Unstubbed: the real builds over the temporal fixture, read as of the
    # URL's ?as_of=.
    use AshA2ui.LiveRenderer,
      ui: AshA2ui.Test.TimeTravel.PlanUI,
      time_travel: true
  end
end
