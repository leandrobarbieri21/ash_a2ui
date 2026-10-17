defmodule AshA2ui.Test.BoardTask do
  @moduledoc """
  Fixture resource for boards (sections over an attribute's enumerated
  values): `status` is an atom with a `one_of` constraint (the board's lane
  attribute, moved by the `:claim` / `:complete` transitions) and
  `severity` an `Ash.Type.Enum` (`AshA2ui.Test.Severity`). `stage`'s
  `one_of` holds two values whose lane names collide (`:"in-progress"` and
  `:in_progress`), and `tier`'s values whose runtime names extend one
  another (`:high`, `:high_total`), for the verifier.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:open, :claimed, :completed, :archived]],
      default: :open

    attribute :priority, :atom,
      public?: true,
      constraints: [one_of: [:low, :high]],
      default: :low

    attribute :severity, AshA2ui.Test.Severity, public?: true

    # Two values that sanitize to the same lane name (board_in_progress).
    attribute :stage, :atom,
      public?: true,
      constraints: [one_of: [:"in-progress", :in_progress, :done]]

    # Values whose runtime names extend one another (board_high,
    # board_high_total, board_high_cells): their component ids collide.
    attribute :tier, :atom,
      public?: true,
      constraints: [one_of: [:high, :high_total, :high_cells, :low]]
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :claim do
      accept []
      change set_attribute(:status, :claimed)
    end

    update :complete do
      accept []
      change set_attribute(:status, :completed)
    end
  end
end
