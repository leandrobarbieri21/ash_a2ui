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

    # How a visit's title and status were filled in (`review`): the title
    # read from page 3 of the referral and not checked yet; the status
    # looked for and not found until the visit is completed.
    calculate :title_review,
              :map,
              fn records, _context ->
                Enum.map(records, fn _visit ->
                  %{
                    state: :pending,
                    page: 3,
                    href: "/referrals/1#page=3",
                    quote: "Reason for visit: checkup"
                  }
                end)
              end do
      public? true
    end

    calculate :status_review,
              :map,
              fn records, _context ->
                Enum.map(records, fn visit ->
                  if visit.status == :completed,
                    do: %{"state" => "reviewed", "page" => "2"},
                    else: %{"state" => "missing"}
                end)
              end do
      public? true
    end

    # The referral a visit's details were read from, for a document pane
    # (catalog 3.4): a walk-in has none. Its title was read from a box on
    # page 1, its status from page 2; the clinic's stamp is a region no
    # field cites.
    calculate :referral_document,
              :map,
              fn records, _context ->
                Enum.map(records, fn
                  %{title: "Walk-in"} -> nil
                  visit -> %{url: "/referrals/#{visit.id}/file", name: "referral.pdf"}
                end)
              end do
      public? true
    end

    calculate :referral_regions,
              {:array, :map},
              fn records, _context ->
                Enum.map(records, fn _visit ->
                  [
                    %{
                      id: "stamp",
                      page: 2,
                      x: 0.7,
                      y: 0.85,
                      width: 0.2,
                      height: 0.08,
                      state: :empty
                    },
                    %{id: "bad", page: 0, x: 0.1, y: 0.1, width: 0.1, height: 0.1}
                  ]
                end)
              end do
      public? true
    end

    calculate :title_cited_review,
              :map,
              fn records, _context ->
                Enum.map(records, fn _visit ->
                  %{
                    state: :pending,
                    page: 1,
                    boxes: [
                      %{page: 1, x: 0.1, y: 0.2, width: 0.3, height: 0.025},
                      %{page: 1, x: 2, y: 0.2, width: 0.3, height: 0.025}
                    ]
                  }
                end)
              end do
      public? true
    end

    calculate :status_cited_review,
              :map,
              fn records, _context ->
                Enum.map(records, fn visit ->
                  %{
                    state: if(visit.status == :completed, do: :reviewed, else: :pending),
                    page: 2,
                    href: "/referrals/1#page=2",
                    boxes: [
                      %{"page" => 2, "x" => 0.5, "y" => 0.4, "width" => 0.25, "height" => 0.02}
                    ]
                  }
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
