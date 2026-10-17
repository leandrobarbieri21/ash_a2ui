defmodule AshA2ui.Test.ComposedBoard.Domain do
  @moduledoc "Domain for the composed-board fixture (A2UI-110)."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.ComposedBoard.Job
  end
end

defmodule AshA2ui.Test.ComposedBoard.Job do
  @moduledoc """
  A resource with wide enumerations for the composed-board cell cap: five
  `stage` values by three `region` values is 15 cells. `region_or_none`
  maps a nil region to its own value, the way a composed board must
  swimlane over a nullable attribute.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.ComposedBoard.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false

    attribute :stage, :atom,
      public?: true,
      constraints: [one_of: [:new, :triage, :quoted, :booked, :done]],
      default: :new

    attribute :region, :atom, public?: true, constraints: [one_of: [:north, :south, :west]]
  end

  calculations do
    calculate :region_or_none,
              :atom,
              expr(if is_nil(region), do: :none, else: region),
              constraints: [one_of: [:north, :south, :west, :none]],
              public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :advance do
      accept []
      change set_attribute(:stage, :triage)
    end
  end
end
