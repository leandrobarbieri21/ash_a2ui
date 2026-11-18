defmodule AshA2ui.Test.Finding do
  @moduledoc """
  Fixture resource for field actions (admin catalog 3.2): a finding whose
  title and amount a person checks one at a time. `:check_field` records
  the field it is run for (its `:field` argument); `title_open` says
  whether the title still waits for its check.
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
    attribute :amount, :integer, public?: true
    attribute :note, :string, public?: true
    attribute :checked_fields, {:array, :atom}, public?: true, default: []
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :check_field do
      require_atomic? false

      argument :field, :atom do
        allow_nil? false
        constraints one_of: [:title, :amount]
      end

      change fn changeset, _context ->
        field = Ash.Changeset.get_argument(changeset, :field)
        checked = Ash.Changeset.get_attribute(changeset, :checked_fields) || []
        Ash.Changeset.change_attribute(changeset, :checked_fields, Enum.uniq(checked ++ [field]))
      end
    end
  end

  calculations do
    calculate :title_open,
              :boolean,
              fn records, _context ->
                Enum.map(records, &(:title not in (&1.checked_fields || [])))
              end do
      public? true
    end
  end
end
