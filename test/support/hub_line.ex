defmodule AshA2ui.Test.HubLine do
  @moduledoc "Fixture: a line of a `AshA2ui.Test.HubContract`, at one property."

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :property, :string, public?: true
  end

  relationships do
    belongs_to :contract, AshA2ui.Test.HubContract, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end
end
