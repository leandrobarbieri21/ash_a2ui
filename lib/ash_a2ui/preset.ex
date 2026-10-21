defmodule AshA2ui.Preset do
  @moduledoc """
  Target struct for the `preset` DSL entity nested inside a `query`: a named,
  server-side composite filter the client selects **by name only** — the
  predicates never travel over the wire.

  Exactly one of the two mechanisms is set:

    * `filter` — a declarative keyword filter ANDed together:
      `[status: :pending, deleted_at: nil]`. A `nil` value means `is_nil`, a
      list means `in`, anything else is equality. Keys may be public
      attributes or public expression calculations.
    * `read_action` — the escape hatch for predicates the keyword form can't
      express (e.g. `not is_nil(...)`, ranges): the preset reads through the
      named read action (with its own `filter expr(...)`) instead of the
      table's `read_action`. Search/filters/sort still apply on top.

  On a `display :calendar` table a preset may also set `calendar_anchor`:
  switching to it moves the window to the one holding today plus that many
  days (see `AshA2ui.Calendar`).
  """

  defstruct [
    :name,
    :filter,
    :read_action,
    :calendar_anchor,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          filter: [{atom, term}] | nil,
          read_action: atom | nil,
          calendar_anchor: integer | nil
        }
end
