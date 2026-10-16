defmodule AshA2ui.Bulk do
  @moduledoc """
  Bulk actions over a row selection: the `bulk_actions` option of a `:table`
  component.

  This module holds the transport-agnostic pieces that the encoder and
  `AshA2ui.ActionHandler` share: the reserved row key and result path, the
  selection parsing and caps, the authorized re-read of the selected ids,
  the outcome summary, and the basic-catalog composition (row CheckBox and
  toolbar). The handler owns the per-record dispatch, which is the same
  dispatch a single-row `invoke` uses.

  Prior art: PyroManiac (<https://github.com/frankdugan3/pyro_maniac>)
  offers bulk actions over a row selection; we borrowed the idea, not the
  code. The design record is
  `notes/2026-10-15-pyro-maniac-borrowings.md`, section 1.

  ## Data model

    * Every row of a table with bulk actions carries `"_selected"` (`false`
      on every server write; the row CheckBox toggles it client-side).
    * `/bulk/<table>/result` holds the last outcome:
      `%{"ok" => n, "failed" => n, "refused" => n, "skipped" => n,
      "errors" => [%{"id" => id, "message" => text}]}`.

  ## Selection rules (enforced by the handler)

    * The action must be in the view's union of `bulk_actions` and in the
      target table's own `bulk_actions`.
    * Ids are the `"id"` values of the carried rows whose `"_selected"` is
      `true`. Nothing else in the carried rows is read.
    * An empty selection is an error. A selection larger than the table's
      page size cap (`cap/1`) is refused.
    * Ids are re-read through the table's read under its active query
      preset (the preset's `read_action`, or the table's, with a `filter`
      preset's conditions ANDed on — see `AshA2ui.QueryRunner.preset_read/3`)
      and the table's context and section scope, as the actor. Ids the read
      does not return are counted as `refused` and are never passed to an
      action.
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ContextRunner
  alias AshA2ui.QueryRunner

  @selected_key "_selected"

  # The cap for tables without a query whose read action declares no
  # pagination: the same number as the query's default max_page_size.
  @default_cap 100

  @typedoc "One per-record outcome of a bulk run."
  @type outcome :: :ok | :skipped | {:failed, String.t(), String.t()}

  @doc "Whether `table` (a resolved table scope) declares bulk actions."
  @spec enabled?(map) :: boolean
  def enabled?(%{bulk_actions: [_ | _]}), do: true
  def enabled?(_table), do: false

  @doc """
  The reserved selection key merged into every serialized row of a table
  with bulk actions: `%{"_selected" => selected}`. `%{}` for other tables,
  so their rows are unchanged.
  """
  @spec row_data(map | nil, boolean) :: map
  def row_data(table, selected \\ false) do
    if enabled?(table), do: %{@selected_key => selected}, else: %{}
  end

  @doc "The reserved `/bulk/<table>/result` path of a table."
  @spec result_path(map) :: String.t()
  def result_path(table), do: "/bulk/#{table.name}/result"

  @doc "The initial (all-zero) result value."
  @spec empty_result() :: map
  def empty_result do
    %{"ok" => 0, "failed" => 0, "refused" => 0, "skipped" => 0, "errors" => []}
  end

  @doc """
  The initial `/bulk` state: `%{<table> => %{"result" => empty_result()}}`
  per table with bulk actions. `%{}` on surfaces without bulk actions, which
  carry no `"bulk"` key at all.
  """
  @spec state(AshA2ui.ResolvedView.t()) :: map
  def state(view) do
    for table <- view.tables, enabled?(table), into: %{} do
      {to_string(table.name), %{"result" => empty_result()}}
    end
  end

  # --- handler-side validation -------------------------------------------------

  @doc """
  The allowlisted bulk action named by the context's `"action"`: it must be
  in the view's union of `bulk_actions` (matched by string, so no atom is
  created from client input).
  """
  @spec allowed_action(AshA2ui.ResolvedView.t(), map, String.t()) ::
          {:ok, atom} | {:error, String.t()}
  def allowed_action(view, context, event \\ "bulk_invoke") do
    case Map.get(context, "action") do
      requested when is_binary(requested) ->
        case Enum.find(view.bulk_actions, &(to_string(&1) == requested)) do
          nil ->
            {:error,
             "Action #{inspect(requested)} is not allowed: it is not listed in the " <>
               "view's bulk_actions."}

          action ->
            {:ok, action}
        end

      _missing ->
        {:error, ~s(Malformed #{event} action: context is missing "action".)}
    end
  end

  @doc """
  The table a bulk event targets: the context's `"component"` when given,
  else the only table with bulk actions. The table must declare bulk
  actions (and, when `action` is given, that action).
  """
  @spec target_table(AshA2ui.ResolvedView.t(), map, atom | nil, String.t()) ::
          {:ok, map} | {:error, String.t()}
  def target_table(view, context, action, event) do
    bulk_tables = Enum.filter(view.tables, &enabled?/1)

    found =
      case {Map.get(context, "component"), bulk_tables} do
        {component, _tables} when is_binary(component) ->
          Enum.find(bulk_tables, &(to_string(&1.name) == component))

        {_missing, [only]} ->
          only

        {_missing, _several} ->
          :ambiguous
      end

    cond do
      found == :ambiguous ->
        {:error,
         ~s(Malformed #{event} action: surfaces with several bulk tables require ) <>
           ~s("component" in the context.)}

      is_nil(found) ->
        {:error, "Unknown bulk table #{inspect(Map.get(context, "component"))}."}

      action && action not in found.bulk_actions ->
        {:error,
         "Action #{inspect(to_string(action))} is not a bulk action of table " <>
           "#{inspect(to_string(found.name))}."}

      true ->
        {:ok, found}
    end
  end

  @doc """
  The selected ids of the carried rows (`context["records"]`): the `"id"`
  of every row map whose `"_selected"` is exactly `true`, deduplicated, in
  row order. Validated against the table's cap: an empty selection and an
  oversized one are errors.
  """
  @spec selection(map, map) :: {:ok, [String.t() | integer]} | {:error, String.t()}
  def selection(table, context) do
    case Map.get(context, "records") do
      rows when is_list(rows) ->
        ids = selected_ids(rows)
        cap = cap(table)

        cond do
          ids == [] ->
            {:error, "Select at least one record first."}

          length(ids) > cap ->
            {:error,
             "Too many records selected (#{length(ids)}): a bulk action runs on at most " <>
               "#{cap} records, one page."}

          true ->
            {:ok, ids}
        end

      _missing ->
        {:error, ~s(Malformed bulk_invoke action: context is missing the "records" rows.)}
    end
  end

  @doc false
  def selected_ids(rows) do
    rows
    |> Enum.flat_map(fn
      %{@selected_key => true, "id" => id} when is_binary(id) or is_integer(id) -> [id]
      _unselected_or_malformed -> []
    end)
    |> Enum.uniq()
  end

  @doc """
  The most records one bulk run accepts: the table query's
  `max_page_size`; without a query, the read action's pagination
  `default_limit` (or `max_page_size`); otherwise #{@default_cap}.
  """
  @spec cap(map) :: pos_integer
  def cap(%{query: %{max_page_size: max}}) when is_integer(max), do: max

  def cap(table) do
    case table.read_action && ResourceInfo.action(table.resource, table.read_action) do
      %{pagination: %{default_limit: limit}} when is_integer(limit) -> limit
      %{pagination: %{max_page_size: max}} when is_integer(max) -> max
      _unpaginated -> @default_cap
    end
  end

  @doc """
  The rows a `bulk_select` writes back: `"_selected"` set to `selected` on
  every row, except that "Select page" marks at most `cap/1` rows (in
  order), since a bulk run refuses a larger selection. Only a table without
  a query can show more rows than its cap: it reads every row at once.
  """
  @spec mark_rows(map, [map], boolean) :: [map]
  def mark_rows(table, rows, selected) do
    cap = cap(table)

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> Map.merge(row, row_data(table, selected and index < cap)) end)
  end

  @doc """
  The status line of a "Select page" that marked only the first `cap/1` of
  `count` rows, or `nil` when every row was marked.
  """
  @spec capped_selection_text(map, non_neg_integer, boolean) :: String.t() | nil
  def capped_selection_text(table, count, true = _selected) do
    cap = cap(table)

    if count > cap do
      "Selected the first #{cap} of #{count} records: a bulk action runs on at most " <>
        "#{cap} records."
    end
  end

  def capped_selection_text(_table, _count, _selected), do: nil

  @doc """
  The authorized, scoped re-read of the selected ids, as the actor
  (`ash_opts`): the read the table performs under the active preset of
  `params` (the handler's parsed carried query state, falling back to the
  query's `default_preset`; `nil` for a table without a query), see
  `AshA2ui.QueryRunner.preset_read/3`, with the table's context and section
  scope (`ContextRunner.table_scope/3`) and `<primary key> in ids`. Search,
  filters and paging are not applied: they narrow what the user looks at,
  while the preset decides which read the rows come from. Ids that do not
  cast to the primary key's type are dropped before the read (they are
  counted as refused like any id the read does not return).
  """
  @spec read_selected(
          map,
          QueryRunner.params() | nil,
          [term],
          [{atom, term}],
          list,
          keyword
        ) :: {:ok, [Ash.Resource.record()]} | {:error, term}
  def read_selected(table, params, ids, scope, loads, ash_opts) do
    case castable_ids(table.resource, ids) do
      [] ->
        {:ok, []}

      cast ->
        [key] = ResourceInfo.primary_key(table.resource)

        table
        |> QueryRunner.preset_read(params, ash_opts)
        |> ContextRunner.apply_scope(scope)
        |> Ash.Query.filter(^ref(key) in ^cast)
        |> Ash.Query.load(loads)
        |> Ash.read()
    end
  end

  defp castable_ids(resource, ids) do
    [key] = ResourceInfo.primary_key(resource)
    %{type: type, constraints: constraints} = ResourceInfo.attribute(resource, key)

    Enum.flat_map(ids, fn id ->
      case Ash.Type.cast_input(type, id, constraints) do
        {:ok, cast} when not is_nil(cast) -> [cast]
        _uncastable -> []
      end
    end)
  end

  # --- outcome -----------------------------------------------------------------

  @doc """
  The `/bulk/<table>/result` value of a run: `selected` ids were asked
  for, `outcomes` are the per-record outcomes of the re-read records (ids
  the re-read did not return count as refused).
  """
  @spec result(non_neg_integer, [outcome]) :: map
  def result(selected, outcomes) do
    failed = for {:failed, id, message} <- outcomes, do: %{"id" => id, "message" => message}

    %{
      "ok" => Enum.count(outcomes, &(&1 == :ok)),
      "failed" => length(failed),
      "refused" => selected - length(outcomes),
      "skipped" => Enum.count(outcomes, &(&1 == :skipped)),
      "errors" => failed
    }
  end

  @doc """
  The status line of a run, e.g. `"Approve: 4 of 5 selected records done;
  1 refused."` — named by `label` (the action's `label`) when given, else
  the humanized action name.
  """
  @spec status_text(atom, non_neg_integer, map, String.t() | nil) :: String.t()
  def status_text(action, selected, result, label \\ nil) do
    others =
      for key <- ["refused", "skipped", "failed"], result[key] > 0, do: "#{result[key]} #{key}"

    base = "#{label || humanize(action)}: #{result["ok"]} of #{selected} selected records done"

    case others do
      [] -> base <> "."
      others -> base <> "; " <> Enum.join(others, ", ") <> "."
    end
  end

  @doc """
  The typed feedback kind of a run: `"success"` when every selected record
  was written, `"error"` when none was, `"warning"` otherwise.
  """
  @spec feedback_kind(non_neg_integer, map) :: String.t()
  def feedback_kind(selected, %{"ok" => selected}), do: "success"
  def feedback_kind(_selected, %{"ok" => 0}), do: "error"
  def feedback_kind(_selected, _result), do: "warning"

  # --- basic-catalog composition ----------------------------------------------

  @doc "The id of a table's bulk toolbar Row."
  @spec toolbar_id(String.t()) :: String.t()
  def toolbar_id(sfx), do: "bulk#{sfx}_toolbar"

  @doc """
  The toolbar above a bulk table's list: one `bulk_invoke` Button per bulk
  action, then "Select page" and "Clear" (`bulk_select`). `bind` adds the
  surface's usual carried bindings (`"query"`, `"contexts"`) to a context;
  `label` names each action's button (the action's `label`).
  """
  @spec toolbar_components(map, String.t(), (map -> map), (atom -> String.t())) :: [map]
  def toolbar_components(table, sfx, bind, label \\ &humanize/1) do
    base = "bulk#{sfx}"
    records = %{"path" => table.records_path}
    component = to_string(table.name)

    # Action buttons are namespaced under "_action_" so an action named
    # :select_page or :clear cannot collide with the fixed controls.
    actions =
      Enum.map(table.bulk_actions, fn action ->
        context =
          bind.(%{"action" => to_string(action), "component" => component, "records" => records})

        button("#{base}_action_#{action}", label.(action), "bulk_invoke", context)
      end)

    selects =
      for {id, label, selected} <- [
            {"select_page", "Select page", true},
            {"clear", "Clear", false}
          ] do
        context =
          bind.(%{"component" => component, "selected" => selected, "records" => records})

        button("#{base}_#{id}", label, "bulk_select", context)
      end

    buttons = actions ++ selects

    [
      %{
        "id" => toolbar_id(sfx),
        "component" => "Row",
        "align" => "center",
        "children" => Enum.map(buttons, fn [button, _text] -> button["id"] end)
      }
      | List.flatten(buttons)
    ]
  end

  defp button(id, label, event, context) do
    [
      %{
        "id" => "#{id}_button",
        "component" => "Button",
        "child" => "#{id}_text",
        "action" => %{"event" => %{"name" => event, "context" => context}}
      },
      %{"id" => "#{id}_text", "component" => "Text", "text" => label}
    ]
  end

  @doc """
  Adds the row CheckBox (bound to the row-relative `_selected` path) to a
  bulk table's row template: first in the card header for `row_layout`
  cards, first in the row's cell Row otherwise. Other tables' components
  are returned unchanged.
  """
  @spec with_row_checkbox([map], map, String.t()) :: [map]
  def with_row_checkbox(components, table, sfx) do
    if enabled?(table) do
      checkbox_id = "record_row#{sfx}_selected"

      host_id =
        if table.component.row_layout,
          do: "record_row#{sfx}_header",
          else: "record_row#{sfx}_content"

      checkbox = %{
        "id" => checkbox_id,
        "component" => "CheckBox",
        "label" => "Select",
        "value" => %{"path" => @selected_key}
      }

      Enum.map(components, fn
        %{"id" => ^host_id, "children" => children} = host ->
          %{host | "children" => [checkbox_id | children]}

        other ->
          other
      end) ++ [checkbox]
    else
      components
    end
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
