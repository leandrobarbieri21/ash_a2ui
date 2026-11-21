defmodule AshA2ui.ReviewSummary do
  @moduledoc """
  Target struct for the `review_summary` DSL entity (admin catalog 3.6): an
  `alert` `:detail` that sums up the review of the record its context
  selects — how many of the surface's `review` fields still wait for a
  person, and a link to the first one.

  A field waits while its review's state is `pending` or `missing` (see
  `AshA2ui.Review`): filled in automatically and not checked, or looked for
  and not found, and not checked either.

  A table's rows count too (catalog 3.9): a table filtered by this context
  alone (every `context_filter` entry names it) whose fields include
  `review` fields counts each of its rows with one waiting, once, however
  many of that row's fields wait. The summary reads those rows itself,
  through the table's read action, as the reader, scoped to the record and
  in the table's `default_sort`.

  So do the items of such a table's `pairs` fields (catalog 3.10): each
  item whose own review waits counts once (see `AshA2ui.Pairs`), as each
  has its own button. A row's review fields and its items count in the
  table's field order.

  "First" is the surface's declaration order: its `:detail` components and
  those tables in order, each card's fields in order, each table's rows in
  order. The link goes to the section of the card or table holding it: its
  `section_nav` entry's `#anchor` when the nav lists the section, else the
  section's own id (`#section_<component>`). With nothing waiting it is
  `fallback_href`, worded `fallback_label`.

  The record carries the summary at `/detail/<context>/_review_summary_<component>`:

      %{
        "count" => 2,                 # fields (and rows) still waiting
        "field" => "fee",             # the first one's field ("" when none)
        "href" => "#overview",        # where the link goes ("" for no link)
        "label" => "Go to first flagged field"
      }

  See `data/4`.
  """

  alias AshA2ui.{ContextRunner, Label, Pairs, QueryRunner, ResolvedView, Review}

  defstruct [
    :link_label,
    :fallback_href,
    :fallback_label,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          link_label: String.t() | nil,
          fallback_href: String.t() | nil,
          fallback_label: String.t() | nil
        }

  @waiting ~w(pending missing)

  @doc "The data key a summary component's record carries its summary at."
  @spec key(AshA2ui.Component.t()) :: String.t()
  def key(component), do: "_review_summary_#{AshA2ui.Component.key(component)}"

  @doc """
  The review summaries of `context`'s record: one `_review_summary_<component>`
  per `:detail` component of that context declaring a `review_summary`.
  `opts` are the read options (`:actor`, `:tenant`, ...) a counted table's
  rows are read with.
  """
  @spec data(ResolvedView.t(), atom, struct(), keyword) :: %{String.t() => map}
  def data(view, context, record, opts \\ []) do
    case for(
           %{component: %{review_summary: %__MODULE__{}} = component} <- view.details,
           component.context == context,
           do: component
         ) do
      [] ->
        %{}

      components ->
        waiting = waiting(view, context, record, opts)
        Map.new(components, &{key(&1), summary(view, &1.review_summary, waiting)})
    end
  end

  defp summary(view, summary, waiting) do
    case waiting do
      [{_key, field, component} | _rest] ->
        %{
          "count" => length(waiting),
          "field" => to_string(field),
          "href" => href(view, component),
          "label" => translate(view, summary.link_label || "Go to the first field to review")
        }

      [] ->
        %{
          "count" => 0,
          "field" => "",
          "href" => summary.fallback_href || "",
          "label" => (summary.fallback_label && translate(view, summary.fallback_label)) || ""
        }
    end
  end

  # What still waits on `record`, in declaration order, as `{key, field,
  # component}`: each review field of its cards (a field on two cards counts
  # once) and each row of its counted tables.
  defp waiting(view, context, record, opts) do
    details = Map.new(view.details, &{&1.component, &1})
    tables = Map.new(view.tables, &{&1.component, &1})

    view.components
    |> Enum.flat_map(fn component ->
      cond do
        detail = details[component] -> detail_waiting(view, context, record, detail)
        table = tables[component] -> rows_waiting(view, context, record, table, opts)
        true -> []
      end
    end)
    |> Enum.uniq_by(fn {key, _field, _component} -> key end)
  end

  defp detail_waiting(view, context, record, detail) do
    if detail.context == context and is_nil(detail.component.alert) do
      for field <- detail.fields,
          %AshA2ui.Field{review: source} when not is_nil(source) <- [view.fields[field]],
          waiting?(Map.get(record, source)),
          do: {field, field, detail.component}
    else
      []
    end
  end

  # A table's rows, once each, while one of its review fields waits, and
  # each waiting item of its `pairs` fields (3.10), in column order. A
  # table naming the context in `context_record` reads them with `record`
  # handed, as it reads its own rows.
  defp rows_waiting(view, context, record, table, opts) do
    opts = with_read_context(opts, table, %{context => record})

    with [_ | _] = fields <- counted_fields(view, table),
         {:ok, scope} <- scope(view, context, record, table),
         {:ok, rows} <- read_rows(table, fields, scope, opts) do
      for row <- rows,
          field <- fields,
          key <- row_waiting(table, row, field),
          do: {key, field.name, table.component}
    else
      _none -> []
    end
  end

  defp with_read_context(opts, table, records) do
    case ContextRunner.read_context(table, records) do
      context when context == %{} -> opts
      context -> Keyword.put(opts, :context, context)
    end
  end

  # A review field's wait is the row's (keyed by the row, so it counts
  # once); a pairs field's are its items' (keyed by the item).
  defp row_waiting(table, row, %AshA2ui.Field{pairs: true, name: name}) do
    row
    |> Map.get(name)
    |> Pairs.normalize()
    |> Enum.with_index()
    |> Enum.filter(fn {item, _index} -> Pairs.waiting?(item) end)
    |> Enum.map(fn {item, index} ->
      {table.name, Map.get(row, :id), name, Map.get(item, "key", index)}
    end)
  end

  defp row_waiting(table, row, %AshA2ui.Field{review: source}) do
    if waiting?(Map.get(row, source)), do: [{table.name, Map.get(row, :id)}], else: []
  end

  defp counted_fields(view, table) do
    for name <- table.component.fields || [],
        %AshA2ui.Field{} = field <- [view.fields[name]],
        field.pairs == true or not is_nil(field.review),
        do: field
  end

  # Only a table filtered by this context alone: its rows are this record's.
  defp scope(view, context, record, %{context_filter: [_ | _] = filter}) do
    if Enum.all?(filter, &match?({_attribute, ^context}, &1)) do
      value = Map.get(record, view.contexts[context].option_value)
      {:ok, Enum.map(filter, fn {attribute, _context} -> {attribute, value} end)}
    else
      :not_counted
    end
  end

  defp scope(_view, _context, _record, _table), do: :not_counted

  defp read_rows(table, fields, scope, opts) do
    loads =
      for field <- fields,
          source = if(field.pairs == true, do: field.name, else: field.review),
          ResolvedView.calculation_or_aggregate?(table.resource, source),
          uniq: true,
          do: source

    sort = (table.query && table.query.default_sort) || []

    table
    |> QueryRunner.preset_read(nil, opts)
    |> ContextRunner.apply_scope(scope)
    |> Ash.Query.sort(sort)
    |> Ash.Query.load(loads)
    |> Ash.read()
  end

  defp waiting?(value),
    do: match?(%{"state" => state} when state in @waiting, Review.normalize(value))

  # The section a card sits in: its nav entry's anchor, else the section's id.
  defp href(view, component) do
    case section_start(view, component) do
      nil ->
        "#detail_#{AshA2ui.Component.key(component)}"

      start ->
        anchor =
          view.section_nav &&
            Enum.find_value(view.section_nav.items, &(&1.component == start && &1.anchor))

        "#" <> (anchor || "section_#{start}")
    end
  end

  defp section_start(_view, %{section: nil}), do: nil

  defp section_start(view, component) do
    view.components
    |> Enum.chunk_by(&Map.get(&1, :section))
    |> Enum.find_value(fn [first | _] = run ->
      if Enum.any?(run, &(&1 == component)), do: AshA2ui.Component.key(first)
    end)
  end

  defp translate(view, text), do: Label.translate(view.l10n, text)

  @doc "The words a summary shows, for the metadata template."
  @spec texts(t()) :: [String.t()]
  def texts(%__MODULE__{} = summary),
    do:
      Enum.reject(
        [summary.link_label || "Go to the first field to review", summary.fallback_label],
        &is_nil/1
      )
end
