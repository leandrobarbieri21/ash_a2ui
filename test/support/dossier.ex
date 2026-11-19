defmodule AshA2ui.Test.Dossier do
  @moduledoc """
  Fixture resource for record pages (admin catalog 3.5): a dossier whose
  page header names it and its state, links to its file, and offers
  "Close" to a manager while it is open. `:close` is the header action;
  only an actor with `role: :manager` may run it.
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

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :state, :atom,
      public?: true,
      default: :open,
      constraints: [one_of: [:open, :closed]]

    attribute :owner, :string, public?: true
    attribute :file_url, :string, public?: true
    attribute :summary, :string, public?: true
    attribute :notes, :string, public?: true
    # How each field was filled in (AshA2ui.Review's shape), for review summaries.
    attribute :name_review, :map, public?: true
    attribute :owner_review, :map, public?: true
    attribute :notes_review, :map, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :close do
      accept []
      change set_attribute(:state, :closed)
    end
  end

  policies do
    policy action(:close) do
      authorize_if actor_attribute_equals(:role, :manager)
    end

    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if always()
    end
  end

  calculations do
    calculate :state_text,
              :string,
              expr(if state == :open, do: "Open", else: "Closed") do
      public? true
    end

    calculate :state_tone,
              :string,
              expr(if state == :open, do: "info", else: "gray") do
      public? true
    end

    calculate :state_help,
              :string,
              expr(if state == :open, do: "Still being worked on", else: nil) do
      public? true
    end

    calculate :open?, :boolean, expr(state == :open) do
      public? true
    end

    calculate :closed?, :boolean, expr(state == :closed) do
      public? true
    end

    calculate :closed_note,
              :string,
              expr(if state == :closed, do: "Nothing more is done on it.", else: nil) do
      public? true
    end

    calculate :has_summary?, :boolean, expr(not is_nil(summary)) do
      public? true
    end
  end
end
