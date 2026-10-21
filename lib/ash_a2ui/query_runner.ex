defmodule AshA2ui.QueryRunner do
  @moduledoc """
  Validates client-supplied `"query"` action context against a view's
  `AshA2ui.Query` allowlist and executes the resulting Ash read.

  The allowlist principle: the client only ever *references* the named query
  declared in the DSL — every requested search/sort/filter/page value is
  validated against `search_fields` / `sortable` / `filters` /
  `max_page_size`, and anything not declared is rejected before Ash is
  called. No arbitrary client sort/filter parameters ever reach the data
  layer.

  ## The `/query` data-model state shape

  `run/3` returns (alongside the records) the map written to the reserved
  `/query` data-model path:

      %{
        "search" => "",
        "filters" => %{"status" => "", "category" => ""},   # every declared filter, "" = inactive
        "ranges" => %{"inserted_at" => %{"from" => "", "to" => ""}},
                                                            # only when the query declares range_filters
        "preset" => "pending",                              # only when the query declares presets
        "sort" => %{"field" => "name", "dir" => "asc"},     # or nil when unsorted
        "page" => 1,
        "pageSize" => 25,
        "totalCount" => 42,                                 # or nil when the data layer can't count
        "hasMore" => true
      }

  ## Range filters

  When the query declares `range_filters`, the client may bound those fields
  via `"ranges"`: `%{"<field>" => %{"from" => _, "to" => _}}` — inclusive
  bounds cast to the attribute's type, `""` = unbounded. Datetime-typed
  fields also accept plain date strings (the native date input format),
  expanding to the day's start (from) / end (to) in UTC.

  ## Search fields

  `search_fields` entries are string attributes (`:subject`) or relationship
  paths to one (`[:author, :email]`); each produces a case-insensitive
  contains condition (path entries reference the terminal attribute through
  the relationship path), OR'd together.

  ## Presets

  When the query declares `preset` entities, the client may select one **by
  name** via the `"preset"` key of the query state — the predicates
  themselves live server-side only. A `filter`-based preset ANDs its
  conditions onto the base query (`nil` = `is_nil`, list = membership,
  otherwise equality); a `read_action`-based preset reads through that
  action instead of the table's `read_action`. A missing `"preset"` key (and
  `""`) falls back to the query's `default_preset` (or no preset when none
  is declared); unknown names are rejected.

  ## Calendar windows

  On a `display :calendar` table the state also carries `"window"` (see
  `AshA2ui.Calendar`): the read is narrowed to the visible window (or the
  picked day), and the context may move the window (`"anchor"`,
  `"windowDelta"`) or pick a day (`"date"`). Either change resets the page
  to 1. Without a declared or requested sort, a calendar reads in
  `date_field` order.

  ## Pagination mechanism

  Plain `Ash.Query.limit/2` + `Ash.Query.offset/2` with `limit = page_size + 1`
  — the extra row only signals `hasMore` and is dropped from the results. This
  works on any data layer without requiring the read action to enable Ash
  pagination. `totalCount` is computed with `Ash.count/2` on the filtered
  (unpaginated) query and degrades to `nil` on data layers without count
  support. The resource's primary key is appended as a sort tiebreaker so
  pages are stable under equal sort values.
  """

  import Ash.Expr

  require Ash.Query

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView

  @typedoc """
  Validated query parameters, safe to execute. Each `ranges` entry is a
  fully-cast, allowlisted range filter: `from`/`to` are the cast bound
  values (`nil` = unbounded), `from_raw`/`to_raw` the client strings echoed
  back into the `/query` state.
  """
  @type params :: %{
          search: String.t(),
          filters: [{atom, term}],
          ranges: [%{field: atom, from: term, to: term, from_raw: String.t(), to_raw: String.t()}],
          preset: atom | nil,
          sort: {atom, :asc | :desc} | nil,
          page: pos_integer,
          page_size: pos_integer,
          window: AshA2ui.Calendar.window() | nil
        }

  @doc """
  Parses and validates a `"query"` action context map against the view's
  query allowlist.

  The context shape (all keys optional):

      %{
        "query" => %{"search" => _, "filters" => _, "sort" => _, "page" => _, "pageSize" => _},
        "page" => 1,        # literal page override (used by the Apply button to reset to page 1)
        "pageDelta" => 1    # relative page change (used by the prev/next buttons)
      }

  Returns `{:ok, params}` or `{:error, reason_text}` — non-allowlisted sort
  fields, filters, or search on a query without `search_fields` are rejected,
  never passed through. Page is clamped to >= 1 and page size to
  `1..max_page_size`. Unknown keys inside `"query"` (such as the echoed
  `totalCount`/`hasMore`) are ignored.
  """
  @spec parse(ResolvedView.t(), map) :: {:ok, params} | {:error, String.t()}
  def parse(%{query: nil}, _context) do
    {:error, "No query is configured for this surface."}
  end

  def parse(view, context) when is_map(context) do
    query = view.query

    with {:ok, state} <- query_state(context),
         {:ok, search} <- parse_search(query, state),
         {:ok, filters} <- parse_filters(view.resource, query, state),
         {:ok, ranges} <- parse_ranges(view.resource, query, state),
         {:ok, preset} <- parse_preset(query, state),
         {:ok, sort} <- parse_sort(query, state),
         {:ok, page} <- parse_page(state, context),
         {:ok, page_size} <- parse_page_size(query, state),
         {:ok, window, moved?} <- parse_window(view, state, context, preset) do
      {:ok,
       %{
         search: search,
         filters: filters,
         ranges: ranges,
         preset: preset,
         sort: sort,
         page: window_page(page, moved?, context),
         page_size: page_size,
         window: window
       }}
    end
  end

  # Only calendar tables have a window (see AshA2ui.Calendar). A preset
  # with a calendar_anchor moves the window when the request switches to it.
  defp parse_window(view, state, context, preset) do
    case Map.get(view, :calendar) do
      nil ->
        {:ok, nil, false}

      config ->
        AshA2ui.Calendar.parse_window(config, state, context, preset_entity(view.query, preset))
    end
  end

  defp preset_entity(_query, nil), do: nil
  defp preset_entity(query, name), do: Enum.find(query.presets, &(&1.name == name))

  # Moving the window or picking a day starts over at page 1, unless the
  # context names a page itself.
  defp window_page(_page, true, context) when not is_map_key(context, "page"), do: 1
  defp window_page(page, _moved?, _context), do: page

  @doc """
  The validated params equivalent to an empty client context: no search, no
  filters, the declared default preset, the declared default sort, page 1 at
  the declared page size. Used for initial surface loads and refreshes
  without client query state.
  """
  @spec default_params(AshA2ui.Query.t() | ResolvedView.table() | ResolvedView.t()) :: params
  def default_params(%AshA2ui.Query{} = query) do
    %{
      search: "",
      filters: [],
      ranges: [],
      preset: query.default_preset,
      sort: nil,
      page: 1,
      page_size: query.page_size,
      window: nil
    }
  end

  # A table (or view) scope: a calendar table's defaults hold today's window
  # (or the default preset's calendar_anchor day).
  def default_params(%{query: query} = table) do
    window =
      case Map.get(table, :calendar) do
        nil ->
          nil

        config ->
          AshA2ui.Calendar.default_window(
            config,
            nil,
            preset_entity(query, query.default_preset)
          )
      end

    %{default_params(query) | window: window}
  end

  @doc """
  Builds the frozen `/query` data-model state map (see the moduledoc) for
  `params` with the given `total_count` (integer or `nil`) and `has_more`.
  """
  @spec state(AshA2ui.Query.t(), params, non_neg_integer | nil, boolean) :: map
  def state(query, params, total_count, has_more) do
    effective_sort = effective_sort(query, params)

    %{
      "search" => params.search,
      "filters" => filters_state(query, params.filters),
      "sort" => sort_state(effective_sort),
      "page" => params.page,
      "pageSize" => params.page_size,
      "totalCount" => total_count,
      "hasMore" => has_more
    }
    |> put_preset_state(query, params)
    |> put_ranges_state(query, params)
    |> put_window_state(params)
  end

  # The "window" key only exists on calendar tables (marks are filled in by
  # run/4, which read them).
  defp put_window_state(state, %{window: %{} = window}),
    do: Map.put(state, "window", AshA2ui.Calendar.state(window, []))

  defp put_window_state(state, _params), do: state

  # The "ranges" key only exists on queries that declare range_filters — the
  # state shape of range-less queries is unchanged. Every declared range is
  # present ({"from" => "", "to" => ""} = inactive) so client bindings under
  # /query/ranges/<field>/from|to are stable.
  defp put_ranges_state(state, %{range_filters: []}, _params), do: state

  defp put_ranges_state(state, query, params) do
    active = Map.new(params.ranges, &{&1.field, &1})

    ranges =
      Map.new(query.range_filters, fn field ->
        case Map.get(active, field) do
          nil -> {to_string(field), %{"from" => "", "to" => ""}}
          range -> {to_string(field), %{"from" => range.from_raw, "to" => range.to_raw}}
        end
      end)

    Map.put(state, "ranges", ranges)
  end

  # The "preset" key only exists on queries that declare presets — the state
  # shape of preset-less queries is unchanged.
  defp put_preset_state(state, %{presets: []}, _params), do: state

  defp put_preset_state(state, _query, params) do
    Map.put(state, "preset", to_string(params.preset || ""))
  end

  @doc """
  Executes the validated `params` through the view's read action and returns
  `{:ok, records, query_state}` — `query_state` being the frozen `/query`
  data-model shape (see the moduledoc) — or `{:error, error}` when the read
  fails.

  `ash_opts` are the usual `:domain` / `:actor` / `:tenant` / `:authorize?`
  read options.

  `scope` (from `AshA2ui.ContextRunner.table_scope/3`) is a list of
  `{attribute, value}` context filters ANDed onto the read *before*
  search/filters/pagination — total counts and `hasMore` respect it.

  The first argument is anything carrying the queried-read shape —
  `AshA2ui.ResolvedView.t/0` itself, or one resolved table of a
  multi-table view (`AshA2ui.ResolvedView.table/0`).
  """
  @spec run(ResolvedView.t() | ResolvedView.table(), params, keyword, [{atom, term}]) ::
          {:ok, [Ash.Resource.record()], map} | {:error, term}
  def run(view, params, ash_opts, scope \\ []) do
    query = view.query
    calendar = Map.get(view, :calendar)
    params = with_window(params, view)
    effective_sort = read_sort(effective_sort(query, params), calendar)

    filtered =
      view
      |> preset_read(params, ash_opts)
      |> AshA2ui.ContextRunner.apply_scope(scope)
      |> apply_filters(params.filters)
      |> apply_ranges(params.ranges)
      |> apply_search(query, params.search)

    windowed = apply_window(filtered, calendar, params)

    paged =
      windowed
      |> Ash.Query.sort(effective_sort ++ tiebreaker(view.resource, effective_sort))
      |> Ash.Query.load(view.loads)
      |> Ash.Query.limit(params.page_size + 1)
      |> Ash.Query.offset((params.page - 1) * params.page_size)

    with {:ok, rows} <- Ash.read(paged),
         has_more = length(rows) > params.page_size,
         records = Enum.take(rows, params.page_size),
         {:ok, marks} <- window_marks(filtered, calendar, params, records, has_more) do
      state =
        query
        |> state(params, total_count(windowed), has_more)
        |> put_marks(marks)

      {:ok, records, state}
    end
  end

  # A calendar table always reads a window: params built without one (by a
  # caller holding only the query) get today's.
  defp with_window(params, view) do
    case {Map.get(view, :calendar), Map.get(params, :window)} do
      {nil, _window} ->
        Map.put(params, :window, nil)

      {config, nil} ->
        preset = preset_entity(view.query, params.preset)
        Map.put(params, :window, AshA2ui.Calendar.default_window(config, nil, preset))

      {_config, _window} ->
        params
    end
  end

  # Without a declared or requested sort a calendar reads in date order.
  defp read_sort([], %{date_field: date_field}), do: [{date_field, :asc}]
  defp read_sort(sort, _calendar), do: sort

  defp apply_window(query, nil, _params), do: query

  defp apply_window(query, calendar, params),
    do: AshA2ui.Calendar.filter(query, calendar, AshA2ui.Calendar.read_range(params.window))

  # When the page holds the whole window (no picked day, first page, no
  # further page) the marks come from its rows; otherwise from one more read
  # of the window's dates through the same filters.
  defp window_marks(_filtered, nil, _params, _records, _has_more), do: {:ok, nil}

  defp window_marks(
         _filtered,
         calendar,
         %{window: %{selected: nil}, page: 1} = params,
         records,
         false
       ),
       do: {:ok, AshA2ui.Calendar.marks(calendar, records, params.window)}

  defp window_marks(filtered, calendar, params, _records, _has_more),
    do: AshA2ui.Calendar.read_marks(filtered, calendar, params.window)

  defp put_marks(state, nil), do: state
  defp put_marks(state, marks), do: put_in(state, ["window", "marks"], marks)

  @doc """
  The read a table performs under the active preset of `params`, before
  scope, search, filters, sort and pagination: the preset's `read_action`
  (or the table's declared or primary read), as the actor in `ash_opts`,
  with a `filter` preset's conditions ANDed on. `params` may be `nil` (a
  table without a query), which reads through the table's read action.

  `run/4` builds on it, and so does the authorized re-read of a bulk
  selection (`AshA2ui.Bulk.read_selected/5`), so a selection is re-read
  through the same action and preset predicate as the page it came from.
  """
  @spec preset_read(ResolvedView.t() | ResolvedView.table(), params | nil, keyword) ::
          Ash.Query.t()
  def preset_read(view, params, ash_opts) do
    preset = active_preset(view.query, params)

    # A related table reads a resource that may live in another domain.
    ash_opts =
      Keyword.put(ash_opts, :domain, ResourceInfo.domain(view.resource) || ash_opts[:domain])

    view.resource
    |> Ash.Query.for_read(read_action(view, preset), %{}, ash_opts)
    |> apply_preset(preset)
  end

  defp active_preset(%{presets: presets}, %{preset: name}) when not is_nil(name),
    do: Enum.find(presets, &(&1.name == name))

  defp active_preset(_query, _params), do: nil

  # --- context parsing --------------------------------------------------------

  defp query_state(context) do
    case Map.get(context, "query", %{}) do
      state when is_map(state) -> {:ok, state}
      _other -> {:error, ~s(Malformed query action: "query" must be a map.)}
    end
  end

  defp parse_search(query, state) do
    case Map.get(state, "search") do
      empty when empty in [nil, ""] ->
        {:ok, ""}

      search when is_binary(search) ->
        if query.search_fields == [] do
          {:error, "Search is not enabled for this query: it declares no search_fields."}
        else
          {:ok, search}
        end

      _other ->
        {:error, ~s(Malformed query action: "search" must be a string.)}
    end
  end

  defp parse_filters(resource, query, state) do
    case Map.get(state, "filters", %{}) do
      filters when is_map(filters) ->
        collect_filters(resource, query, filters)

      _other ->
        {:error, ~s(Malformed query action: "filters" must be a map.)}
    end
  end

  defp collect_filters(resource, query, filters) do
    filters
    |> Enum.reject(fn {_key, value} -> inactive_filter_value?(value) end)
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case parse_filter(resource, query, key, value) do
        {:ok, filter} -> {:cont, {:ok, [filter | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, collected} -> {:ok, Enum.reverse(collected)}
      error -> error
    end
  end

  # A ChoicePicker's "All" option binds "" — and under multipleSelection the
  # bound value is a *list* that may contain only empty strings (e.g. [""]).
  # All of these mean "no filter"; letting [""] through would strip the empty
  # entries during casting and produce `field in []`, matching nothing.
  defp inactive_filter_value?(value) when is_list(value),
    do: Enum.all?(value, &inactive_filter_value?/1)

  defp inactive_filter_value?(value), do: value in [nil, ""]

  defp parse_filter(resource, query, key, value) do
    case allowlisted(query.filters, key) do
      nil ->
        {:error,
         "Filter #{inspect(key)} is not allowlisted: it is not declared in the query's filters."}

      field ->
        case cast_filter_value(resource, field, value) do
          {:ok, cast} -> {:ok, {field, cast}}
          :error -> {:error, "Filter #{inspect(key)} value #{inspect(value)} is invalid."}
        end
    end
  end

  # Range filters arrive as %{"<field>" => %{"from" => _, "to" => _}} under
  # the state's "ranges" key. Every referenced field must be allowlisted in
  # the query's range_filters; every non-empty bound must cast to the
  # attribute's type. A range with both bounds empty is inactive.
  defp parse_ranges(resource, query, state) do
    case Map.get(state, "ranges", %{}) do
      ranges when is_map(ranges) ->
        reduce_ranges(resource, query, ranges)

      _other ->
        {:error, ~s(Malformed query action: "ranges" must be a map.)}
    end
  end

  defp reduce_ranges(resource, query, ranges) do
    ranges
    |> Enum.reduce_while({:ok, []}, fn {key, bounds}, {:ok, acc} ->
      case parse_range(resource, query, key, bounds) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, range} -> {:cont, {:ok, [range | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, collected} -> {:ok, Enum.reverse(collected)}
      error -> error
    end
  end

  defp parse_range(resource, query, key, bounds) do
    field = allowlisted(query.range_filters, key)

    cond do
      is_nil(field) ->
        {:error,
         "Range filter #{inspect(key)} is not allowlisted: it is not declared in the " <>
           "query's range_filters."}

      not is_map(bounds) ->
        {:error, ~s(Malformed query action: range "#{key}" must be a {"from", "to"} map.)}

      true ->
        cast_range(resource, field, key, bounds)
    end
  end

  defp cast_range(resource, field, key, bounds) do
    from_raw = range_bound_string(Map.get(bounds, "from"))
    to_raw = range_bound_string(Map.get(bounds, "to"))

    with {:ok, from} <- cast_range_bound(resource, field, from_raw, :from),
         {:ok, to} <- cast_range_bound(resource, field, to_raw, :to) do
      if is_nil(from) and is_nil(to) do
        {:ok, nil}
      else
        {:ok, %{field: field, from: from, to: to, from_raw: from_raw, to_raw: to_raw}}
      end
    else
      :error -> {:error, "Range filter #{inspect(key)} value is invalid."}
    end
  end

  defp range_bound_string(value) when is_binary(value), do: value
  defp range_bound_string(_nil_or_other), do: ""

  # An empty bound is unbounded. A plain date string ("2026-05-07", the
  # native date input format) on a datetime-typed field expands to the day's
  # start (from) or end (to) in UTC — checked first, because Ash's datetime
  # casts would silently read it as midnight and make a same-day from/to
  # range empty. Everything else casts to the attribute's type.
  defp cast_range_bound(_resource, _field, "", _side), do: {:ok, nil}

  defp cast_range_bound(resource, field, value, side) do
    %{type: type, constraints: constraints} = ResourceInfo.attribute(resource, field)

    case date_expanded_bound(type, value, side) do
      {:ok, cast} ->
        {:ok, cast}

      :not_a_date_bound ->
        with {:ok, cast} <- Ash.Type.cast_input(type, value, constraints),
             {:ok, cast} <- Ash.Type.apply_constraints(type, cast, constraints) do
          {:ok, cast}
        else
          _error -> :error
        end
    end
  end

  @datetime_types [Ash.Type.UtcDatetime, Ash.Type.UtcDatetimeUsec, Ash.Type.DateTime]

  defp date_expanded_bound(type, value, side) do
    with true <- Ash.Type.get_type(type) in @datetime_types,
         {:ok, date} <- Date.from_iso8601(value) do
      time = if side == :from, do: ~T[00:00:00], else: ~T[23:59:59.999999]
      {:ok, DateTime.new!(date, time, "Etc/UTC")}
    else
      _not_a_date -> :not_a_date_bound
    end
  end

  # A missing preset key (or the ChoicePicker's "" placeholder) falls back
  # to the declared default; names are string-compared against the declared
  # presets — never creating atoms from client input.
  #
  # The preset picker is semantically single-select, but the client binds
  # ChoicePicker values as string lists — a picked preset arrives as
  # ["name"] and the "All" placeholder as [""] or [] — so one-element lists
  # are unwrapped before matching (mirrors form-value unwrapping in
  # ActionHandler).
  defp parse_preset(query, state) do
    case Map.get(state, "preset") |> unwrap_preset() do
      empty when empty in [nil, ""] ->
        {:ok, query.default_preset}

      name when is_binary(name) ->
        case Enum.find(query.presets, &(to_string(&1.name) == name)) do
          nil ->
            {:error,
             "Preset #{inspect(name)} is not allowlisted: it is not declared in the query's " <>
               "presets."}

          preset ->
            {:ok, preset.name}
        end

      _other ->
        {:error, ~s(Malformed query action: "preset" must be a string.)}
    end
  end

  defp unwrap_preset([value]), do: value
  defp unwrap_preset([]), do: nil
  defp unwrap_preset(value), do: value

  # ChoicePickers may bind a single string or a string list (multipleSelection);
  # accept both. Every value must cast to the attribute's type + constraints.
  defp cast_filter_value(resource, field, values) when is_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case cast_filter_value(resource, field, value) do
        {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, [single]} -> {:ok, single}
      {:ok, cast} -> {:ok, Enum.reverse(cast)}
      :error -> :error
    end
  end

  # Filters may target attributes or (expression-backed, verified at compile
  # time) public calculations; both carry a type + constraints to cast with.
  defp cast_filter_value(resource, field, value) do
    %{type: type, constraints: constraints} =
      ResourceInfo.attribute(resource, field) || ResourceInfo.calculation(resource, field)

    with {:ok, cast} <- Ash.Type.cast_input(type, value, constraints),
         {:ok, cast} <- Ash.Type.apply_constraints(type, cast, constraints) do
      {:ok, cast}
    else
      _error -> :error
    end
  end

  defp parse_sort(query, state) do
    case Map.get(state, "sort") do
      nil ->
        {:ok, nil}

      %{"field" => field} = sort when is_binary(field) ->
        dir = Map.get(sort, "dir", "asc")

        cond do
          is_nil(allowlisted(query.sortable, field)) ->
            {:error,
             "Sort field #{inspect(field)} is not allowlisted: it is not declared in the " <>
               "query's sortable fields."}

          dir not in ["asc", "desc"] ->
            {:error, "Sort direction #{inspect(dir)} is invalid: use \"asc\" or \"desc\"."}

          true ->
            {:ok, {allowlisted(query.sortable, field), String.to_existing_atom(dir)}}
        end

      _other ->
        {:error, ~s(Malformed query action: "sort" must be a {"field", "dir"} map or null.)}
    end
  end

  # Precedence: a literal "page" in the context wins (the Apply button resets
  # to page 1), then "pageDelta" relative to the state's page (prev/next
  # buttons), then the state's page itself. Always clamped to >= 1.
  defp parse_page(state, context) do
    with {:ok, current} <- integer_or_default(Map.get(state, "page"), 1, "page"),
         {:ok, override} <- integer_or_default(Map.get(context, "page"), nil, "page"),
         {:ok, delta} <- integer_or_default(Map.get(context, "pageDelta"), 0, "pageDelta") do
      {:ok, max(override || current + delta, 1)}
    end
  end

  defp parse_page_size(query, state) do
    case integer_or_default(Map.get(state, "pageSize"), query.page_size, "pageSize") do
      {:ok, size} -> {:ok, size |> min(query.max_page_size) |> max(1)}
      error -> error
    end
  end

  defp integer_or_default(nil, default, _key), do: {:ok, default}
  defp integer_or_default(value, _default, _key) when is_integer(value), do: {:ok, value}

  defp integer_or_default(_value, _default, key),
    do: {:error, "Malformed query action: #{inspect(key)} must be an integer."}

  # String-compares client input against the declared atom allowlist — never
  # creating atoms from client input.
  defp allowlisted(allowlist, key) do
    Enum.find(allowlist, &(to_string(&1) == key))
  end

  # --- query building ---------------------------------------------------------

  # A filter-based preset ANDs its declared conditions onto the base query
  # (nil = is_nil, list = membership, otherwise equality); a read_action
  # preset already switched the read (see read_action/2).
  defp apply_preset(query, %{filter: conditions}) when is_list(conditions) do
    Enum.reduce(conditions, query, fn
      {field, nil}, query ->
        Ash.Query.filter(query, is_nil(^ref(field)))

      {field, values}, query when is_list(values) ->
        Ash.Query.filter(query, ^ref(field) in ^values)

      {field, value}, query ->
        Ash.Query.filter(query, ^ref(field) == ^value)
    end)
  end

  defp apply_preset(query, _no_filter_preset), do: query

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {field, values}, query when is_list(values) ->
        Ash.Query.filter(query, ^ref(field) in ^values)

      {field, value}, query ->
        Ash.Query.filter(query, ^ref(field) == ^value)
    end)
  end

  defp apply_ranges(query, ranges) do
    Enum.reduce(ranges, query, fn range, query ->
      query
      |> apply_range_bound(range.field, :>=, range.from)
      |> apply_range_bound(range.field, :<=, range.to)
    end)
  end

  defp apply_range_bound(query, _field, _op, nil), do: query

  defp apply_range_bound(query, field, :>=, value),
    do: Ash.Query.filter(query, ^ref(field) >= ^value)

  defp apply_range_bound(query, field, :<=, value),
    do: Ash.Query.filter(query, ^ref(field) <= ^value)

  defp apply_search(query, _ui_query, ""), do: query

  defp apply_search(query, ui_query, search) do
    ci_search = Ash.CiString.new(search)

    condition =
      ui_query.search_fields
      |> Enum.map(&search_condition(&1, ci_search))
      |> Enum.reduce(&expr(^&2 or ^&1))

    Ash.Query.filter(query, ^condition)
  end

  # A plain attribute matches directly; a relationship path references the
  # terminal attribute through the path (Ash data layers apply exists
  # semantics to to-many paths in filters).
  defp search_condition(field, ci_search) when is_atom(field) do
    expr(contains(^ref(field), ^ci_search))
  end

  defp search_condition(path, ci_search) when is_list(path) do
    {relationship_path, [attribute]} = Enum.split(path, -1)
    expr(contains(^ref(relationship_path, attribute), ^ci_search))
  end

  defp effective_sort(query, params) do
    case params.sort do
      nil -> query.default_sort
      sort -> [sort]
    end
  end

  defp tiebreaker(resource, effective_sort) do
    sorted_fields = Enum.map(effective_sort, &elem(&1, 0))

    resource
    |> ResourceInfo.primary_key()
    |> Enum.reject(&(&1 in sorted_fields))
    |> Enum.map(&{&1, :asc})
  end

  defp total_count(filtered_query) do
    case Ash.count(filtered_query) do
      {:ok, count} -> count
      {:error, _error} -> nil
    end
  end

  # A read_action-based preset reads through its dedicated action; otherwise
  # the table's declared (or primary) read applies.
  defp read_action(_view, %{read_action: action}) when not is_nil(action), do: action

  defp read_action(view, _preset),
    do: view.read_action || ResourceInfo.primary_action!(view.resource, :read).name

  # --- /query state -----------------------------------------------------------

  # Every declared filter is present ("" = inactive) so client bindings under
  # /query/filters/<name> are stable.
  defp filters_state(query, active_filters) do
    active = Map.new(active_filters)

    Map.new(query.filters, fn field ->
      {to_string(field), stringify(Map.get(active, field, ""))}
    end)
  end

  defp sort_state([]), do: nil

  defp sort_state([{field, dir} | _rest]),
    do: %{"field" => to_string(field), "dir" => to_string(dir)}

  defp stringify(values) when is_list(values), do: Enum.map(values, &stringify/1)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
