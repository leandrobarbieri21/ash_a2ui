defmodule AshA2ui.Test.Search.Outage do
  @moduledoc "A resource whose primary read always fails, as a data layer outage would."

  use Ash.Resource,
    domain: AshA2ui.Test.Search.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :string, public?: true
  end

  actions do
    read :read do
      primary? true
      prepare AshA2ui.Test.Search.Outage.Down
    end
  end
end
