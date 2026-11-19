defmodule AshA2ui.PageHeader.Action do
  @moduledoc """
  Target struct for a `page_header`'s `header_action` entity: a header
  button, a link (`href`) or an update action of the record (`run`).
  """

  defstruct [
    :name,
    :label,
    :run,
    :href,
    :visible,
    :title,
    variant: :secondary,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          run: atom | nil,
          href: atom | nil,
          visible: atom | nil,
          title: String.t() | nil,
          variant: :primary | :secondary | :quiet
        }
end
