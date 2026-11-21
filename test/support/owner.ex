defmodule AshA2ui.Test.Owner do
  @moduledoc """
  Fixture resource for surface contexts: the "user" of the visits-shaped
  fixture trio (Owner -> ClinicMembership -> Clinic, Appointment scoped by
  owner + clinic).
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
    attribute :email, :string, public?: true, allow_nil?: false
  end

  relationships do
    has_many :clinic_memberships, AshA2ui.Test.ClinicMembership, public?: true
  end

  calculations do
    # A value a table's row calculation reuses from the selected owner
    # (`context_record`, AshA2ui.Test.SharedOwnerVisitsUI).
    calculate :greeting, :string, expr("Hello " <> name) do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
