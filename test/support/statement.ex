defmodule AshA2ui.Test.Statement do
  @moduledoc """
  Fixture resource for editing a record in place (admin catalog 3.11): a
  statement whose values were read from a document, which a person corrects
  (`:correct`) and then marks reviewed (`:review`). A locked statement is
  never corrected (`correctable`); `amount_text` is the amount as shown,
  edited as `:amount`; `title_review` and `amount_review` say whether each
  value still waits for a person.
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

    attribute :kind, :atom do
      public? true
      constraints one_of: [:invoice, :quote]
    end

    attribute :due_on, :date, public?: true
    attribute :locked, :boolean, public?: true, default: false
    attribute :reviewed, :boolean, public?: true, default: false
  end

  relationships do
    # The term the statement states, on its own record (editing a related
    # record's values in place, `AshA2ui.Test.StatementTermEditUI`).
    has_one :term, AshA2ui.Test.StatementTerm do
      public? true
      destination_attribute :statement_id
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :correct do
      accept [:title, :amount, :kind, :due_on]
      require_atomic? false

      # The term's values, corrected through the term's own action.
      argument :term, :map

      change manage_relationship(:term,
               on_match: {:update, :correct},
               on_no_match: :error,
               on_missing: :ignore,
               on_lookup: :ignore
             )

      validate compare(:amount, greater_than_or_equal_to: 0)

      validate fn changeset, _context ->
        if changeset.data.locked,
          do: {:error, field: :locked, message: "a locked statement is never corrected"},
          else: :ok
      end
    end

    update :review do
      accept []
      change set_attribute(:reviewed, true)
    end
  end

  calculations do
    calculate :correctable, :boolean, expr(not locked), public?: true

    calculate :term_ends_text,
              :string,
              {AshA2ui.Test.StatementTermText, field: :ends_on},
              public?: true

    calculate :term_notice_text,
              :string,
              {AshA2ui.Test.StatementTermText, field: :notice_days},
              public?: true

    calculate :term_renewal_text,
              :string,
              {AshA2ui.Test.StatementTermText, field: :renewal},
              public?: true

    calculate :review_open, :boolean, expr(not reviewed), public?: true

    calculate :amount_text,
              :string,
              fn records, _context ->
                Enum.map(records, &(&1.amount && "$#{&1.amount}"))
              end do
      public? true
    end

    calculate :title_review,
              :map,
              fn records, _context ->
                Enum.map(records, &%{state: if(&1.reviewed, do: "reviewed", else: "pending")})
              end do
      public? true
    end

    calculate :amount_review,
              :map,
              fn records, _context ->
                Enum.map(records, fn
                  %{reviewed: true} -> %{state: "reviewed"}
                  %{amount: nil} -> %{state: "missing"}
                  _waiting -> %{state: "pending"}
                end)
              end do
      public? true
    end
  end
end
