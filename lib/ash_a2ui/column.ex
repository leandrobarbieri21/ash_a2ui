defmodule AshA2ui.Column do
  @moduledoc """
  Target struct for the `column` DSL entity — how a `:table` component's
  data grid draws one field's cell beyond its value: a second line under
  it (`subtitle`), a leading icon chosen per row (`icon`), a "+N more" tag
  from a count (`more`) and a detail line under it (`detail`).

  The fields a column reads from (`subtitle`, `icon`, `more`, `detail`,
  `detail_date`) are table fields, so rows carry them; the data grid draws
  them inside the column rather than as columns of their own.
  """

  defstruct [
    :name,
    :subtitle,
    :icon,
    :more,
    :detail,
    :detail_date,
    icon_names: [],
    icon_tones: [],
    icon_labels: [],
    detail_text: [],
    detail_icon_names: [],
    detail_icon_tones: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom,
          subtitle: atom | nil,
          icon: atom | nil,
          icon_names: keyword(atom),
          icon_tones: keyword(atom),
          icon_labels: keyword(String.t()),
          more: atom | nil,
          detail: atom | nil,
          detail_date: atom | nil,
          detail_text: keyword(String.t()),
          detail_icon_names: keyword(atom),
          detail_icon_tones: keyword(atom)
        }

  @icons ~w(check x user_check user_x alert clock info refresh extend)a

  @doc """
  The icon vocabulary `icon_names` values are drawn from. Generic names;
  each renderer maps them onto its own icon set.
  """
  @spec icons() :: [atom]
  def icons, do: @icons

  @doc """
  The fields a column reads from besides its own: its subtitle, icon,
  count, detail and detail date fields, in that order.
  """
  @spec source_fields(t()) :: [atom]
  def source_fields(column) do
    Enum.reject(
      [column.subtitle, column.icon, column.more, column.detail, column.detail_date],
      &is_nil/1
    )
  end

  @doc """
  The fields of a table's columns that ride in each row without being
  drawn as columns of their own.
  """
  @spec folded_fields([t()]) :: [atom]
  def folded_fields(columns), do: columns |> Enum.flat_map(&source_fields/1) |> Enum.uniq()

  @doc """
  The computed per-row keys a serialized record carries for the table's
  columns. A column with an `icon` adds `"_icon_<column>"` (the
  `icon_names` entry matching the record's value), `"_icon_tone_<column>"`
  (the `icon_tones` entry, `"neutral"` when unmatched) and
  `"_icon_label_<column>"` (the `icon_labels` entry, else the humanized
  value); a column with a `detail` adds `"_detail_<column>"` (the
  `detail_text` entry, with any `{date}` left for the renderer to fill)
  and, when it declares `detail_icon_names`, `"_detail_icon_<column>"` and
  `"_detail_icon_tone_<column>"` (the icon and tone for the line, picked
  by the same value). A nil or unmatched value serializes as `""`: no
  icon, no detail line.

  Shared by the encoder and `AshA2ui.ActionHandler` (through
  `serialize_row`) so initial renders and refreshes serialize rows
  identically.
  """
  @spec row_data([t()], Ash.Resource.record()) :: %{String.t() => String.t()}
  def row_data(columns, record) do
    columns
    |> Enum.flat_map(&column_data(&1, record))
    |> Map.new()
  end

  defp column_data(column, record) do
    icon_data(column, record) ++ detail_data(column, record)
  end

  defp icon_data(%{icon: nil}, _record), do: []

  defp icon_data(column, record) do
    value = Map.get(record, column.icon)
    name = lookup(column.icon_names, value)

    [
      {"_icon_#{column.name}", (name && to_string(name)) || ""},
      {"_icon_tone_#{column.name}", to_string(lookup(column.icon_tones, value) || :neutral)},
      {"_icon_label_#{column.name}", icon_label(column, value, name)}
    ]
  end

  defp icon_label(_column, _value, nil), do: ""
  defp icon_label(column, value, _name), do: lookup(column.icon_labels, value) || humanize(value)

  defp detail_data(%{detail: nil}, _record), do: []

  defp detail_data(column, record) do
    value = Map.get(record, column.detail)
    text = lookup(column.detail_text, value)
    [{"_detail_#{column.name}", text || ""} | detail_icon_data(column, value)]
  end

  defp detail_icon_data(%{detail_icon_names: []}, _value), do: []

  defp detail_icon_data(column, value) do
    name = lookup(column.detail_icon_names, value)

    [
      {"_detail_icon_#{column.name}", (name && to_string(name)) || ""},
      {"_detail_icon_tone_#{column.name}",
       to_string(lookup(column.detail_icon_tones, value) || :neutral)}
    ]
  end

  # Keyword keys are atoms; values arrive as atoms (enums, booleans) or as
  # strings (expression calculations), matched by name either way.
  defp lookup(_mapping, nil), do: nil
  defp lookup(mapping, value) when is_atom(value), do: Keyword.get(mapping, value)

  defp lookup(mapping, value) when is_binary(value) do
    Enum.find_value(mapping, fn {key, mapped} -> Atom.to_string(key) == value && mapped end)
  end

  defp lookup(_mapping, _value), do: nil

  defp humanize(value) do
    value |> to_string() |> String.replace("_", " ") |> String.capitalize()
  end
end
