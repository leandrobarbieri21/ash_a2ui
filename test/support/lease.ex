defmodule AshA2ui.Test.Lease do
  @moduledoc """
  Fixture resource for recalculating values from unsaved changes (admin
  catalog 3.15): a lease whose monthly rent and term a person corrects
  (`:correct`, the term through its own `:correct`), and the values worked
  out from them: the yearly rent, the date notice is due by (stored on the
  term, derived when the term is corrected) and a timeline of the two dates.

  On Mnesia, a data layer with transactions: the preview runs the
  correction and rolls it back. `AshA2ui.Test.LeaseNotifier` reports every
  notification to the process that ran the action.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Mnesia,
    notifiers: [AshA2ui.Test.LeaseNotifier]

  mnesia do
    table :ash_a2ui_test_leases
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
    attribute :rent, :integer, public?: true, constraints: [min: 0]
    attribute :locked, :boolean, public?: true, default: false
  end

  relationships do
    has_one :term, AshA2ui.Test.LeaseTerm do
      public? true
      destination_attribute :lease_id
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :correct do
      accept [:title, :rent]
      require_atomic? false

      argument :term, :map

      change manage_relationship(:term,
               on_match: {:update, :correct},
               on_no_match: :error,
               on_missing: :ignore,
               on_lookup: :ignore
             )

      validate fn changeset, _context ->
        if changeset.data.locked,
          do: {:error, field: :locked, message: "a locked lease is never corrected"},
          else: :ok
      end
    end
  end

  calculations do
    calculate :correctable, :boolean, expr(not locked), public?: true

    calculate :yearly_text,
              :string,
              fn records, _context ->
                Enum.map(records, &(&1.rent && "$#{&1.rent * 12} a year"))
              end do
      public? true
    end

    calculate :ends_text, :string, {AshA2ui.Test.LeaseTermText, part: :ends_on}, public?: true

    calculate :notice_text,
              :string,
              {AshA2ui.Test.LeaseTermText, part: :notice_days},
              public?: true

    calculate :notice_by_text,
              :string,
              {AshA2ui.Test.LeaseTermText, part: :notice_by},
              public?: true

    calculate :timeline,
              {:array, :map},
              {AshA2ui.Test.LeaseTermText, part: :timeline},
              public?: true
  end
end
