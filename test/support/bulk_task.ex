defmodule AshA2ui.Test.BulkTask do
  @moduledoc """
  Fixture resource for bulk actions (A2UI-104), with policies so the
  authorized re-read of a selection can be exercised:

    * reads only return records whose `secret` is `false`,
    * writes require an actor,
    * `:approve` fails validation for a record with a negative `score`
      (the partial-failure case), `:reject` always succeeds, `:flag` is a
      row-only action, `:clear` is named like the toolbar's fixed control,
    * `:active` / `:archived` are read actions splitting on `archived` (a
      preset that swaps the read action),
    * `:stamp` is a generic action taking `:record_id` (sets that record's
      `score` to 7); `:ping` is a generic action without one (the verifier
      rejects it as a bulk action).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :approved, :rejected]],
      default: :open

    attribute :score, :integer, public?: true, default: 0
    attribute :secret, :boolean, public?: true, default: false
    attribute :archived, :boolean, public?: true, default: false
  end

  relationships do
    belongs_to :project, AshA2ui.Test.BulkProject, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :approve do
      accept []
      require_atomic? false
      validate compare(:score, greater_than_or_equal_to: 0)
      change set_attribute(:status, :approved)
    end

    update :reject do
      accept []
      change set_attribute(:status, :rejected)
    end

    update :flag do
      accept []
    end

    # Named like the toolbar's fixed "Clear" control (component ids).
    update :clear do
      accept []
      change set_attribute(:score, 0)
    end

    read :active do
      filter expr(archived == false)
    end

    read :archived do
      filter expr(archived == true)
    end

    action :stamp do
      argument :record_id, :uuid, allow_nil?: false

      run fn input, _context ->
        __MODULE__
        |> Ash.get!(input.arguments.record_id, authorize?: false)
        |> Ash.update!(%{score: 7}, action: :update, authorize?: false)

        :ok
      end
    end

    action :ping do
      run fn _input, _context -> :ok end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false)
    end

    policy action_type([:create, :update, :destroy, :action]) do
      authorize_if actor_present()
    end
  end
end
