defmodule AshA2ui.Test.HubRole do
  @moduledoc "Fixture: a party of a `AshA2ui.Test.HubContract`, as its vendor or its PMC."

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :role, :atom, public?: true, constraints: [one_of: [:vendor, :pmc]]
    attribute :party_name, :string, public?: true
  end

  relationships do
    belongs_to :contract, AshA2ui.Test.HubContract, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end
end
