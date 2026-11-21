defmodule AshA2ui.Editable do
  @moduledoc """
  Target struct for the `editable` DSL entity: the allowlist of a
  component's fields that a person edits in place, and the update action
  the edits run.

  On a `:table` the listed fields render as in-row inputs committing per
  cell through the `"edit_cell"` client action (see the inline-cell-editing
  section of the multi-section-surfaces topic). On a `:detail` card (admin
  catalog 3.11) each listed field's value opens as an input in place; the
  change waits, with every other unsaved change on the surface, until the
  surface's `save_bar` saves them all through the `"save_changes"` client
  action (see the editing-a-record-in-place section of the
  contexts-and-details topic). `visible` gates editing per record.
  """

  defstruct [
    :update_action,
    :visible,
    fields: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          fields: [atom],
          update_action: atom | nil,
          visible: atom | nil
        }
end
