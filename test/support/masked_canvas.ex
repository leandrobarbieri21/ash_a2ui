defmodule MaskedCanvas.Test.Leases do
  @moduledoc "Canvas fixture domain (short name `leases`): one resource with a policy-guarded name."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource MaskedCanvas.Test.Thing
  end
end

defmodule MaskedCanvas.Test.Thing do
  @moduledoc """
  Canvas fixture: a record whose `name` is guarded by a field policy
  (admins only), so a non-admin resolver derives the record label from a
  `%Ash.ForbiddenField{}`.
  """

  use Ash.Resource,
    domain: MaskedCanvas.Test.Leases,
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
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :name do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule MaskedCanvas.Test.Registry do
  @moduledoc "Canvas fixture registry: the domain, no label overrides."

  @behaviour AshA2ui.Canvas.Registry

  @impl true
  def domains, do: [MaskedCanvas.Test.Leases]

  @impl true
  def label(_other), do: nil
end
