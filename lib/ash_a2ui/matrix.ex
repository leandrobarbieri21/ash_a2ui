defmodule AshA2ui.Matrix do
  @moduledoc """
  Matrices: a `:table` whose records are laid out as a grid
  (`display :matrix`), one row per `row_field` value and one column per
  `column_field` value, each cell showing `cell_field`.

      a2ui do
        component :table do
          display :matrix
          row_field :case_name
          column_field :candidate
          cell_field :outcome
          query :results
        end
      end

  A matrix adds no catalog component. Its rows and columns vary with the
  data, so the server builds the grid and the composition binds to it:

    * the grid is served at the reserved root path `/_matrix_<table>`
      (`path/1`) as `%{"columns" => [%{"text" => ...}], "rows" =>
      [%{"cells" => [%{"text" => ..., "recorded" => boolean}]}]}`. The first
      column is the row heading (the `row_field` label), and the first cell
      of each row is that row's value;
    * rows are the `row_field` values in the order the table reads them
      (its sort applies); columns are an enumerated `column_field`'s values
      in declaration order (an empty column is kept), else the values in
      read order;
    * a cell holds the `cell_field` display value of the first record read
      at that row and column. A cell with no record, or whose record has no
      `cell_field` value, is `"recorded" => false` with the text "Not
      recorded": a missing result is never shown as a value, and never as
      an empty string that reads like one;
    * the composition (`components/2`) is a `Column` holding a header `Row`
      templated over `columns` and a `List` of `Row`s templated over `rows`,
      each templated over its `cells`. Basic catalog only, under both
      catalogs, so a client that advertises only the basic catalog renders
      it in full.

  The table's query, filters and pagination apply to the records read, and
  the grid is built from that page: a page that splits a row's records
  shows that row partly. Give a matrix a page size that holds the grid.
  The initial data model and every records refresh driven by an action or a
  `"query"` action rewrite `/_matrix_<table>` beside the records. A
  records-only push (`encode_data_model(view, records, scope: :records)`)
  replaces `/records` alone, as it leaves board totals.

  Rules (`validate/2`, run at compile time by
  `AshA2ui.Verifiers.VerifyTableDisplays` and over composed surfaces):
  `:table` only; `row_field`, `column_field` and `cell_field` are required,
  distinct public attributes of the table's resource, among its `fields`
  when it declares them; no `sections`, `row_layout`, `row_actions`,
  `bulk_actions` or `editable`; and the three options only with
  `display :matrix`.
  """

  import AshA2ui.Gettext

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.{L10n, TypeMapper}

  @options [:row_field, :column_field, :cell_field]

  @typedoc "The resolved matrix config of a table: its three fields."
  @type config :: %{row_field: atom, column_field: atom, cell_field: atom}

  @doc """
  The resolved matrix config of a `display :matrix` table component, or
  `nil` for any other component.
  """
  @spec resolve(AshA2ui.Component.t()) :: config | nil
  def resolve(%{display: :matrix} = component) do
    %{
      row_field: component.row_field,
      column_field: component.column_field,
      cell_field: component.cell_field
    }
  end

  def resolve(_component), do: nil

  @doc "Whether a resolved table is a matrix."
  @spec matrix?(map) :: boolean
  def matrix?(table), do: not is_nil(Map.get(table, :matrix))

  @doc """
  The fields a matrix table's rows must carry for its grid (`row_field`,
  `column_field`, `cell_field`), whatever its `fields` say; `[]` for any
  other table.
  """
  @spec fields(map | nil) :: [atom]
  def fields(%{matrix: %{} = config}),
    do: [config.row_field, config.column_field, config.cell_field]

  def fields(_table), do: []

  @doc "The reserved root path a matrix table's grid is served at."
  @spec path(map) :: String.t()
  def path(table), do: "/_matrix_#{table.name}"

  @doc """
  The matrix rules of one component; `:ok` or `{:error, option, message}`.
  """
  @spec validate(AshA2ui.Component.t(), module | map | nil) :: :ok | {:error, atom, String.t()}
  def validate(%{display: :matrix} = component, resource) do
    with :ok <- validate_table(component),
         :ok <- validate_required(component),
         :ok <- validate_distinct(component),
         :ok <- validate_compatible(component) do
      validate_fields(component, resource)
    end
  end

  def validate(component, _resource) do
    case Enum.find(@options, &Map.get(component, &1)) do
      nil -> :ok
      option -> {:error, option, "#{option} is only supported with display :matrix"}
    end
  end

  defp validate_table(%{name: :table}), do: :ok

  defp validate_table(_component),
    do: {:error, :display, "display :matrix is only supported on :table components"}

  defp validate_required(component) do
    case Enum.find(@options, &is_nil(Map.get(component, &1))) do
      nil ->
        :ok

      option ->
        {:error, :display,
         "display :matrix needs #{option}: row_field, column_field and cell_field name the " <>
           "attributes that give the rows, the columns and each cell"}
    end
  end

  defp validate_distinct(component) do
    if @options |> Enum.map(&Map.get(component, &1)) |> Enum.uniq() |> length() == 3,
      do: :ok,
      else: {:error, :cell_field, "row_field, column_field and cell_field must be distinct"}
  end

  defp validate_compatible(component) do
    case Enum.find(
           [
             sections: "a sections block",
             row_layout: "a row_layout",
             row_actions: "row_actions",
             bulk_actions: "bulk_actions",
             editable: "an editable block"
           ],
           fn {option, _what} -> Map.get(component, option) not in [nil, []] end
         ) do
      nil -> :ok
      {option, what} -> {:error, option, "a display :matrix table cannot declare #{what}"}
    end
  end

  defp validate_fields(_component, nil), do: :ok

  defp validate_fields(component, resource) do
    Enum.reduce_while(@options, :ok, fn option, :ok ->
      field = Map.get(component, option)

      cond do
        not match?(%{public?: true}, ResourceInfo.attribute(resource, field)) ->
          {:halt,
           {:error, option,
            "#{option} #{inspect(field)} must be a public attribute of the table's resource"}}

        is_list(component.fields) and field not in component.fields ->
          {:halt,
           {:error, option,
            "#{option} #{inspect(field)} must be one of the table's fields " <>
              "(#{inspect(component.fields)})"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  @doc """
  The grid of a matrix `table` over its serialized `rows` (the rows the
  encoder writes at the table's records path), with headings from `labels`
  (field name to display label) and text translated with `l10n`. See the
  module documentation for the shape.
  """
  @spec data(map, [map], %{atom => String.t()}, L10n.t() | nil) :: map
  def data(%{matrix: config} = table, rows, labels, l10n) do
    row_keys = keys(rows, config.row_field)

    column_keys =
      case TypeMapper.choices(table.resource, config.column_field, l10n) do
        [] -> keys(rows, config.column_field)
        choices -> Enum.map(choices, fn {value, label} -> {to_string(value), label} end)
      end

    cells =
      Enum.reduce(rows, %{}, fn row, acc ->
        Map.put_new(
          acc,
          {key(row, config.row_field), key(row, config.column_field)},
          row[to_string(config.cell_field)]
        )
      end)

    missing = L10n.t(l10n, msg("Not recorded"))

    %{
      "columns" =>
        [%{"text" => Map.fetch!(labels, config.row_field)}] ++
          Enum.map(column_keys, fn {_key, label} -> %{"text" => label} end),
      "rows" =>
        Enum.map(row_keys, fn {row_key, row_label} ->
          %{
            "cells" =>
              [%{"text" => row_label, "recorded" => true}] ++
                Enum.map(column_keys, fn {column_key, _label} ->
                  case Map.get(cells, {row_key, column_key}) do
                    nil -> %{"text" => missing, "recorded" => false}
                    value -> %{"text" => text(value), "recorded" => true}
                  end
                end)
          }
        end)
    }
  end

  # The distinct values of `field` over `rows`, in read order, as
  # {key, display label}: the raw value of a rewritten choice (`_values`) is
  # the key, so two values with one label stay apart.
  defp keys(rows, field) do
    rows
    |> Enum.map(&{key(&1, field), text(&1[to_string(field)])})
    |> Enum.uniq_by(&elem(&1, 0))
  end

  defp key(row, field) do
    name = to_string(field)

    case row do
      %{"_values" => %{^name => value}} -> text(value)
      _plain -> text(row[name])
    end
  end

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: value
  defp text(%Decimal{} = value), do: Decimal.to_string(value)
  defp text(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp text(value), do: inspect(value)

  @doc """
  The basic composition of a matrix table under the multi-table suffix
  `sfx`: its root is `matrix<sfx>`.
  """
  @spec components(map, String.t()) :: [map]
  def components(table, sfx) do
    base = "matrix#{sfx}"
    path = path(table)

    [
      %{"id" => base, "component" => "Column", "children" => ["#{base}_head", "#{base}_body"]},
      %{
        "id" => "#{base}_head",
        "component" => "Row",
        "children" => %{"componentId" => "#{base}_heading", "path" => "#{path}/columns"}
      },
      %{
        "id" => "#{base}_heading",
        "component" => "Text",
        "text" => %{"path" => "text"},
        "variant" => "h5"
      },
      %{
        "id" => "#{base}_body",
        "component" => "List",
        "children" => %{"componentId" => "#{base}_row", "path" => "#{path}/rows"}
      },
      %{
        "id" => "#{base}_row",
        "component" => "Row",
        "children" => %{"componentId" => "#{base}_cell", "path" => "cells"}
      },
      %{"id" => "#{base}_cell", "component" => "Text", "text" => %{"path" => "text"}}
    ]
  end
end
