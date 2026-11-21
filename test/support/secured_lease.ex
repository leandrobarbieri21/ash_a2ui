defmodule AshA2ui.Test.SecureClient do
  @moduledoc """
  Fixture: a client whose `credit_line` is guarded by a field policy
  (admins only). The destination of `AshA2ui.Test.SecureLease`'s
  `belongs_to :client`, so a `source` walk can hit a forbidden leaf.
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

    attribute :credit_line, :decimal, public?: true
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
    field_policy :credit_line do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule AshA2ui.Test.SecureLease do
  @moduledoc """
  Fixture: a lease whose `rate` is guarded by a field policy (admins
  only) — the forbidden leaf a `source` walk can hit. Ash field policies
  cover attributes and calculations only, so a forbidden *relationship*
  step (which masks every `source [:client, ...]` field behind it) is
  exercised on a constructed record; the walker treats any forbidden step
  the same. `:note` is a `nil` the reader may see.
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

    attribute :rate, :decimal, public?: true

    attribute :note, :string, public?: true

    attribute :state, :atom,
      public?: true,
      constraints: [one_of: [:open, :closed]],
      default: :open
  end

  relationships do
    belongs_to :client, AshA2ui.Test.SecureClient, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :rate do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule AshA2ui.Test.SecureLeasesUI do
  @moduledoc """
  Fixture surface over the field-policy-guarded lease: a table (the
  forbidden `rate`, a visible `nil`, and `source` walks into the client —
  one to a forbidden leaf, one behind a forbidden relationship), a
  `:detail` card (the `rate` drawn as a badge field), and the form whose
  edit buffer must keep `null` for a forbidden field.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.SecureLease
    surface_id "secure_leases"
    title "Secure leases"

    context :lease do
      resource AshA2ui.Test.SecureLease
      option_label :name
    end

    query :default do
      default_sort name: :asc
    end

    component :table do
      fields [:name, :rate, :note, :client_credit, :client_name]
      read_action :read
      query :default
    end

    component :detail, :card do
      context :lease
      fields [:name, :rate, :note]
    end

    component :form do
      fields [:name, :rate, :note]
      create_action :create
      update_action :update
    end

    field :rate do
      badge_tones open: :info, closed: :gray
    end

    field :client_credit do
      label "Client credit line"
      source [:client, :credit_line]
    end

    field :client_name do
      label "Client name"
      source [:client, :name]
    end
  end
end
