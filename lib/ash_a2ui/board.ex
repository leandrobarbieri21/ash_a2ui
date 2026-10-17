defmodule AshA2ui.Board do
  @moduledoc """
  Boards: a sectioned `:table` whose sections are the enumerated values of an
  attribute, rendered as lanes side by side (`display :board`).

  A board adds no component kind. It rides on `sections` (see
  `AshA2ui.Sections`): a `sections` block without a `source` enumerates its
  sections from `scope_by`'s values — an `Ash.Type.Enum`'s `values/0`, or
  the attribute's (or calculation's) `one_of` constraint — in declaration
  order, narrowed and reordered by `values` and headed per `labels`. Each
  lane is an ordinary expanded table: runtime name
  `<template_key>_<sanitized value>`, records at `/records/<lane>`, query
  state at `/query/<lane>`, reads ANDed with `scope_by == value`. No read is
  issued to enumerate the lanes, and an empty lane is kept (it renders its
  empty state).

  Cards move between lanes through **transition row actions**: actions
  gated by `visible_when` on the lane attribute that refresh the template
  key (which fans out to every lane). There is no drag-and-drop: the basic
  catalog has no pointer events.

  ## Swimlanes

  `swimlanes_by` (with optional `swimlane_values`, `swimlane_labels` and
  `swimlane_tones`) splits the board into rows by a second enumerated
  attribute. Each (swimlane, lane) pair is one expanded table, a **cell**
  (`cell?/1`), swimlane-major, named `<template_key>_<lane>__<swimlane>`
  (`cell_name/3`) and scoped by both filters (`section.filter` and
  `section.swimlane.filter`). The encoder keeps the stage columns side by
  side and stacks one row per swimlane (see the multi-section surfaces
  topic). Each swimlane's tone is served at `/_swimlane_tone_<swimlane>`
  (`swimlane_tone_path/1`); its total at `/_swimlane_total_<swimlane>` and
  each stage's at `/_lane_total_<lane>` are sums of their cells' totals
  (`aggregate_totals/2`).

  ## Lane totals

  Each lane's heading shows its total, served at the reserved root path
  `/_lane_total_<lane>` as a string: the lane query's `totalCount` when it
  has one, else the number of rows in the lane (with a `+` suffix when the
  query reports more rows but no count). The initial data model, refreshes
  driven by actions (`refreshes`) and `"query"` actions rewrite it beside
  the lane's records. A records-only push
  (`encode_data_model(view, records, scope: :records)`) replaces `/records`
  alone and leaves every `/_lane_total_<lane>` as it was, like the
  `_empty_visible` sentinels: push a full data model when the totals must
  move with the records.

  ## Lanes and `limit`

  On sections without a source, `limit` caps the number of lanes, not the
  cards per lane: a lane's page size comes from its query (`page_size`).
  The verifier rejects a `limit` below the number of lanes, so no lane is
  dropped silently.

  The vocabulary (kanban lanes over an attribute's values) comes from
  PyroManiac (<https://github.com/frankdugan3/pyro_maniac>), an Ash UI DSL.
  This is our own implementation over `sections`; see
  `notes/2026-10-15-pyro-maniac-borrowings.md`.
  """

  @typedoc "One synthesized lane record (the source-less section record)."
  @type lane :: %{value: atom | String.t(), label: String.t()}

  @typedoc "One swimlane of a swimlaned board, with its tone."
  @type swimlane :: %{value: atom | String.t(), label: String.t(), tone: String.t()}

  @doc """
  The enumerated values of `name` on `resource` (a resource module or its
  DSL state): an `Ash.Type.Enum`'s values, else a non-empty `one_of`
  constraint. Returns `:error` when `name` is not an attribute or
  calculation, or has no enumerable values.
  """
  @spec enumerated_values(module | map, atom) :: {:ok, [atom | String.t()]} | :error
  def enumerated_values(resource, name) do
    case AshA2ui.TypeMapper.choices(resource, name) do
      [_ | _] = choices -> {:ok, Enum.map(choices, &elem(&1, 0))}
      [] -> :error
    end
  end

  @doc """
  The lanes of a source-less sections config (`%{scope_by, values, labels}`)
  over `resource`, in order: `%{value, label}` per lane. `values` picks a
  subset and an order (matched against the enumeration by string form, the
  enumerated value kept); `labels` overrides headings, which otherwise are
  the enum's label or the humanized value.

  Raises `ArgumentError` when `scope_by` has no enumerable values (the
  verifier rejects that at compile time where the resource is resolvable).
  """
  @spec lanes(module, map) :: [lane]
  def lanes(resource, config) do
    enumerate(resource, :scope_by, config.scope_by, Map.get(config, :values),
      labels: Map.get(config, :labels, [])
    )
  end

  @doc """
  The swimlanes of a source-less sections config's resolved `swimlanes`
  (`%{scope_by, values, labels, tones}`) over `resource`, top to bottom:
  `%{value, label, tone}` per swimlane, enumerated like `lanes/2` (`values`
  picks a subset and an order, `labels` overrides headings) with the tone
  of `tones` (`"neutral"` when unlisted). `[]` for a board without
  swimlanes (`nil`).

  Raises `ArgumentError` when the swimlane attribute has no enumerable
  values (the verifier rejects that at compile time where the resource is
  resolvable).
  """
  @spec swimlanes(module, map | nil) :: [swimlane]
  def swimlanes(_resource, nil), do: []

  def swimlanes(resource, swimlanes) do
    tones = Map.get(swimlanes, :tones, [])

    resource
    |> enumerate(:swimlanes_by, swimlanes.scope_by, Map.get(swimlanes, :values),
      labels: Map.get(swimlanes, :labels, [])
    )
    |> Enum.map(&Map.put(&1, :tone, swimlane_tone(&1.value, tones)))
  end

  defp enumerate(resource, option, attribute, values, opts) do
    case AshA2ui.TypeMapper.choices(resource, attribute) do
      [_ | _] = choices ->
        all = Enum.map(choices, &elem(&1, 0))

        values
        |> chosen_values(all)
        |> Enum.map(fn value ->
          %{value: value, label: lane_label(value, opts[:labels], choices)}
        end)

      [] ->
        raise ArgumentError,
              "sections without a source need enumerable values: #{option} " <>
                "#{inspect(attribute)} of #{inspect(resource)} is neither an " <>
                "Ash.Type.Enum nor constrained by one_of"
    end
  end

  defp swimlane_tone(value, tones) do
    case Enum.find(tones, fn {key, _tone} -> to_string(key) == to_string(value) end) do
      {_key, tone} -> to_string(tone)
      nil -> "neutral"
    end
  end

  @doc """
  The enumerated value matching `value` by string form, or `nil`.
  """
  @spec match_value(atom | String.t(), [atom | String.t()]) :: atom | String.t() | nil
  def match_value(value, all) do
    string = to_string(value)
    Enum.find(all, &(to_string(&1) == string))
  end

  @doc """
  Whether an (expanded) resolved table is a board lane — on a swimlaned
  board, a cell (see `cell?/1`).
  """
  @spec lane?(map) :: boolean
  def lane?(%{component: %{display: :board}, section: %{}}), do: true
  def lane?(_table), do: false

  @doc "Whether an (expanded) resolved table is a cell of a swimlaned board."
  @spec cell?(map) :: boolean
  def cell?(%{component: %{display: :board}, section: %{swimlane: %{}}}), do: true
  def cell?(_table), do: false

  @doc """
  The runtime name of a swimlane row: the template key and the sanitized
  swimlane value joined by `__` (`swimlane_name(:board, :very_high) ==
  "board__very_high"`). A cell's runtime name is its lane's runtime name
  plus the same `__<swimlane>` suffix (`board_open__very_high`).
  """
  @spec swimlane_name(atom | String.t(), term) :: String.t()
  def swimlane_name(template_key, value) do
    "#{template_key}__#{AshA2ui.Sections.sanitize(value)}"
  end

  @doc "The runtime name of the cell of `lane` and `swimlane` on `template_key`'s board."
  @spec cell_name(atom | String.t(), term, term) :: String.t()
  def cell_name(template_key, lane, swimlane) do
    "#{AshA2ui.Sections.section_name(template_key, lane)}__#{AshA2ui.Sections.sanitize(swimlane)}"
  end

  @doc "The reserved root data-model path of a swimlane row's tone."
  @spec swimlane_tone_path(String.t()) :: String.t()
  def swimlane_tone_path(swimlane_name), do: "/_swimlane_tone_#{swimlane_name}"

  @doc "The reserved root data-model path of a swimlane row's total."
  @spec swimlane_total_path(String.t()) :: String.t()
  def swimlane_total_path(swimlane_name), do: "/_swimlane_total_#{swimlane_name}"

  @doc """
  The reserved root data-model path of a stage column's total on a
  swimlaned board: `/_lane_total_<lane>`, with the lane's own runtime name
  (the path a lane-only board's lane total has).
  """
  @spec stage_total_path(String.t()) :: String.t()
  def stage_total_path(lane_name), do: "/_lane_total_#{lane_name}"

  @doc """
  The rows and columns of a swimlaned board's cells (each in board order):
  `{[{swimlane_name, cells}], [{lane_name, cells}]}`. Empty for a board
  without swimlanes.
  """
  @spec grid([map]) :: {[{String.t(), [map]}], [{String.t(), [map]}]}
  def grid(cells) do
    cells = Enum.filter(cells, &cell?/1)
    {group_in_order(cells, & &1.section.swimlane.name), group_in_order(cells, & &1.section.lane)}
  end

  @doc """
  The swimlane-row and stage-column totals of a swimlaned board, as
  `{path, text}` pairs, from the cell totals in `cell_totals` (cell runtime
  name => total text, see `total_text/2`): a row's (or column's) total is
  the sum of its cells', suffixed `+` when any cell's is. Only rows and
  columns whose every cell has a total in `cell_totals` are returned, so a
  refresh covering some cells leaves the others' aggregates as they were.
  """
  @spec aggregate_totals([map], %{String.t() => String.t()}) :: [{String.t(), String.t()}]
  def aggregate_totals(tables, cell_totals) do
    {rows, columns} = grid(tables)

    Enum.flat_map(rows, fn {name, cells} ->
      aggregate(swimlane_total_path(name), cells, cell_totals)
    end) ++
      Enum.flat_map(columns, fn {name, cells} ->
        aggregate(stage_total_path(name), cells, cell_totals)
      end)
  end

  defp aggregate(path, cells, cell_totals) do
    texts = Enum.map(cells, &Map.get(cell_totals, &1.name))

    if Enum.all?(texts, &is_binary/1) do
      sum =
        texts |> Enum.map(&(&1 |> String.trim_trailing("+") |> String.to_integer())) |> Enum.sum()

      more? = Enum.any?(texts, &String.ends_with?(&1, "+"))
      [{path, if(more?, do: "#{sum}+", else: Integer.to_string(sum))}]
    else
      []
    end
  end

  defp group_in_order(cells, key_fun) do
    cells
    |> Enum.reduce({[], %{}}, fn cell, {order, groups} ->
      key = key_fun.(cell)
      order = if Map.has_key?(groups, key), do: order, else: [key | order]
      {order, Map.update(groups, key, [cell], &[cell | &1])}
    end)
    |> then(fn {order, groups} ->
      order |> Enum.reverse() |> Enum.map(&{&1, Enum.reverse(Map.fetch!(groups, &1))})
    end)
  end

  @doc "The reserved root data-model path of a lane's total."
  @spec total_path(map) :: String.t()
  def total_path(table), do: "/_lane_total_#{table.name}"

  @doc """
  The lane total text for `row_count` rows and the lane's `/query` state
  (`nil` for lanes without a query): `totalCount` when known, else the row
  count, suffixed `+` when the query reports more rows.
  """
  @spec total_text(non_neg_integer, map | nil) :: String.t()
  def total_text(_row_count, %{"totalCount" => total}) when is_integer(total),
    do: Integer.to_string(total)

  def total_text(row_count, %{"hasMore" => true}), do: "#{row_count}+"
  def total_text(row_count, _state), do: Integer.to_string(row_count)

  @doc """
  The lanes of the board whose template key is `template`, in order.
  """
  @spec template_lanes([map], atom | String.t()) :: [map]
  def template_lanes(tables, template) do
    Enum.filter(tables, &(lane?(&1) and &1.section.template == template))
  end

  # --- enumeration ---

  # Duplicates, and entries whose runtime lane names collide, keep their
  # first occurrence: the verifier rejects both at compile time, and this
  # keeps component ids and data-model paths unique where it could not run.
  defp chosen_values(values, all) do
    (values || all)
    |> Enum.map(&match_value(&1, all))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&AshA2ui.Sections.section_name(:lane, &1))
  end

  # Headings: a `labels` override, else the shared choice label
  # (`AshA2ui.TypeMapper.choices/2`, the ChoicePicker's labels).
  defp lane_label(value, nil, choices), do: lane_label(value, [], choices)

  defp lane_label(value, labels, choices) do
    case Enum.find(labels, fn {key, _label} -> to_string(key) == to_string(value) end) do
      {_key, label} -> to_string(label)
      nil -> choices |> List.keyfind(value, 0) |> elem(1)
    end
  end
end
