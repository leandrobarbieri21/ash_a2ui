defmodule AshA2ui.ContextRunner do
  @moduledoc """
  Runtime for surface contexts: sanitizes client-carried `/context` state,
  loads context option lists (dependency-filtered), validates selections
  through authorized reads, computes selection cascades (dependent contexts
  clear and re-derive when a parent changes), and scopes table reads.

  ## The `/context` data-model state

  Surfaces with `context` entities carry one entry per context at
  `/context/<name>`:

      %{"search" => "", "value" => "<selected id or ''>", "label" => "<selected label or ''>"}

  Client actions (`context_search` / `context_select` / `context_clear` —
  and, additively, `query` / `submit_form` / `invoke` on context-enabled
  surfaces) carry the whole `/context` map under `"contexts"`; the server
  treats it as scoping input only:

    * the *changed* context's value is always validated through an
      **authorized read** (dependency filter included — a value outside the
      parent's scope is rejected), so the UI can never select a record the
      actor cannot read;
    * *carried* values of other contexts only ever become equality filters
      on reads that themselves run with the surface's
      `actor:`/`tenant:`/`authorize?:` — like query filters and presets,
      contexts are UX scoping, not a security boundary. Authorization stays
      in Ash policies.

  Values that don't cast to the target attribute's type are treated as
  unselected.
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  @typedoc "Sanitized selection state: only declared, selected contexts."
  @type selected :: %{atom => %{value: String.t(), label: String.t()}}

  @typedoc """
  The result of a selection change (`select/5` / `clear/4`): the new
  sanitized selection state, the context names whose selection changed (in
  declaration order), and the refreshed option lists of dependent picker
  contexts.
  """
  @type change :: %{
          selected: selected,
          changed: [atom],
          options: %{atom => [map]}
        }

  @doc """
  Sanitizes a client-carried `/context` map into the selected-values state:
  only declared context names are kept, and only entries whose `"value"` is
  a non-empty string count as selected. Anything else (missing, malformed,
  cleared) is simply not selected.
  """
  @spec selected(ResolvedView.t(), term) :: selected
  def selected(view, carried) do
    carried = if is_map(carried), do: carried, else: %{}

    view.contexts
    |> Enum.flat_map(fn {name, _context} ->
      case Map.get(carried, to_string(name)) do
        %{"value" => value} = entry when is_binary(value) and value != "" ->
          label = Map.get(entry, "label")
          [{name, %{value: value, label: (is_binary(label) && label) || ""}}]

        _unselected ->
          []
      end
    end)
    |> Map.new()
  end

  @doc """
  The `/context` data-model value for a selection state: every declared
  context present, selected ones carrying their value/label.
  """
  @spec state(ResolvedView.t(), selected) :: %{String.t() => map}
  def state(view, selected) do
    Map.new(view.contexts, fn {name, _context} ->
      case Map.get(selected, name) do
        nil ->
          {to_string(name), %{"search" => "", "value" => "", "label" => ""}}

        %{value: value, label: label} ->
          {to_string(name), %{"search" => "", "value" => value, "label" => label}}
      end
    end)
  end

  @doc """
  The scope filters a table's reads must AND on: one `{attribute, cast
  value}` per `context_filter` entry whose context is selected (values that
  don't cast are treated as unselected), plus — on the expanded tables of a
  dynamic table set (see `AshA2ui.Sections`) — the table's section filter.
  Returns `:require_unmet` when the table declares `require_context` and
  none of those contexts are selected — the table must render no records
  and execute no read.
  """
  @spec table_scope(ResolvedView.t(), ResolvedView.table() | map, selected) ::
          {:ok, [{atom, term}]} | :require_unmet
  def table_scope(_view, table, selected) do
    context_filter = Map.get(table, :context_filter) || []
    require_context = Map.get(table, :require_context) || []

    scope =
      Enum.flat_map(context_filter, fn {attribute, context_name} ->
        with %{value: value} <- Map.get(selected, context_name, :unselected),
             {:ok, cast} <- cast_attribute(table.resource, attribute, value) do
          [{attribute, cast, context_name}]
        else
          _unselected_or_uncastable -> []
        end
      end)

    require_met? =
      require_context == [] or
        Enum.any?(scope, fn {_attribute, _cast, name} -> name in require_context end)

    if require_met? do
      {:ok,
       section_scope(table) ++
         Enum.map(scope, fn {attribute, cast, _name} -> {attribute, cast} end)}
    else
      :require_unmet
    end
  end

  # A section's own filter, plus a swimlaned board cell's swimlane filter.
  defp section_scope(table) do
    case Map.get(table, :section) do
      %{filter: {attribute, value}, swimlane: %{filter: {swimlane_attribute, swimlane}}} ->
        [{attribute, value}, {swimlane_attribute, swimlane}]

      %{filter: {attribute, value}} ->
        [{attribute, value}]

      _not_a_section ->
        []
    end
  end

  @doc """
  ANDs scope filters (from `table_scope/3`) onto an `Ash.Query`.
  """
  @spec apply_scope(Ash.Query.t(), [{atom, term}]) :: Ash.Query.t()
  def apply_scope(query, scope) do
    Enum.reduce(scope, query, fn {attribute, value}, query ->
      Ash.Query.filter(query, ^ref(attribute) == ^value)
    end)
  end

  @doc """
  Loads a context's option list: the context resource's primary read with
  the surface's `actor:`/`tenant:`/`authorize?:` options, dependency-filtered
  through `depends_on_path` when the context depends on another, searched
  over the allowlisted `option_search` fields, sorted by `option_sort` and
  capped at `option_limit`.

  Pickerless contexts — and dependent contexts whose parent is unselected —
  load `{:ok, []}` without touching Ash.
  """
  @spec load_options(ResolvedView.t(), ResolvedView.context(), selected, String.t(), keyword) ::
          {:ok, [map]} | {:error, term}
  def load_options(view, context, selected, search \\ "", ash_opts) do
    cond do
      not context.picker ->
        {:ok, []}

      not is_nil(context.depends_on) and not Map.has_key?(selected, context.depends_on) ->
        {:ok, []}

      true ->
        query =
          context
          |> base_query(view, selected, ash_opts)
          |> apply_search(context.search_fields, search)
          |> Ash.Query.sort([{context.option_sort, :asc}])
          |> Ash.Query.limit(context.option_limit)

        case Ash.read(query) do
          {:ok, records} -> {:ok, Enum.map(records, &AshA2ui.Info.option_entry(&1, context))}
          {:error, error} -> {:error, error}
        end
    end
  end

  @doc """
  Fetches the record behind a selected context value — an **authorized**
  read through the context resource's primary read, dependency filter
  included: a value the actor cannot read, or one outside the selected
  parent's scope, is `:not_found`.
  """
  @spec fetch_selected(
          ResolvedView.t(),
          ResolvedView.context(),
          String.t(),
          selected,
          keyword,
          list
        ) :: {:ok, Ash.Resource.record()} | :not_found | {:error, term}
  def fetch_selected(view, context, value, selected, ash_opts, loads \\ []) do
    query =
      context
      |> base_query(view, selected, ash_opts)
      |> Ash.Query.filter(^ref(context.option_value) == ^value)
      |> Ash.Query.load(loads)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [record]} -> {:ok, record}
      {:ok, []} -> :not_found
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Applies a selection: validates `value` through `fetch_selected/6`, then
  cascades — every context depending on a changed context is cleared, its
  option list re-derived, and (with `auto_select_single`) re-selected when
  exactly one option remains.

  Returns `{:ok, change}` (see `t:change/0`), `:not_found`, or
  `{:error, error}`.
  """
  @spec select(ResolvedView.t(), ResolvedView.context(), String.t(), selected, keyword) ::
          {:ok, change} | :not_found | {:error, term}
  def select(view, context, value, selected, ash_opts) do
    case fetch_selected(view, context, value, selected, ash_opts) do
      {:ok, record} ->
        entry = AshA2ui.Info.option_entry(record, context)

        selected =
          Map.put(selected, context.name, %{value: entry["value"], label: entry["label"]})

        cascade(view, [context.name], selected, ash_opts)

      other ->
        other
    end
  end

  @doc """
  Clears a selection and cascades like `select/5` (dependents clear, their
  options re-derive to the unselected-parent state).
  """
  @spec clear(ResolvedView.t(), ResolvedView.context(), selected, keyword) ::
          {:ok, change} | {:error, term}
  def clear(view, context, selected, ash_opts) do
    cascade(view, [context.name], Map.delete(selected, context.name), ash_opts)
  end

  # Contexts may only depend on previously declared contexts (verified at
  # compile time), so a single pass in declaration order settles the
  # cascade: a context whose parent changed is cleared, its options
  # re-derived, and (auto_select_single) re-selected when exactly one option
  # remains — which marks it changed for *its* dependents in turn.
  defp cascade(view, initially_changed, selected, ash_opts) do
    acc = %{selected: selected, changed: initially_changed, options: %{}}

    view.context_order
    |> Enum.reduce_while({:ok, acc}, fn name, {:ok, acc} ->
      cascade_step(view, view.contexts[name], acc, ash_opts)
    end)
    |> case do
      {:ok, acc} -> {:ok, %{acc | changed: order_changed(view, acc.changed)}}
      error -> error
    end
  end

  defp cascade_step(view, context, acc, ash_opts) do
    if context.depends_on in acc.changed and context.name not in acc.changed do
      case cascade_child(view, context, acc, ash_opts) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:error, error} -> {:halt, {:error, error}}
      end
    else
      {:cont, {:ok, acc}}
    end
  end

  defp cascade_child(view, context, acc, ash_opts) do
    acc = %{acc | selected: Map.delete(acc.selected, context.name)}

    with {:ok, options} <- load_options(view, context, acc.selected, "", ash_opts) do
      selected =
        case {context.auto_select_single, options} do
          {true, [%{"value" => value, "label" => label}]} ->
            Map.put(acc.selected, context.name, %{value: value, label: label})

          _no_auto_select ->
            acc.selected
        end

      options_map =
        if context.picker, do: Map.put(acc.options, context.name, options), else: acc.options

      {:ok, %{selected: selected, changed: acc.changed ++ [context.name], options: options_map}}
    end
  end

  defp order_changed(view, changed) do
    Enum.filter(view.context_order, &(&1 in changed))
  end

  # --- query building -----------------------------------------------------------

  defp base_query(context, view, selected, ash_opts) do
    context.resource
    |> Ash.Query.for_read(
      ResourceInfo.primary_action!(context.resource, :read).name,
      %{},
      destination_opts(context.resource, ash_opts)
    )
    |> apply_dependency(view, context, selected)
  end

  defp apply_dependency(query, _view, %{depends_on: nil}, _selected), do: query

  defp apply_dependency(query, _view, context, selected) do
    case Map.get(selected, context.depends_on) do
      nil ->
        query

      %{value: value} ->
        {relationship_path, [terminal]} = Enum.split(context.depends_on_path, -1)

        cast =
          case cast_path_value(context.resource, relationship_path, terminal, value) do
            {:ok, cast} -> cast
            :error -> value
          end

        Ash.Query.filter(query, ^ref(relationship_path, terminal) == ^cast)
    end
  end

  defp cast_path_value(resource, relationship_path, terminal, value) do
    destination =
      Enum.reduce_while(relationship_path, resource, fn step, current ->
        case ResourceInfo.relationship(current, step) do
          %{destination: destination} -> {:cont, destination}
          nil -> {:halt, nil}
        end
      end)

    with true <- not is_nil(destination),
         %{type: type, constraints: constraints} <- ResourceInfo.attribute(destination, terminal),
         {:ok, cast} <- Ash.Type.cast_input(type, value, constraints) do
      {:ok, cast}
    else
      _missing_or_uncastable -> :error
    end
  end

  defp apply_search(query, _fields, ""), do: query
  defp apply_search(query, [], _search), do: query

  defp apply_search(query, fields, search) do
    ci_search = Ash.CiString.new(search)

    condition =
      fields
      |> Enum.map(&expr(contains(^ref(&1), ^ci_search)))
      |> Enum.reduce(&expr(^&2 or ^&1))

    Ash.Query.filter(query, ^condition)
  end

  defp cast_attribute(resource, attribute, value) do
    case ResourceInfo.attribute(resource, attribute) do
      %{type: type, constraints: constraints} ->
        case Ash.Type.cast_input(type, value, constraints) do
          {:ok, cast} -> {:ok, cast}
          _error -> :error
        end

      nil ->
        :error
    end
  end

  defp destination_opts(destination, ash_opts) do
    Keyword.put(
      ash_opts,
      :domain,
      ResourceInfo.domain(destination) || ash_opts[:domain]
    )
  end
end
