defmodule AshA2ui.Field do
  @moduledoc """
  Target struct for the `field` DSL entity.

  FROZEN CONTRACT — parallel tracks code against these fields; do not change
  outside an integration commit.
  """

  defstruct [
    :name,
    :label,
    :widget,
    :format,
    :relationship,
    :option_label,
    :option_value,
    :option_sort,
    :source,
    :link,
    :links,
    :link_label,
    :link_url,
    :download,
    :pairs,
    :empty_text,
    :note,
    order: 0,
    badge_text: [],
    badge_tones: [],
    badge_help: [],
    hidden: false,
    option_limit: 100,
    option_search: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          widget: atom | nil,
          format: atom | nil,
          relationship: atom | nil,
          option_label: atom | nil,
          option_value: atom | nil,
          option_sort: atom | nil,
          option_limit: pos_integer,
          option_search: [atom],
          source: [atom] | nil,
          link: atom | {atom | String.t(), atom | [atom]} | nil,
          links: atom | nil,
          link_label: atom | nil,
          link_url: atom | nil,
          download: boolean | nil,
          pairs: boolean | nil,
          empty_text: String.t() | nil,
          note: String.t() | nil,
          badge_text: keyword(String.t()),
          badge_tones: keyword(atom),
          badge_help: keyword(String.t()),
          order: non_neg_integer,
          hidden: boolean
        }
end
