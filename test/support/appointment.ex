defmodule AshA2ui.Test.Appointment do
  @moduledoc """
  Fixture resource scoped by contexts: an appointment belongs to an owner and
  a clinic. Also carries a datetime attribute for `range_filters`.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:scheduled, :completed]],
      default: :scheduled

    attribute :scheduled_for, :utc_datetime, public?: true
  end

  relationships do
    belongs_to :owner, AshA2ui.Test.Owner, public?: true
    belongs_to :clinic, AshA2ui.Test.Clinic, public?: true
  end

  calculations do
    # A page of the visit's own, for plain links (`link_url`): none once completed.
    calculate :page_url,
              :string,
              expr(if status == :completed, do: nil, else: "/visits/" <> type(id, :string)) do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
