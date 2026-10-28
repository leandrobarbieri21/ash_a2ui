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
    :search_placeholder,
    :empty_state,
    :no_results_state,
    search_fields: [],
    sortable: [],
    filters: [],
    hidden_filters: [],
    range_filters: [],
    presets: [],
    preset_picker: true,
    apply_on_change: false,
    multi_select_filters: [],
    filter_groups: [],
    group_labels: [],
    filter_labels: [],
    filter_hints: [],
    facet_counts: false,
    path_filters: [],
    filter_order: [],
    controls_card: true,
    page_size_options: [],
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
          multi_select_filters: [atom],
          filter_groups: keyword(keyword([atom])),
          group_labels: keyword(keyword(String.t())),
          filter_labels: keyword(String.t()),
          filter_hints: keyword(String.t()),
          facet_counts: boolean | [atom],
          path_filters: keyword(atom | [atom]),
          filter_order: [atom],
          search_placeholder: String.t() | nil,
          empty_state: keyword | nil,
          no_results_state: keyword | nil,
          controls_card: boolean,
          page_size_options: [pos_integer],
          default_sort: [{atom, :asc | :desc}],
          page_size: pos_integer,
          max_page_size: pos_integer
        }

  @doc """
  Every filter name the client may send under `filters`: the declared
  `filters` followed by the `path_filters` names, in `filter_order` when the
  query declares one (unlisted names keep their order after the listed ones).
  """
  @spec filter_names(t()) :: [atom]
  def filter_names(%__MODULE__{} = query) do
    names = query.filters ++ Keyword.keys(query.path_filters)
    order = Map.get(query, :filter_order) || []
    rank = order |> Enum.with_index() |> Map.new()
    Enum.sort_by(names, &Map.get(rank, &1, length(order)))
  end

  @doc "Whether `name` is a `path_filters` entry of the query."
  @spec path_filter?(t(), atom) :: boolean
  def path_filter?(%__MODULE__{} = query, name), do: Keyword.has_key?(query.path_filters, name)

  @doc """
  The filters whose option counts the runner computes: every filter the
  query lets the client pick (`filters` and `path_filters`, less
  `hidden_filters`) when `facet_counts` is `true`, the listed ones when it
  is a list, none when `false`.
  """
  @spec faceted_filters(t()) :: [atom]
  def faceted_filters(%__MODULE__{facet_counts: true} = query),
    do: filter_names(query) -- query.hidden_filters

  def faceted_filters(%__MODULE__{facet_counts: names}) when is_list(names), do: names
  def faceted_filters(_query), do: []

  @doc "Whether a filter's picker selects several values (`multi_select_filters`)."
  @spec multi_select?(t(), atom) :: boolean
  def multi_select?(%__MODULE__{} = query, name), do: name in query.multi_select_filters

  @doc """
  The leaf values a group of `filter_groups` stands for, as strings:
  `%{"<group>" => ["<leaf>", ...]}` for `field`, `%{}` when it has none.
  """
  @spec group_leaves(t(), atom) :: %{String.t() => [String.t()]}
  def group_leaves(%__MODULE__{} = query, field) do
    query.filter_groups
    |> Keyword.get(field, [])
    |> Map.new(fn {group, leaves} -> {to_string(group), Enum.map(leaves, &to_string/1)} end)
  end
end
