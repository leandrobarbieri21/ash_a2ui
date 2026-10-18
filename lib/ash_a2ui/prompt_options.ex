defmodule AshA2ui.PromptOptions do
  @moduledoc """
  Target struct for the `prompt_options` DSL entity (inside an `action`):
  the per-row option scope of one relationship prompt field.

  * `field` — the prompt field (one of the action's `prompt_fields`, a
    relationship select).
  * `read_action` — a read action of the relationship's destination
    returning the options that apply to one row.
  * `record_argument` — the argument of `read_action` that receives the
    row's primary key.

  The read runs as the actor (same actor, tenant and `authorize?` as every
  option read) for a row the actor can read through the surface's read
  action. Options are never loaded surface-wide for a scoped field: the
  `prompt` pre-fill writes the row's list, and every picked value is
  re-read through the same scope before it is written or submitted.
  """

  defstruct [:field, :read_action, :record_argument, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          field: atom,
          read_action: atom,
          record_argument: atom
        }
end
