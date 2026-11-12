defmodule AshA2ui.Column do
  @moduledoc """
  Target struct for the `column` DSL entity — how a `:table` component's
  data grid draws one field's cell beyond its value: a second line under
  it (`subtitle`), a leading icon chosen per row (`icon`), a "+N more" tag
  from a count (`more`), a detail line under it (`detail`) and a third line
  (`caption`).

  The fields a column reads from (`subtitle`, `icon`, `more`, `detail`,
  `detail_date`, `caption`) are table fields, so rows carry them; the data
  grid draws them inside the column rather than as columns of their own.
  """

  import AshA2ui.Gettext, only: [msg: 1, msg_plural: 2]

  alias AshA2ui.L10n
  alias AshA2ui.Label

  defstruct [
    :name,
    :subtitle,
    :icon,
    :more,
    :detail,
    :detail_date,
    :detail_help,
    :help_title,
    :help,
    :sort_by,
    :sort_first,
    :caption,
    :caption_text,
    :width,
    :more_values,
    :more_noun,
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
          detail_icon_tones: keyword(atom),
          detail_help: atom | nil,
          help_title: String.t() | nil,
          help: String.t() | nil,
          sort_by: atom | nil,
          sort_first: :asc | :desc | nil,
          caption: atom | nil,
          caption_text: String.t() | nil,
          width: pos_integer | nil,
          more_values: atom | nil,
          more_noun: String.t() | nil
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
  count, detail, detail date, detail help, values and caption fields, in
  that order.
  """
  @spec source_fields(t()) :: [atom]
  def source_fields(column) do
    Enum.reject(
      [
        column.subtitle,
        column.icon,
        column.more,
        column.detail,
        column.detail_date,
        Map.get(column, :detail_help),
        Map.get(column, :more_values),
        Map.get(column, :caption)
      ],
      &is_nil/1
    )
  end

  @doc """
  The wire form of a column's header help (`help_title` + `help`):
  `%{"title" => title, "body" => body}`, `nil` without `help`. The body is
  the declared text, trimmed; paragraphs stay separated by blank lines.
  """
  @spec help(t(), AshA2ui.L10n.t()) :: %{String.t() => String.t()} | nil
  def help(column, l10n \\ nil)

  def help(%{help: help} = column, l10n) when is_binary(help) do
    title = Map.get(column, :help_title)

    %{
      "title" => (title && Label.translate(l10n, title)) || "",
      "body" => Label.translate(l10n, String.trim(help))
    }
  end

  def help(_column, _l10n), do: nil

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

  A column with a `more` count adds the "+N more" tag's text, already
  pluralized for the reader: `"_more_text_<column>"` ("+2 more", `""`
  below a count of 2, as the renderer's `moreCount`), and with
  `more_values` the list's caption, `"_more_caption_<column>"` ("3
  properties", from `more_noun`; `""` for fewer than two values), and the
  tag's accessible label, `"_more_label_<column>"` ("+2 more, show all 3
  properties"; the tag's text when there is no caption).

  Shared by the encoder and `AshA2ui.ActionHandler` (through
  `serialize_row`) so initial renders and refreshes serialize rows
  identically.
  """
  @spec row_data([t()], Ash.Resource.record(), AshA2ui.L10n.t()) ::
          %{String.t() => String.t() | [String.t()]}
  def row_data(columns, record, l10n \\ nil) do
    columns
    |> Enum.flat_map(&column_data(&1, record, l10n))
    |> Map.new()
  end

  defp column_data(column, record, l10n) do
    icon_data(column, record, l10n) ++
      detail_data(column, record, l10n) ++
      more_values_data(column, record) ++ more_text_data(column, record, l10n)
  end

  # `more_values`: every value behind the "+N more" tag, as strings.
  defp more_values_data(%{more_values: field} = column, record) when not is_nil(field),
    do: [{"_more_values_#{column.name}", more_values(record, field)}]

  defp more_values_data(_column, _record), do: []

  defp more_values(record, field) do
    record
    |> Map.get(field)
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  # The tag's words are written here, not in the renderer, because a count
  # needs its plural form, and only the server knows the reader's locale.
  defp more_text_data(%{more: nil}, _record, _l10n), do: []

  defp more_text_data(column, record, l10n) do
    shown = more_shown(Map.get(record, column.more))

    text =
      if shown > 0,
        do: L10n.tn(l10n, msg_plural("+%{count} more", "+%{count} more"), shown),
        else: ""

    caption = more_caption(column, record, l10n)

    label =
      cond do
        text == "" -> ""
        caption == "" -> text
        true -> L10n.t(l10n, msg("%{more}, show all %{list}"), more: text, list: caption)
      end

    [
      {"_more_text_#{column.name}", text},
      {"_more_caption_#{column.name}", caption},
      {"_more_label_#{column.name}", label}
    ]
  end

  # The values after the first: a count of 2 or more shows N - 1.
  defp more_shown(count) when is_integer(count) and count >= 2, do: count - 1

  defp more_shown(count) when is_binary(count) do
    case Integer.parse(count) do
      {n, ""} -> more_shown(n)
      _other -> 0
    end
  end

  defp more_shown(_count), do: 0

  # The list's caption, for the list `more_values` holds: shown only with
  # two values or more, so the noun is always the declared plural.
  defp more_caption(%{more_values: nil}, _record, _l10n), do: ""

  defp more_caption(column, record, l10n) do
    case length(more_values(record, column.more_values)) do
      count when count < 2 ->
        ""

      count ->
        case Map.get(column, :more_noun) do
          nil ->
            L10n.tn(l10n, msg_plural("%{count} item", "%{count} items"), count)

          noun ->
            L10n.t(l10n, msg("%{count} %{noun}"),
              count: count,
              noun: Label.translate(l10n, noun)
            )
        end
    end
  end

  defp icon_data(%{icon: nil}, _record, _l10n), do: []

  defp icon_data(column, record, l10n) do
    value = Map.get(record, column.icon)
    name = lookup(column.icon_names, value)

    [
      {"_icon_#{column.name}", (name && to_string(name)) || ""},
      {"_icon_tone_#{column.name}", to_string(lookup(column.icon_tones, value) || :neutral)},
      {"_icon_label_#{column.name}", icon_label(column, value, name, l10n)}
    ]
  end

  defp icon_label(_column, _value, nil, _l10n), do: ""

  defp icon_label(column, value, _name, l10n),
    do: Label.translate(l10n, lookup(column.icon_labels, value) || Label.humanize(value))

  defp detail_data(%{detail: nil}, _record, _l10n), do: []

  defp detail_data(column, record, l10n) do
    value = Map.get(record, column.detail)
    text = lookup(column.detail_text, value)

    [
      {"_detail_#{column.name}", (text && Label.translate(l10n, text)) || ""}
      | detail_icon_data(column, value)
    ] ++
      detail_help_data(column, record)
  end

  defp detail_help_data(%{detail_help: field} = column, record) when not is_nil(field) do
    help =
      case Map.get(record, field) do
        nil -> ""
        value when is_binary(value) -> value
        value -> to_string(value)
      end

    [{"_detail_help_#{column.name}", help}]
  end

  defp detail_help_data(_column, _record), do: []

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
end
