defmodule AshA2ui.Test.DossierNote do
  @moduledoc """
  Fixture resource for pair reviews (admin catalog 3.10): a note of a dossier
  whose facts were read from a document, each fact a `{term, value}` pair
  with its own review and key. A person checks one fact at a time:
  `:check_fact` takes the fact's key as its `:item` argument and marks that
  fact's review reviewed. `facts_open` says whether the reader may check
  facts on the note at all.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :dossier_id, :uuid, public?: true, allow_nil?: false
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :position, :integer, public?: true, default: 0
    attribute :facts, {:array, :map}, public?: true, default: []
    attribute :locked, :boolean, public?: true, default: false
    attribute :checked, {:array, :string}, public?: true, default: []
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :check_fact do
      accept []
      argument :item, :string, allow_nil?: false
      require_atomic? false

      change fn changeset, _context ->
        key = Ash.Changeset.get_argument(changeset, :item)

        facts =
          Enum.map(changeset.data.facts, fn fact ->
            if to_string(fact[:key] || fact["key"]) == key,
              do: Map.put(fact, :review, %{state: :reviewed, page: 1}),
              else: fact
          end)

        changeset
        |> Ash.Changeset.change_attribute(:facts, facts)
        |> Ash.Changeset.change_attribute(:checked, changeset.data.checked ++ [key])
      end
    end
  end

  calculations do
    calculate :facts_open, :boolean, expr(not locked) do
      public? true
    end
  end
end
