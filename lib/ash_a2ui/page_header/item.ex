defmodule AshA2ui.PageHeader.Item do
  @moduledoc """
  Target struct for a `page_header`'s `tag` and `meta` entities: one item
  of the line under the title, its text, tone, icon and tooltip read from
  the record (`kind` says which entity declared it).
  """

  defstruct [
    :field,
    :tone,
    :icon,
    :icon_field,
    :help,
    :help_field,
    :help_label,
    kind: :meta,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          field: atom,
          tone: atom | nil,
          icon: String.t() | nil,
          icon_field: atom | nil,
          help: String.t() | nil,
          help_field: atom | nil,
          help_label: String.t() | nil,
          kind: :tag | :meta
        }
end
