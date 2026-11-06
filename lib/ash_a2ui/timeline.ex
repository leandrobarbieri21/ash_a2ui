defmodule AshA2ui.Timeline do
  @moduledoc """
  Timelines: a `:table` whose rows are read in time order and each led by
  its moment (`display :timeline`).

      a2ui do
        query :history do
          page_size 50
        end

        component :table do
          display :timeline
          date_field :occurred_at
          fields [:summary, :outcome]
          query :history
        end
      end

  A timeline adds no component kind and no catalog component. It is the
  table's own list, so everything a list does (queries, filters, row
  actions, pagination, empty state) works unchanged, plus:

    * **Order.** Without a declared or requested sort the table's query
      reads in `date_field` order, oldest first. A declared `default_sort`
      or a requested sort still wins. A table without a `query` shows its
      records in the order the host passes them.
    * **The moment.** Each row carries `_timeline_at` (the ISO 8601 value,
      `""` when the record has none) and `_timeline_when` (the date, or the
      date and minute in the configured time zone, as calendars write it).
      Each basic row starts with a caption Text bound to `_timeline_when`.

  Both catalogs render the same basic composition: under the admin catalog
  a timeline does not become a `dataGrid` (whose columns would lose the
  leading moment), as a board does not. A client that advertises only the
  basic catalog therefore renders it in full.

  Rules (`validate/2`, run at compile time by
  `AshA2ui.Verifiers.VerifyTableDisplays` and over composed surfaces):
  `:table` only, a `date_field` that is a public date or datetime attribute,
  and no `sections` block.
  """

  alias AshA2ui.Calendar

  @typedoc "The resolved timeline config of a table."
  @type config :: %{date_field: atom}

  @doc """
  The resolved timeline config of a `display :timeline` table component, or
  `nil` for any other component.
  """
  @spec resolve(AshA2ui.Component.t(), module) :: config | nil
  def resolve(%{display: :timeline, date_field: date_field}, _resource)
      when not is_nil(date_field),
      do: %{date_field: date_field}

  def resolve(_component, _resource), do: nil

  @doc "Whether a resolved table is a timeline."
  @spec timeline?(map) :: boolean
  def timeline?(table), do: not is_nil(Map.get(table, :timeline))

  @doc """
  The timeline rules of one component; `:ok` or `{:error, option, message}`.
  Any component other than a `display :timeline` one is `:ok` here.
  """
  @spec validate(AshA2ui.Component.t(), module | map | nil) :: :ok | {:error, atom, String.t()}
  def validate(%{display: :timeline} = component, resource) do
    cond do
      component.name != :table ->
        {:error, :display, "display :timeline is only supported on :table components"}

      is_nil(component.date_field) ->
        {:error, :display,
         "display :timeline needs a date_field: the date or datetime attribute that orders " <>
           "the records"}

      not is_nil(component.sections) ->
        {:error, :sections, "a display :timeline table cannot declare a sections block"}

      is_nil(resource) or Calendar.field_kind(resource, component.date_field) ->
        :ok

      true ->
        {:error, :date_field,
         "date_field #{inspect(component.date_field)} must be a public :date or datetime " <>
           "attribute of the table's resource"}
    end
  end

  def validate(_component, _resource), do: :ok

  @doc """
  The sort a timeline table reads with: `sort` when one is declared or
  requested, else `date_field` ascending. Any other table's `sort` is
  returned as given.
  """
  @spec read_sort(list, config | nil) :: list
  def read_sort([], %{date_field: date_field}), do: [{date_field, :asc}]
  def read_sort(sort, _config), do: sort

  @doc """
  The reserved row keys of a timeline table's row (`%{}` for any other
  table): `_timeline_at` and `_timeline_when`.
  """
  @spec row_data(map | nil, struct) :: map
  def row_data(%{timeline: %{date_field: date_field}}, record) do
    value = Map.get(record, date_field)

    %{
      "_timeline_at" => iso8601(value),
      "_timeline_when" => Calendar.moment_text(value)
    }
  end

  def row_data(_table, _record), do: %{}

  defp iso8601(%Date{} = date), do: Date.to_iso8601(date)
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  defp iso8601(_other), do: ""
end
