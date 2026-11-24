defmodule AshA2ui.Test.Search.Licence do
  @moduledoc """
  A record found by its business reference (`number`) or its id, in a
  clinic (the tenant), readable by its holder and by an administrator.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Search.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  multitenancy do
    strategy :attribute
    attribute :clinic
  end

  attributes do
    uuid_primary_key :id

    attribute :clinic, :string, public?: true, allow_nil?: false
    attribute :number, :string, public?: true, allow_nil?: false
    attribute :holder_id, :uuid, public?: true, allow_nil?: false
    attribute :renewals, :integer, public?: true, default: 0
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:admin?, true)
      authorize_if expr(holder_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end
end
