defmodule AshA2ui.Query do
  @moduledoc """
  Target struct for the `query` DSL entity: a named, server-enforced allowlist
  for search, sorting, equality filters, and pagination.

  A `query` never lets clients supply arbitrary sort/filter parameters — the
  `"query"` client action is validated against these lists (see
  `AshA2ui.QueryRunner`) and anything not declared here is rejected before
  Ash is called.
  """

  defstruct [
    :name,
    :default_preset,
    search_fields: [],
    sortable: [],
    filters: [],
    hidden_filters: [],
    range_filters: [],
    presets: [],
    preset_picker: true,
    apply_on_change: false,
    default_sort: [],
    page_size: 25,
    max_page_size: 100,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          search_fields: [atom | [atom]],
          sortable: [atom],
          filters: [atom],
          hidden_filters: [atom],
          range_filters: [atom],
          presets: [AshA2ui.Preset.t()],
          default_preset: atom | nil,
          preset_picker: boolean,
          apply_on_change: boolean,
          default_sort: [{atom, :asc | :desc}],
          page_size: pos_integer,
          max_page_size: pos_integer
        }
end
