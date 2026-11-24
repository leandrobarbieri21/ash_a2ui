defmodule AshA2ui.Test.StatementTerm do
  @moduledoc """
  Fixture resource for editing a related record's values in place: the term
  a statement states (when it ends, how many days' notice it asks for, and
  whether it renews), kept on its own record, one per statement. Corrected
  only through its own `:correct`, which the statement's `:correct` runs for
  it (`manage_relationship`); a locked term is never corrected.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :ends_on, :date, public?: true
    attribute :notice_days, :integer, public?: true, constraints: [min: 0]

    attribute :renewal, :atom do
      public? true
      constraints one_of: [:manual, :automatic]
    end

    attribute :locked, :boolean, public?: true, default: false
  end

  relationships do
    belongs_to :statement, AshA2ui.Test.Statement do
      public? true
      allow_nil? false
      attribute_writable? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :correct do
      accept [:ends_on, :notice_days, :renewal]
      require_atomic? false

      validate fn changeset, _context ->
        if changeset.data.locked,
          do: {:error, field: :ends_on, message: "a locked term is never corrected"},
          else: :ok
      end
    end
  end
end
