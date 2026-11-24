defmodule AshA2ui.Test.LeaseTerm do
  @moduledoc """
  Fixture resource for recalculating values from unsaved changes: a lease's
  term, on its own record. Its `:correct` works out the date notice is due
  by (`notice_by`, the end less the notice) and stores it, as a host keeps a
  derived date every reader uses: a recalculation has to run the action to
  see it.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Mnesia,
    notifiers: [AshA2ui.Test.LeaseNotifier]

  mnesia do
    table :ash_a2ui_test_lease_terms
  end

  attributes do
    uuid_primary_key :id

    attribute :ends_on, :date, public?: true
    attribute :notice_days, :integer, public?: true, constraints: [min: 0]
    attribute :notice_by, :date, public?: true
  end

  relationships do
    belongs_to :lease, AshA2ui.Test.Lease do
      public? true
      allow_nil? false
      attribute_writable? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :correct do
      accept [:ends_on, :notice_days]
      require_atomic? false

      change fn changeset, _context ->
        ends_on = Ash.Changeset.get_attribute(changeset, :ends_on)
        days = Ash.Changeset.get_attribute(changeset, :notice_days)

        if match?(%Date{}, ends_on) and is_integer(days),
          do:
            Ash.Changeset.force_change_attribute(changeset, :notice_by, Date.add(ends_on, -days)),
          else: changeset
      end
    end
  end
end
