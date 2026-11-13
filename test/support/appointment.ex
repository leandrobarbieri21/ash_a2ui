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

    # A visit's labeled values whose labels vary per record (`pairs`), and a
    # badge already in words.
    calculate :details,
              {:array, :map},
              fn records, _context ->
                Enum.map(records, fn visit ->
                  [%{"term" => "Title", "value" => visit.title}] ++
                    if(visit.status,
                      do: [%{"term" => "Status", "value" => to_string(visit.status)}],
                      else: []
                    )
                end)
              end do
      public? true
    end

    # A visit's steps (`steps`): booked, checked in, seen and billed, with
    # the state of each.
    calculate :progress,
              {:array, :map},
              fn records, _context ->
                Enum.map(records, fn visit ->
                  done? = visit.status == :completed

                  [
                    %{label: "Booked", text: "Requested online", state: :complete},
                    %{
                      label: "Checked in",
                      text: if(done?, do: "At the front desk", else: "Not yet"),
                      state: if(done?, do: :complete, else: :current)
                    },
                    %{
                      label: "Seen",
                      text: if(done?, do: visit.title, else: "Not yet"),
                      state: if(done?, do: :complete, else: :upcoming)
                    },
                    %{
                      "label" => "Billed",
                      "text" => "Not yet",
                      "note" => if(done?, do: "Invoice not sent"),
                      "state" => if(done?, do: "overdue", else: "upcoming")
                    }
                  ]
                end)
              end do
      public? true
    end

    calculate :seen_by,
              :string,
              expr("Seen by Dr. " <> title) do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
