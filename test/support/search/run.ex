defmodule AshA2ui.Test.Search.Run do
  @moduledoc "A record found by its id only, readable by an administrator."

  use Ash.Resource,
    domain: AshA2ui.Test.Search.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:admin?, true)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end
end
