defmodule AshA2ui.Test.BulkProject do
  @moduledoc """
  Fixture resource for bulk actions (A2UI-104): the project a
  `AshA2ui.Test.BulkTask` belongs to, selected through the bulk surfaces'
  `:project` context so the tables' context scope can be exercised.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
