defmodule AshA2ui.Test.HubContract do
  @moduledoc """
  Fixture resource for the hub filter bar: a contract with a status (with
  groups of leaves), a verified flag, lines naming properties (a to-many
  path filter), parties of two roles (the vendor's name is a `first`
  aggregate filtered to the vendor role, so the PMC party never matches),
  a module calculation shown in the status column and sorted by the
  stored status, and a `secret` flag the read policy hides.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:active, :expiring_soon, :renewal_scheduled, :expired, :draft]],
      default: :draft

    attribute :verified, :boolean, public?: true, default: false
    attribute :status_help, :string, public?: true
    attribute :secret, :boolean, public?: true, default: false
    attribute :archived, :boolean, public?: true, default: false
  end

  relationships do
    has_many :lines, AshA2ui.Test.HubLine, public?: true, destination_attribute: :contract_id
    has_many :roles, AshA2ui.Test.HubRole, public?: true, destination_attribute: :contract_id
  end

  calculations do
    calculate :status_text, :atom, AshA2ui.Test.HubContract.StatusText, public?: true
  end

  aggregates do
    first :vendor_name, :roles, :party_name do
      public? true
      filter expr(role == :vendor)
    end

    first :property_name, :lines, :property, public?: true
    count :line_count, :lines, public?: true
    list :property_names, :lines, :property, public?: true
  end

  actions do
    defaults [:read, create: :*]

    read :active do
      filter expr(archived == false)
    end

    read :archived do
      filter expr(archived == true)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end
end
