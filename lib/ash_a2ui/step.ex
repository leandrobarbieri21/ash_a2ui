defmodule AshA2ui.Step do
  @moduledoc """
  Target struct for the `step` DSL entity — one page of a wizard (stepped)
  `:form` component. See `AshA2ui.Wizard` for the data model and the
  handler contract.
  """

  defstruct [
    :name,
    :label,
    :description,
    fields: [],
    review?: false,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          description: String.t() | nil,
          fields: [atom],
          review?: boolean
        }
end
