defmodule AshA2ui.Info do
  @moduledoc """
  Introspection for the `AshA2ui` extension, plus the public payload-building
  API.

  FROZEN CONTRACT — the signatures of `build_surface/2`, `build_data_model/2`,
  `resource!/1`, `components/1` and `fields/1` are the interface every parallel
  track codes against; do not change outside an integration commit.
  """

  use Spark.InfoGenerator, extension: AshA2ui, sections: [:a2ui]

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.ResolvedView
  alias Spark.Dsl.Extension

  @doc """
  The `component` entities declared in the `a2ui` section.
  """
  @spec components(module | Spark.Dsl.t()) :: [AshA2ui.Component.t()]
  def components(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end

  @doc """
  The `field` entities declared in the `a2ui` section.
  """
  @spec fields(module | Spark.Dsl.t()) :: [AshA2ui.Field.t()]
  def fields(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Field))
  end

  @doc """
  The `context` entities declared in the `a2ui` section.
  """
  @spec contexts(module | Spark.Dsl.t()) :: [AshA2ui.Context.t()]
  def contexts(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Context))
  end

  @doc """
  The `query` entities declared in the `a2ui` section.
  """
  @spec queries(module | Spark.Dsl.t()) :: [AshA2ui.Query.t()]
  def queries(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Query))
  end

  @doc """
  The `action` entities (per-action refresh metadata) declared in the `a2ui`
  section.
  """
  @spec action_settings(module | Spark.Dsl.t()) :: [AshA2ui.Action.t()]
  def action_settings(resource_or_ui_module) do
    resource_or_ui_module
    |> Extension.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Action))
  end

  @doc """
  Resolves the Ash resource behind `resource_or_ui_module`: the module's
  `for_resource` option if set (standalone UI modules), otherwise the module
  itself (which must be an `Ash.Resource`).
  """
  @spec resource!(module | Spark.Dsl.t()) :: module
  def resource!(resource_or_ui_module) do
    case a2ui_for_resource(resource_or_ui_module) do
      {:ok, resource} ->
        resource

      :error ->
        if ResourceInfo.resource?(resource_or_ui_module) do
          resource_or_ui_module
        else
          raise ArgumentError,
                "#{inspect(resource_or_ui_module)} is not an Ash resource and has no " <>
                  "`for_resource` configured in its `a2ui` section"
        end
    end
  end

  @doc """
  Builds the ordered A2UI server->client message list for the surface, in
  the protocol version the surface declares (`spec_version`, default
  `"0.9.1"`): the v0.9.1 `createSurface` -> `updateComponents` ->
  `updateDataModel` triple, or v1.0's single inline `createSurface` message
  (components + data model in one payload — see `AshA2ui.Encoder.V1_0`).

  ## Options

    * `:actor` — the actor used to load records.
    * `:tenant` — the tenant used to load records.
    * `:authorize?` — whether to authorize the read. Defaults to `true`.
    * `:domain` — the Ash domain used for the read. Defaults to the
      resource's configured domain.
    * `:query_state` — a client `/query` state map to run the read with
      (validated against the query allowlist; invalid or missing state falls
      back to the query's declared defaults). Lets refreshes preserve the
      user's current search/filters/sort/page instead of resetting them.
    * `:context_state` — a client `/context` state map to load under
      (sanitized like any client input — see
      `AshA2ui.ContextRunner.selected/2`). Lets refreshes preserve the
      user's current context selections: dependent option lists stay
      filtered, `/detail/<context>` records re-fetch, and scoped tables
      keep their context filters (tables with an unmet `require_context`
      load no records).
    * `:surface_properties` — v1.0 surfaces only: an optional map for the
      `createSurface` payload's `surfaceProperties` (e.g.
      `%{"agentDisplayName" => "Support Agent"}`). Ignored on v0.9.1
      surfaces (the v0.9 `theme` block was never emitted).
    * `:link_buttons` — basic catalog only: `true` renders each to-one
      reference link (`link :relationship` / `link {surface, id_path}`)
      as a borderless `Button` dispatching the `"open_surface"` action
      (see the Relationships topic). Defaults to `false` (plain value
      Text): pass it only from a transport that navigates on an accepted
      `"open_surface"`. `AshA2ui.LiveRenderer` sets it when it has an
      `:open_surface` callback or an `:open_surface_url` template.
      Admin-catalog link columns and FieldDisplays render their links
      regardless; only its basic-component fallbacks follow this option.
  """
  @spec build_surface(module | Spark.Dsl.t(), keyword) :: [map]
  def build_surface(resource_or_ui_module, opts \\ []) do
    resolved_view =
      resource_or_ui_module
      |> ResolvedView.resolve(opts)
      |> AshA2ui.Sections.expand!(opts)

    {records, opts} = load_and_put_state!(resolved_view, opts)

    encoder(resolved_view).encode_surface(resolved_view, records, opts)
  end

  @doc """
  Builds a data-only refresh: the `updateDataModel` message for the surface
  (in the surface's declared protocol version), used for PubSub-driven live
  refreshes.

  Takes the same options as `build_surface/2`.
  """
  @spec build_data_model(module | Spark.Dsl.t(), keyword) :: map
  def build_data_model(resource_or_ui_module, opts \\ []) do
    resolved_view =
      resource_or_ui_module
      |> ResolvedView.resolve(opts)
      |> AshA2ui.Sections.expand!(opts)

    {records, opts} = load_and_put_state!(resolved_view, opts)

    encoder(resolved_view).encode_data_model(resolved_view, records, opts)
  end

  @doc """
  Validates externally carried context selections — `%{"<context>" =>
  "<record id>"}`, e.g. from a deep link's `?ctx[person]=<id>` — into the
  `/context` state map `build_surface/2`/`build_data_model/2` take as
  `:context_state`.

  Every id goes through the same **authorized** read (dependency filter
  included) and cascade as a client `"context_select"`, in declaration
  order, with the `opts`' `:actor`/`:tenant`/`:authorize?`/`:domain`.
  Unknown context names and ids the actor cannot read (or that fall outside
  the selected parent's scope) are dropped; labels are derived from the
  records. Surfaces without contexts return `%{}`.
  """
  @spec context_state_for(module | Spark.Dsl.t(), %{String.t() => String.t()}, keyword) ::
          %{String.t() => map}
  def context_state_for(resource_or_ui_module, ids, opts \\ []) do
    view =
      ResolvedView.resolve(
        resource_or_ui_module,
        Keyword.take(opts, [:actor, :tenant, :domain, :authorize?])
      )

    if view.contexts == %{} do
      %{}
    else
      ash_opts = read_opts(view, opts)

      selected =
        Enum.reduce(view.context_order, %{}, fn name, selected ->
          select_carried(view, name, Map.get(ids, to_string(name)), selected, ash_opts)
        end)

      AshA2ui.ContextRunner.state(view, selected)
    end
  end

  defp select_carried(_view, _name, value, selected, _ash_opts)
       when not is_binary(value) or value == "",
       do: selected

  defp select_carried(view, name, value, selected, ash_opts) do
    case AshA2ui.ContextRunner.select(view, view.contexts[name], value, selected, ash_opts) do
      {:ok, change} -> change.selected
      _not_found_or_error -> selected
    end
  end

  @doc """
  The versioned encoder module for a resolved view: `AshA2ui.Encoder.V0_9_1`
  or `AshA2ui.Encoder.V1_0`, per the surface's `spec_version`.
  """
  @spec encoder(ResolvedView.t()) :: module
  def encoder(%ResolvedView{spec_version: :v1_0}), do: AshA2ui.Encoder.V1_0
  def encoder(%ResolvedView{}), do: AshA2ui.Encoder.V0_9_1

  # The shared loading pipeline: sanitize the carried /context state, load
  # records under its scope, load option lists (contexts included), fetch
  # the selected contexts' /detail records, and hand the encoder the
  # resolved context/detail values.
  defp load_and_put_state!(resolved_view, opts) do
    selected = AshA2ui.ContextRunner.selected(resolved_view, opts[:context_state])
    {records, opts} = load_records!(resolved_view, selected, opts)

    opts =
      opts
      |> Keyword.put(:options, load_options!(resolved_view, selected, opts))
      |> put_context_values(resolved_view, selected)

    {records, opts}
  end

  defp put_context_values(opts, %{contexts: contexts}, _selected) when contexts == %{}, do: opts

  defp put_context_values(opts, resolved_view, selected) do
    opts
    |> Keyword.put(:context_values, AshA2ui.ContextRunner.state(resolved_view, selected))
    |> Keyword.put(:detail_values, load_details!(resolved_view, selected, opts))
  end

  # Loads the surface's records through normal `Ash.read`s (policies apply).
  # Surfaces without a table component render no records; single-table
  # surfaces load a plain record list; multi-table surfaces load one list
  # per table (`%{table_name => [record]}`). Tables with a `query` read
  # through `AshA2ui.QueryRunner` — with the caller-carried `:query_state`
  # when given (validated like any client input, falling back to the
  # declared defaults; on multi-table surfaces an object keyed by table
  # component name), otherwise with the query's declared defaults (default
  # sort, page 1) — and the resulting `/query` state (per table on
  # multi-table surfaces) is handed to the encoder via the `:query_state`
  # option.
  defp load_records!(resolved_view, selected, opts) do
    cond do
      ResolvedView.multi_table?(resolved_view) ->
        loaded =
          Enum.map(
            resolved_view.tables,
            &{&1.name, load_table!(resolved_view, &1, selected, opts)}
          )

        records = Map.new(loaded, fn {name, {records, _state}} -> {name, records} end)

        states =
          for {name, {_records, state}} <- loaded, not is_nil(state), into: %{}, do: {name, state}

        {records, (states != %{} && Keyword.put(opts, :query_state, states)) || opts}

      resolved_view.tables == [] ->
        {[], opts}

      true ->
        [single] = resolved_view.tables
        {records, query_state} = load_table!(resolved_view, single, selected, opts)
        {records, (query_state && Keyword.put(opts, :query_state, query_state)) || opts}
    end
  end

  defp load_table!(resolved_view, table, selected, opts) do
    if is_nil(table.read_action) do
      raise ArgumentError,
            "cannot load records for #{inspect(resolved_view.resource)}: the resource has " <>
              "no read action (declare one, or set `read_action` on the table component)"
    end

    case AshA2ui.ContextRunner.table_scope(resolved_view, table, selected) do
      :require_unmet ->
        state =
          table.query &&
            AshA2ui.QueryRunner.state(
              table.query,
              query_params(resolved_view, table, opts),
              0,
              false
            )

        {[], state}

      {:ok, scope} ->
        load_scoped_table!(resolved_view, table, scope, opts)
    end
  end

  defp load_scoped_table!(resolved_view, table, scope, opts) do
    if table.query do
      params = query_params(resolved_view, table, opts)

      case AshA2ui.QueryRunner.run(table, params, read_opts(resolved_view, opts), scope) do
        {:ok, records, query_state} -> {records, query_state}
        {:error, error} -> raise Ash.Error.to_error_class(error)
      end
    else
      records =
        table.resource
        |> Ash.Query.for_read(table.read_action)
        |> AshA2ui.ContextRunner.apply_scope(scope)
        |> Ash.Query.load(table.loads)
        |> Ash.read!(table_read_opts(resolved_view, table, opts))

      {records, nil}
    end
  end

  # The caller-carried :query_state is the single table's state map, or (on
  # multi-table surfaces) an object keyed by table component name.
  defp query_params(resolved_view, table, opts) do
    carried = Keyword.get(opts, :query_state)

    state =
      if ResolvedView.multi_table?(resolved_view) do
        is_map(carried) && Map.get(carried, to_string(table.name))
      else
        carried
      end

    case is_map(state) && AshA2ui.QueryRunner.parse(table, %{"query" => state}) do
      {:ok, params} -> params
      _invalid_or_missing -> AshA2ui.QueryRunner.default_params(table.query)
    end
  end

  # Loads the option lists for the view's relationship selects and
  # pick_existing nested forms: the destination's primary read action with
  # the same actor/tenant/authorize? opts (policies apply to option reads),
  # sorted by `option_sort` and capped at `option_limit`. Returns
  # `%{name => [%{"label" => _, "value" => _}]}` — the shape written to the
  # reserved `/options/<name>` paths. Searchable sources load the same
  # initial page; the `"option_search"` action refreshes them.
  #
  # Picker contexts load through `AshA2ui.ContextRunner.load_options/5`
  # (dependency-filtered by the carried selections; a dependent context
  # whose parent is unselected loads `[]`).
  defp load_options!(resolved_view, selected, opts) do
    select_options =
      resolved_view
      |> ResolvedView.option_sources()
      |> Map.new(fn {name, source} ->
        records =
          source.destination
          |> Ash.Query.for_read(ResourceInfo.primary_action!(source.destination, :read).name)
          |> Ash.Query.sort([{source.option_sort, :asc}])
          |> Ash.Query.limit(source.option_limit)
          |> Ash.read!(option_read_opts(source.destination, opts))

        {name, Enum.map(records, &option_entry(&1, source))}
      end)

    context_options =
      for {name, context} <- resolved_view.contexts, context.picker, into: %{} do
        case AshA2ui.ContextRunner.load_options(
               resolved_view,
               context,
               selected,
               "",
               read_opts(resolved_view, opts)
             ) do
          {:ok, options} -> {name, options}
          {:error, error} -> raise Ash.Error.to_error_class(error)
        end
      end

    Map.merge(select_options, context_options)
  end

  # The initial /detail/<context> values: selected contexts fetch their
  # record (authorized, with the detail components' loads), unselected ones
  # render %{}.
  defp load_details!(resolved_view, selected, opts) do
    resolved_view.details
    |> Enum.group_by(& &1.context)
    |> Map.new(fn {context_name, details} ->
      {context_name, detail_value!(resolved_view, context_name, details, selected, opts)}
    end)
  end

  defp detail_value!(resolved_view, context_name, details, selected, opts) do
    case Map.get(selected, context_name) do
      nil ->
        %{}

      %{value: value} ->
        context = resolved_view.contexts[context_name]
        loads = details |> Enum.flat_map(& &1.loads) |> Enum.uniq()
        fields = details |> Enum.flat_map(& &1.fields) |> Enum.uniq()

        case AshA2ui.ContextRunner.fetch_selected(
               resolved_view,
               context,
               value,
               selected,
               read_opts(resolved_view, opts),
               loads
             ) do
          {:ok, record} -> ResolvedView.record_values(resolved_view, record, fields, opts)
          :not_found -> %{}
          {:error, error} -> raise Ash.Error.to_error_class(error)
        end
    end
  end

  @doc false
  # One `%{"label" => _, "value" => _}` option entry for a destination record
  # of the given option source. Shared with `AshA2ui.ActionHandler` (the
  # `option_search` refresh emits the same shape).
  @spec option_entry(Ash.Resource.record(), map) :: map
  def option_entry(record, source) do
    value = option_string(Map.get(record, source.option_value))
    label = Map.get(record, source.option_label)

    %{"label" => (label && option_string(label)) || value, "value" => value}
  end

  defp option_read_opts(destination, opts) do
    domain =
      ResourceInfo.domain(destination) || opts[:domain] ||
        raise(ArgumentError, "no domain configured for #{inspect(destination)}")

    [
      domain: domain,
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end

  defp option_string(%Date{} = date), do: Date.to_iso8601(date)
  defp option_string(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp option_string(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp option_string(value), do: to_string(value)

  # A related table (`resource`) reads in its own resource's domain.
  defp table_read_opts(resolved_view, table, opts) do
    read_opts = read_opts(resolved_view, opts)

    case ResourceInfo.domain(table.resource) do
      nil -> read_opts
      domain -> Keyword.put(read_opts, :domain, domain)
    end
  end

  defp read_opts(resolved_view, opts) do
    domain =
      opts[:domain] || ResourceInfo.domain(resolved_view.resource) ||
        raise(ArgumentError, "no domain configured for #{inspect(resolved_view.resource)}")

    [
      domain: domain,
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end
end
