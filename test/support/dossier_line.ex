defmodule AshA2ui.Test.DossierLine do
  @moduledoc """
  Fixture resource for row field actions (admin catalog 3.9): a line of a
  dossier whose amount was read from a document (`amount_review`, in
  `AshA2ui.Review`'s shape). A person checks the whole line at once:
  `:mark_reviewed` takes no `:field` argument and marks every review on the
  line reviewed; `review_open` says whether the line still waits.
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
    attribute :label, :string, public?: true, allow_nil?: false
    attribute :position, :integer, public?: true, default: 0
    attribute :period, :string, public?: true
    attribute :amount, :integer, public?: true
    attribute :amount_review, :map, public?: true
    attribute :period_review, :map, public?: true
    attribute :reviewed_count, :integer, public?: true, default: 0
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :mark_reviewed do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        reviewed = fn review -> review && Map.put(review, :state, :reviewed) end

        changeset
        |> Ash.Changeset.change_attribute(
          :amount_review,
          reviewed.(changeset.data.amount_review)
        )
        |> Ash.Changeset.change_attribute(
          :period_review,
          reviewed.(changeset.data.period_review)
        )
        |> Ash.Changeset.change_attribute(:reviewed_count, changeset.data.reviewed_count + 1)
      end
    end
  end

  calculations do
    calculate :review_open,
              :boolean,
              fn lines, _context ->
                Enum.map(lines, fn line ->
                  Enum.any?(
                    [line.amount_review, line.period_review],
                    &match?(%{state: state} when state in [:pending, :missing], &1)
                  )
                end)
              end do
      public? true
    end
  end
end
