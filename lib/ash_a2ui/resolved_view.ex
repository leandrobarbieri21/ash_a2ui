defmodule AshA2ui.ResolvedView do
  @moduledoc """
  The normalization seam between the DSL and the encoder: `resolve/2` turns a
  resource (or standalone UI module) plus request options into a plain struct
  that the encoder consumes. The encoder never reads compiled DSL state
  directly.

  Normalization semantics:

    * each component's `fields` list becomes the *effective rendering list*:
      `hidden` fields are dropped and the rest are ordered by the field's
      `order` (stable by declaration order within the component otherwise)
    * `fields` maps every field referenced by a component or declared as a
      `field` entity to fully-defaulted metadata: `label` defaults to the
      humanized field name, `widget` defaults via `AshA2ui.TypeMapper` on the
      attribute's Ash type/constraints, `format` is carried through
    * `read_action`/`create_action`/`update_action` fall back to the
      resource's primary action of the matching type when a component omits
      them
    * `selects` maps every form field backed by a `belongs_to` relationship
      (inferred by matching the field name against a relationship's
      `source_attribute`, or declared explicitly via the field's
      `relationship` option) to its resolved option-loading config; those
      fields default to the `:choice_picker` widget
    * `loads` is the `Ash.Query.load/2` statement covering every relationship
      path needed by `source` table columns plus every calculation/aggregate
      field rendered by the tables
    * `tables` is one resolved read scope per `:table` component (in
      declaration order): its component key, effective read action, resolved
      query, per-table loads/row_actions, and the frozen data-model paths
      its records/query state live at (see `t:table/0`)
    * `actions` maps Ash action names to their `AshA2ui.Action` metadata
      entities (refresh targets, prompt fields, visibility conditions);
      actions without an entity have no entry
    * `refreshes` maps Ash action names to the table components their
      success refreshes (from `action` entities); actions without an entry —
      or whose entity omits `refreshes` (`nil`) — refresh every table
    * each table's `loads` additionally covers the expression calculations
      referenced by `visible_when` conditions of the table's row actions, so
      per-row visibility can be evaluated on the loaded records
    * on single-table surfaces the legacy top-level `read_action` / `query` /
      `row_actions` / `loads` fields mirror the single table exactly as
      before; on multi-table surfaces `read_action`/`query` are `nil` and
      `row_actions`/`loads` are the union across tables
    * `bulk_actions` is the union of every table's `bulk_actions` (each
      table scope also carries its own list) — the `bulk_invoke` allowlist

  FROZEN CONTRACT — the struct fields and `resolve/2` signature are the
  interface every parallel track codes against; do not change outside an
  integration commit.
  """

  alias Ash.Resource.Info, as: ResourceInfo

  defstruct [
    :resource,
    :surface_id,
    :title,
    :record_label,
    :read_action,
    :create_action,
    :update_action,
    :query,
    spec_version: :v0_9_1,
    sectioned?: false,
    components: [],
    fields: %{},
    row_actions: [],
    bulk_actions: [],
    selects: %{},
    loads: [],
    tables: [],
    actions: %{},
    refreshes: %{},
    nested_forms: %{},
    contexts: %{},
    context_order: [],
    details: [],
    reports: []
  ]

  @typedoc """
  Resolved option-loading config for one relationship-backed form select.
  A non-empty `search_fields` (from the field's `option_search` option)
  makes the select searchable: options refresh through the `"option_search"`
  action and selection round-trips through `"option_select"` instead of a
  static ChoicePicker.
  """
  @type select :: %{
          relationship: atom,
          destination: module,
          option_label: atom,
          option_value: atom,
          option_sort: atom,
          option_limit: pos_integer,
          search_fields: [atom]
        }

  @typedoc """
  A resolved `nested_form` entity: the form-action argument it edits, the
  relationship + destination behind it, the inferred interaction mode
  (see `AshA2ui.ManagedForms.mode/1`), the create_inline sub-form `fields`
  (`[]` in pick_existing mode), and the pick_existing option-loading config
  (option keys resolved like a select's; `search_fields` from
  `option_search`).
  """
  @type nested_form :: %{
          argument: atom,
          relationship: atom,
          destination: module,
          mode: :pick_existing | :create_inline,
          fields: [atom],
          label: String.t(),
          option_label: atom,
          option_value: atom,
          option_sort: atom,
          option_limit: pos_integer,
          search_fields: [atom]
        }

  @typedoc """
  A fully resolved table scope — one per `:table` component, in declaration
  order. `name` is the component key (`:table` for the unnamed table);
  `records_path`/`query_path` are the frozen data-model paths this table's
  records and query state live at (`/records` + `/query` on single-table
  surfaces, `/records/<name>` + `/query/<name>` on multi-table surfaces;
  `query_path` is `nil` when the table declares no `query`).

  The `resource`/`read_action`/`query`/`loads` keys make a table scope a
  drop-in read scope for `AshA2ui.QueryRunner`.

  A table whose component declares a `sections` block is a **template**: its
  `sections` key carries the resolved dynamic-section config, and
  `AshA2ui.Sections.expand/2` replaces it with one concrete table per
  section record before encoding/dispatch — each with a runtime string
  `name`, runtime-scoped paths, and a `section` key
  (`%{value:, label:, filter: {attribute, value}}`) its reads AND on.
  """
  @type table :: %{
          name: atom | String.t(),
          component: AshA2ui.Component.t(),
          resource: module,
          read_action: atom | nil,
          query: AshA2ui.Query.t() | nil,
          loads: list,
          row_actions: [atom],
          bulk_actions: [atom],
          records_path: String.t(),
          query_path: String.t() | nil,
          context_filter: [{atom, atom}],
          require_context: [atom],
          select_context: atom | nil,
          sections: map | nil,
          editable: map | nil,
          export: map | nil
        }

  @typedoc """
  A resolved `context` entity: the surface-level record selection's resource
  and fully-defaulted option-loading config (`option_*` keys resolved like a
  relationship select's; `search_fields` from `option_search`), plus the
  dependency (`depends_on` + `depends_on_path`), `auto_select_single` and
  `picker` settings. Selection state lives at `/context/<name>`, options at
  `/options/<name>`.
  """
  @type context :: %{
          name: atom,
          resource: module,
          label: String.t(),
          option_label: atom,
          option_value: atom,
          option_sort: atom,
          option_limit: pos_integer,
          search_fields: [atom],
          depends_on: atom | nil,
          depends_on_path: [atom] | nil,
          auto_select_single: boolean,
          picker: boolean
        }

  @typedoc """
  A resolved `:detail` component: the component key (`name`), the context it
  renders, the effective field list, and the `Ash.Query.load/2` statement its
  record fetch needs (source paths + calculations/aggregates, computed
  against the **context's** resource). The record map is written to
  `/detail/<context>`.
  """
  @type detail :: %{
          name: atom,
          component: AshA2ui.Component.t(),
          context: atom,
          fields: [atom],
          loads: list,
          detail_path: String.t()
        }

  @typedoc """
  A resolved `:report` component (aggregate/report queries): the generic Ash
  `action` it invokes, the `params` (argument names rendered as inputs, bound
  under `<path>/params`), the `fields` column allowlist (keys of the
  returned row maps, in render order), and the reserved `/report/<name>`
  data-model path its params/rows live under.
  """
  @type report :: %{
          name: atom,
          component: AshA2ui.Component.t(),
          action: atom,
          params: [atom],
          fields: [atom],
          path: String.t(),
          export: map | nil
        }

  @type t :: %__MODULE__{
          resource: module,
          surface_id: String.t(),
          title: String.t() | nil,
          record_label: String.t() | nil,
          spec_version: :v0_9_1 | :v1_0,
          sectioned?: boolean,
          components: [AshA2ui.Component.t()],
          fields: %{atom => AshA2ui.Field.t()},
          read_action: atom | nil,
          create_action: atom | nil,
          update_action: atom | nil,
          query: AshA2ui.Query.t() | nil,
          row_actions: [atom],
          bulk_actions: [atom],
          selects: %{atom => select},
          loads: list,
          tables: [table],
          actions: %{atom => AshA2ui.Action.t()},
          refreshes: %{atom => [atom] | nil},
          nested_forms: %{atom => nested_form},
          contexts: %{atom => context},
          context_order: [atom],
          details: [detail],
          reports: [report]
        }

  @option_label_fallbacks [:name, :title, :label, :username, :email]

  @resolve_opts [
    :actor,
    :tenant,
    :domain,
    :authorize?,
    :query_state,
    :context_state,
    :surface_properties,
    :spec_version
  ]

  @doc """
  Resolves the `a2ui` DSL of `resource_or_ui_module` (an `Ash.Resource` using
  the `AshA2ui` extension, or an `AshA2ui.Standalone` UI module with
  `for_resource`) into a `#{inspect(__MODULE__)}` struct.

  ## Options

    * `:actor` / `:tenant` / `:authorize?` / `:domain` / `:query_state` —
      reserved for data loading (see `AshA2ui.Info.build_surface/2`);
      validated and passed through, not consumed by normalization itself.
    * `:spec_version` — `"0.9.1"` or `"1.0"`: overrides the surface's
      declared `spec_version` for this resolve. Transports whose renderer
      only speaks one protocol version (see the External Transports topic)
      use this to pin the wire version without touching the DSL.
  """
  @spec resolve(module | Spark.Dsl.t(), keyword) :: t()
  def resolve(resource_or_ui_module, opts \\ []) do
    Keyword.validate!(opts, @resolve_opts)

    resource = AshA2ui.Info.resource!(resource_or_ui_module)
    components = AshA2ui.Info.components(resource_or_ui_module)
    declared_fields = AshA2ui.Info.fields(resource_or_ui_module)

    form = Enum.find(components, &(&1.name == :form))
    selects = resolve_selects(resource, form, Map.new(declared_fields, &{&1.name, &1}))

    fields = normalize_fields(resource, components, declared_fields, Map.keys(selects))
    components = Enum.map(components, &normalize_component(&1, fields))

    form = Enum.find(components, &(&1.name == :form))

    actions =
      Map.new(AshA2ui.Info.action_settings(resource_or_ui_module), &{&1.name, &1})

    tables = resolve_tables(resource_or_ui_module, resource, components, fields, actions)
    sectioned? = Enum.any?(tables, & &1.sections)
    single = if match?([_only], tables) and not sectioned?, do: hd(tables)

    create_action = component_action(form, :create_action, resource, :create)
    update_action = component_action(form, :update_action, resource, :update)
    contexts = resolve_contexts(resource_or_ui_module)

    %__MODULE__{
      resource: resource,
      surface_id: surface_id(resource_or_ui_module, resource),
      title: optional_label(resource_or_ui_module, :a2ui_title),
      record_label: optional_label(resource_or_ui_module, :a2ui_record_label),
      spec_version: spec_version(resource_or_ui_module, opts[:spec_version]),
      sectioned?: sectioned?,
      components: components,
      fields: fields,
      read_action: single && single.read_action,
      create_action: create_action,
      update_action: update_action,
      query: single && single.query,
      row_actions: tables |> Enum.flat_map(& &1.row_actions) |> Enum.uniq(),
      bulk_actions: tables |> Enum.flat_map(& &1.bulk_actions) |> Enum.uniq(),
      selects: selects,
      loads: tables |> Enum.flat_map(& &1.loads) |> Enum.uniq(),
      tables: tables,
      actions: actions,
      refreshes: Map.new(actions, fn {name, action} -> {name, action.refreshes} end),
      nested_forms: resolve_nested_forms(resource, form, create_action || update_action),
      contexts: Map.new(contexts, &{&1.name, &1}),
      context_order: Enum.map(contexts, & &1.name),
      details: resolve_details(components, contexts, fields),
      reports: resolve_reports(resource, components)
    }
  end

  @doc """
  Whether the surface declares any contexts (switching on the reserved
  `/context/<name>` state, the context picker sections, and the
  `"contexts"` binding write/query action contexts carry).
  """
  @spec contexts?(t()) :: boolean
  def contexts?(%__MODULE__{contexts: contexts}), do: contexts != %{}

  @doc """
  The initial `/context` state: one `%{"search" => "", "value" => "",
  "label" => ""}` entry per declared context. Empty on context-less surfaces
  (which carry no `"context"` key at all — the frozen pre-context data-model
  shape is unchanged).
  """
  @spec context_state(t()) :: %{String.t() => map}
  def context_state(%__MODULE__{} = view) do
    Map.new(view.contexts, fn {name, _context} ->
      {to_string(name), %{"search" => "", "value" => "", "label" => ""}}
    end)
  end

  @doc """
  The initial `/detail` state: one empty map per `:detail` component, keyed
  by the rendered context's name. Empty on surfaces without details.
  """
  @spec detail_state(t()) :: %{String.t() => map}
  def detail_state(%__MODULE__{details: details}) do
    Map.new(details, fn detail -> {to_string(detail.context), %{}} end)
  end

  @doc """
  Serializes `fields` of an Ash `record` to the wire map shape (string keys,
  JSON-safe values — dates/datetimes to ISO 8601, decimals to strings, atoms
  to strings — with `"id"` always included). Declared `source` fields walk
  the loaded relationship path (nil-safe: an unloaded or nil relationship
  serializes to `""`). When any of `fields` declares `link`/`links`, the
  map carries the reserved `"_links"` key (see `AshA2ui.Links`); `opts`
  carries the render's `:actor`/`:tenant` for the `AshA2ui.LinkResolver`.

  Used for `/detail/<context>` record values; matches the row serialization
  of `/records`.
  """
  @spec record_values(t(), Ash.Resource.record(), [atom], keyword) :: %{String.t() => term}
  def record_values(%__MODULE__{} = view, record, fields, opts \\ []) do
    row =
      fields
      |> Map.new(fn name -> {to_string(name), serialized_field(view, record, name)} end)
      |> Map.put("id", json_safe(Map.get(record, :id)))

    view.fields
    |> then(&AshA2ui.Links.context(record.__struct__, &1, fields, opts))
    |> AshA2ui.Links.row_data(record, row)
    |> Map.merge(row)
  end

  defp serialized_field(view, record, name) do
    case view.fields[name] do
      %{source: [_ | _] = source} ->
        case walk_source(record, source) do
          nil -> ""
          value -> json_safe(value)
        end

      field ->
        case AshA2ui.Links.virtual_value(field, record) do
          {:ok, value} -> value
          :not_virtual -> json_safe(Map.get(record, name))
        end
    end
  end

  defp walk_source(record, [attribute]), do: Map.get(record, attribute)

  defp walk_source(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> nil
      nil -> nil
      related -> walk_source(related, rest)
    end
  end

  defp json_safe(%Ash.NotLoaded{}), do: nil
  defp json_safe(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp json_safe(%Date{} = date), do: Date.to_iso8601(date)
  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  defp json_safe(%Time{} = time), do: Time.to_iso8601(time)
  defp json_safe(value) when is_struct(value), do: inspect(value)

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp json_safe(value), do: value

  @doc """
  Whether the view is a multi-table surface (two or more `:table`
  components, or any table with a `sections` block — the runtime table
  count of a dynamic set must not change the data-model shape), switching
  the data model to the scoped `/records/<component_name>` /
  `/query/<component_name>` paths.
  """
  @spec multi_table?(t()) :: boolean
  def multi_table?(%__MODULE__{sectioned?: true}), do: true
  def multi_table?(%__MODULE__{tables: tables}), do: match?([_, _ | _], tables)

  @doc """
  Every option list the surface loads (and the `"option_search"` action may
  refresh), keyed by the `/options/<name>` segment: relationship selects
  (`kind: :select`) plus pick_existing nested forms (`kind: :nested_form`).
  Each source carries the resolved `destination` / `option_label` /
  `option_value` / `option_sort` / `option_limit` / `search_fields` keys.
  """
  @spec option_sources(t()) :: %{atom => map}
  def option_sources(%__MODULE__{} = view) do
    selects =
      Map.new(view.selects, fn {name, select} -> {name, Map.put(select, :kind, :select)} end)

    pickers =
      for {name, %{mode: :pick_existing} = nested} <- view.nested_forms, into: %{} do
        {name,
         %{
           kind: :nested_form,
           relationship: nested.relationship,
           destination: nested.destination,
           option_label: nested.option_label,
           option_value: nested.option_value,
           option_sort: nested.option_sort,
           option_limit: nested.option_limit,
           search_fields: nested.search_fields
         }}
      end

    Map.merge(selects, pickers)
  end

  @doc """
  The `/select/<name>` state entries the surface's data model carries: one
  `%{"search" => "", "label" => ""}` per **searchable** relationship select
  and one `%{"search" => "", "picked" => []}` per pick_existing nested form
  (`"search"` meaningful only when searchable). Empty when the surface uses
  neither — the frozen pre-wave-5 data-model shape is unchanged.
  """
  @spec select_state(t()) :: %{String.t() => map}
  def select_state(%__MODULE__{} = view) do
    searchable =
      for {name, %{search_fields: [_ | _]}} <- view.selects, into: %{} do
        {to_string(name), %{"search" => "", "label" => ""}}
      end

    pickers =
      for {name, %{mode: :pick_existing}} <- view.nested_forms, into: %{} do
        {to_string(name), %{"search" => "", "picked" => []}}
      end

    Map.merge(searchable, pickers)
  end

  @doc """
  The initial (and post-success) `/form` value: empty, except nested-form
  arguments start as stable empty row arrays so their List templates and
  `"rows"` context bindings always have a value.
  """
  @spec initial_form(t()) :: map
  def initial_form(%__MODULE__{} = view) do
    Map.new(view.nested_forms, fn {name, _nested} -> {to_string(name), []} end)
  end

  @doc """
  The `Ash.Query.load/2` statement `select_row` record fetches need beyond
  the table loads: the relationship behind every searchable select (to
  derive the current selection's label) and behind every nested form (to
  populate the argument's rows).
  """
  @spec form_loads(t()) :: [atom]
  def form_loads(%__MODULE__{} = view) do
    select_loads =
      for {_name, %{search_fields: [_ | _], relationship: relationship}} <- view.selects,
          do: relationship

    nested_loads =
      for {_name, %{relationship: relationship}} <- view.nested_forms, do: relationship

    Enum.uniq(select_loads ++ nested_loads)
  end

  # --- nested forms -------------------------------------------------------------

  # Nested forms resolve against one form action (create when declared, else
  # update — the verifier guarantees every form action agrees on the change
  # and mode, so either works). Skipped without a form or resolvable action.
  defp resolve_nested_forms(resource, form, action_name)

  defp resolve_nested_forms(_resource, nil, _action_name), do: %{}
  defp resolve_nested_forms(_resource, _form, nil), do: %{}

  defp resolve_nested_forms(resource, form, action_name) do
    Map.new(form.nested_forms, fn nested ->
      {nested.name, resolve_nested_form(resource, nested, action_name)}
    end)
  end

  defp resolve_nested_form(resource, nested, action_name) do
    case AshA2ui.ManagedForms.manage(resource, action_name, nested.name) do
      {:ok, %{relationship: relationship} = manage} ->
        {:ok, mode} = AshA2ui.ManagedForms.mode(manage.opts)
        destination = relationship.destination

        option_value =
          nested.option_value || nested_single_primary_key!(nested, destination)

        option_label = nested.option_label || default_option_label(destination, option_value)

        %{
          argument: nested.name,
          relationship: relationship.name,
          destination: destination,
          mode: mode,
          fields: nested_fields(nested, mode, manage),
          label: nested.label || humanize(nested.name),
          option_label: option_label,
          option_value: option_value,
          option_sort: nested.option_sort || option_label,
          option_limit: nested.option_limit,
          search_fields: nested.option_search
        }

      :error ->
        raise ArgumentError,
              "nested_form #{inspect(nested.name)} does not map to a manage_relationship " <>
                "change consuming argument #{inspect(nested.name)} on action " <>
                "#{inspect(action_name)} of #{inspect(resource)}"
    end
  end

  defp nested_fields(_nested, :pick_existing, _manage), do: []

  defp nested_fields(nested, :create_inline, manage) do
    nested.fields || AshA2ui.ManagedForms.default_fields(manage) ||
      raise(
        ArgumentError,
        "cannot infer fields for nested_form #{inspect(nested.name)}: declare them explicitly"
      )
  end

  defp nested_single_primary_key!(nested, destination) do
    case ResourceInfo.primary_key(destination) do
      [key] ->
        key

      composite ->
        raise ArgumentError,
              "cannot infer option_value for nested_form #{inspect(nested.name)}: " <>
                "#{inspect(destination)} has a composite primary key " <>
                "#{inspect(composite)} — set option_value explicitly"
    end
  end

  # --- table scopes -------------------------------------------------------------

  defp resolve_tables(resource_or_ui_module, resource, components, fields, actions) do
    table_components = Enum.filter(components, &(&1.name == :table))

    multi? =
      match?([_, _ | _], table_components) or Enum.any?(table_components, & &1.sections)

    Enum.map(table_components, fn component ->
      name = AshA2ui.Component.key(component)
      query = resolve_query(resource_or_ui_module, component)
      # A related table (`resource` on the component) reads its own resource.
      resource = AshA2ui.Component.resource(component, resource)

      %{
        name: name,
        component: component,
        resource: resource,
        read_action: component_action(component, :read_action, resource, :read),
        query: query,
        loads:
          Enum.uniq(
            loads(resource, component, fields) ++ condition_loads(resource, component, actions)
          ),
        row_actions: component.row_actions,
        bulk_actions: component.bulk_actions,
        records_path: (multi? && "/records/#{name}") || "/records",
        query_path: query && ((multi? && "/query/#{name}") || "/query"),
        context_filter: component.context_filter,
        require_context: component.require_context,
        select_context: component.select_context,
        sections: resolve_sections(component.sections),
        editable: resolve_editable(resource, component.editable),
        export: resolve_export(component, component.fields || public_attribute_names(resource))
      }
    end)
  end

  # The resolved CSV-export config of a table or report: filename, the
  # exportable columns (defaulting to the component's fields), column
  # selection and the table row cap. Consumed by the encoder (the Export
  # button + optional column checkboxes) and the "export" action handler.
  defp resolve_export(%{export: nil}, _default_columns), do: nil

  defp resolve_export(component, default_columns) do
    export = component.export

    %{
      filename: export.filename || "#{AshA2ui.Component.key(component)}.csv",
      columns: export.columns || default_columns,
      column_select: export.column_select,
      limit: export.limit
    }
  end

  defp public_attribute_names(resource) do
    resource
    |> ResourceInfo.public_attributes()
    |> Enum.map(& &1.name)
  end

  # The resolved inline-cell-editing config of a table: the editable field
  # allowlist and the effective update action a cell commit runs.
  defp resolve_editable(_resource, nil), do: nil

  defp resolve_editable(resource, editable) do
    %{
      fields: editable.fields,
      update_action: editable.update_action || primary_action_name(resource, :update)
    }
  end

  # The resolved dynamic-section config of a sectioned table template, with
  # the label/value/sort/read_action defaults applied (like an option
  # source's). Consumed by `AshA2ui.Sections.expand/2`.
  defp resolve_sections(nil), do: nil

  defp resolve_sections(sections) do
    value = sections.value || sections_single_primary_key!(sections)
    label = sections.label || default_option_label(sections.source, value)

    %{
      source: sections.source,
      scope_by: sections.scope_by,
      label: label,
      value: value,
      read_action: sections.read_action || primary_action_name(sections.source, :read),
      sort: sections.sort || label,
      limit: sections.limit
    }
  end

  defp sections_single_primary_key!(sections) do
    case ResourceInfo.primary_key(sections.source) do
      [key] ->
        key

      composite ->
        raise ArgumentError,
              "cannot infer the section value for a sections block: " <>
                "#{inspect(sections.source)} has a composite primary key " <>
                "#{inspect(composite)} — set value explicitly"
    end
  end

  # --- reports --------------------------------------------------------------------

  # One resolved report per `:report` component: the generic action, the
  # rendered params (defaulting to all of the action's arguments) and the
  # frozen /report/<name> data-model path.
  defp resolve_reports(resource, components) do
    components
    |> Enum.filter(&(&1.name == :report))
    |> Enum.map(fn component ->
      name = AshA2ui.Component.key(component)

      %{
        name: name,
        component: component,
        action: component.action,
        params: component.params || default_report_params(resource, component),
        fields: component.fields || [],
        path: "/report/#{name}",
        export: resolve_export(component, component.fields || [])
      }
    end)
  end

  defp default_report_params(resource, component) do
    case component.action && ResourceInfo.action(resource, component.action) do
      %{arguments: arguments} -> Enum.map(arguments, & &1.name)
      _missing -> []
    end
  end

  @doc """
  The initial `/report` state: one `%{"params" => %{<param> => ""}, "rows"
  => []}` entry per `:report` component. Empty on surfaces without reports
  (which carry no `"report"` key at all — the frozen data-model shape is
  unchanged).
  """
  @spec report_state(t()) :: %{String.t() => map}
  def report_state(%__MODULE__{reports: reports}) do
    Map.new(reports, fn report ->
      {to_string(report.name),
       %{"params" => Map.new(report.params, &{to_string(&1), ""}), "rows" => []}}
    end)
  end

  @doc """
  The initial `/export` state: one `%{"columns" => %{<column> => true}}`
  entry per component whose `export` declares `column_select` (all columns
  checked). Empty on surfaces without column-selectable exports (which
  carry no `"export"` key at all — the frozen data-model shape is
  unchanged).
  """
  @spec export_state(t()) :: %{String.t() => map}
  def export_state(%__MODULE__{} = view) do
    (view.tables ++ view.reports)
    |> Enum.filter(&match?(%{export: %{column_select: true}}, &1))
    |> Map.new(fn component ->
      {to_string(component.name),
       %{"columns" => Map.new(component.export.columns, &{to_string(&1), true})}}
    end)
  end

  # --- contexts and details -----------------------------------------------------

  defp resolve_contexts(resource_or_ui_module) do
    resource_or_ui_module
    |> AshA2ui.Info.contexts()
    |> Enum.map(&resolve_context/1)
  end

  defp resolve_context(context) do
    option_value = context.option_value || context_single_primary_key!(context)
    option_label = context.option_label || default_option_label(context.resource, option_value)

    %{
      name: context.name,
      resource: context.resource,
      label: context.label || humanize(context.name),
      option_label: option_label,
      option_value: option_value,
      option_sort: context.option_sort || option_label,
      option_limit: context.option_limit,
      search_fields: context.option_search,
      depends_on: context.depends_on,
      depends_on_path: context.depends_on_path,
      auto_select_single: context.auto_select_single,
      picker: context.picker
    }
  end

  defp context_single_primary_key!(context) do
    case ResourceInfo.primary_key(context.resource) do
      [key] ->
        key

      composite ->
        raise ArgumentError,
              "cannot infer option_value for context #{inspect(context.name)}: " <>
                "#{inspect(context.resource)} has a composite primary key " <>
                "#{inspect(composite)} — set option_value explicitly"
    end
  end

  # Detail loads are computed against the CONTEXT's resource (details may
  # render a different resource than the surface's), reusing the table
  # loads logic for source paths and calculations/aggregates.
  defp resolve_details(components, contexts, fields) do
    by_name = Map.new(contexts, &{&1.name, &1})

    components
    |> Enum.filter(&(&1.name == :detail))
    |> Enum.map(fn component ->
      context =
        Map.get(by_name, component.context) ||
          raise(
            ArgumentError,
            "detail component #{inspect(AshA2ui.Component.key(component))} references " <>
              "undeclared context #{inspect(component.context)}"
          )

      detail_fields = component.fields || []

      %{
        name: AshA2ui.Component.key(component),
        component: component,
        context: context.name,
        fields: detail_fields,
        loads: field_loads(context.resource, detail_fields, fields),
        detail_path: "/detail/#{context.name}"
      }
    end)
  end

  # Calculations referenced by visible_when conditions of this table's row
  # actions must be loaded with the records so per-row visibility can be
  # evaluated (deduplicated against the rendered-field loads).
  defp condition_loads(resource, component, actions) do
    component.row_actions
    |> Enum.flat_map(fn row_action ->
      case actions[row_action] do
        %{visible_when: [_ | _] = conditions} ->
          AshA2ui.Conditions.condition_loads(resource, conditions)

        _no_conditions ->
          []
      end
    end)
    |> Enum.uniq()
  end

  # --- relationship selects ---------------------------------------------------

  # A form field is a relationship select when it declares an explicit
  # `relationship`, or when its name matches a `belongs_to` relationship's
  # `source_attribute` (the AshSDUI-derived inference).
  defp resolve_selects(_resource, nil, _declared), do: %{}

  defp resolve_selects(resource, form, declared) do
    (form.fields || [])
    |> Enum.flat_map(fn name ->
      field = declared[name] || %AshA2ui.Field{name: name}

      case select_relationship(resource, field) do
        nil -> []
        relationship -> [{name, resolve_select(field, relationship)}]
      end
    end)
    |> Map.new()
  end

  defp select_relationship(resource, %{relationship: relationship})
       when not is_nil(relationship) do
    ResourceInfo.relationship(resource, relationship)
  end

  defp select_relationship(resource, field) do
    resource
    |> ResourceInfo.relationships()
    |> Enum.find(&(&1.type == :belongs_to and &1.source_attribute == field.name))
  end

  defp resolve_select(field, relationship) do
    destination = relationship.destination
    option_value = field.option_value || single_primary_key!(field, destination)
    option_label = field.option_label || default_option_label(destination, option_value)

    %{
      relationship: relationship.name,
      destination: destination,
      option_label: option_label,
      option_value: option_value,
      option_sort: field.option_sort || option_label,
      option_limit: field.option_limit,
      search_fields: field.option_search
    }
  end

  # The option-label fallback chain: the first existing public attribute of
  # [:name, :title, :label, :username, :email], else the option value itself.
  defp default_option_label(destination, option_value) do
    Enum.find(@option_label_fallbacks, option_value, fn name ->
      match?(%{public?: true}, ResourceInfo.attribute(destination, name))
    end)
  end

  defp single_primary_key!(field, destination) do
    case ResourceInfo.primary_key(destination) do
      [key] ->
        key

      composite ->
        raise ArgumentError,
              "cannot infer option_value for field #{inspect(field.name)}: " <>
                "#{inspect(destination)} has a composite primary key " <>
                "#{inspect(composite)} — set option_value explicitly"
    end
  end

  # --- record loads --------------------------------------------------------------

  # The Ash.Query.load statement covering a table's rendered fields: one
  # entry per relationship prefix of a `source` column ([:user, :email] ->
  # :user; [:a, :b, :attr] -> {:a, [:b]}) plus the name of every field that
  # is a public calculation or aggregate of the resource.
  defp loads(resource, table, fields), do: field_loads(resource, table.fields, fields)

  defp field_loads(resource, field_names, fields) do
    source_loads =
      field_names
      |> Enum.map(&(fields[&1] && fields[&1].source))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&source_load_path(resource, &1))
      |> Enum.reject(&(&1 == []))
      |> Enum.uniq()
      |> Enum.map(&path_to_load/1)

    calc_loads = Enum.filter(field_names, &calculation_or_aggregate?(resource, &1))

    Enum.uniq(source_loads ++ calc_loads ++ AshA2ui.Links.loads(resource, field_names, fields))
  end

  # A source path loads its relationship prefix — and, when the terminal
  # step is a calculation/aggregate of the final destination (a decrypted
  # display name, a count), the terminal too.
  defp source_load_path(resource, source) do
    {relationships, [terminal]} = Enum.split(source, -1)

    destination =
      Enum.reduce_while(relationships, resource, fn step, current ->
        case ResourceInfo.relationship(current, step) do
          %{destination: destination} -> {:cont, destination}
          nil -> {:halt, nil}
        end
      end)

    if destination && calculation_or_aggregate?(destination, terminal),
      do: source,
      else: relationships
  end

  defp calculation_or_aggregate?(resource, name) do
    not is_nil(ResourceInfo.calculation(resource, name)) or
      not is_nil(ResourceInfo.aggregate(resource, name))
  end

  defp path_to_load([relationship]), do: relationship
  defp path_to_load([relationship | rest]), do: {relationship, [path_to_load(rest)]}

  # The query config referenced by the table component; the reference is
  # verified at compile time (VerifyQueries), so a miss here only happens for
  # surfaces without a table or without a query option.
  defp resolve_query(resource_or_ui_module, %{query: query_name}) when not is_nil(query_name) do
    resource_or_ui_module
    |> AshA2ui.Info.queries()
    |> Enum.find(&(&1.name == query_name))
  end

  defp resolve_query(_resource_or_ui_module, _table), do: nil

  # `title` and `record_label` are both optional and both default to the
  # derived resource label, so absence is the common case and must stay cheap.
  defp optional_label(resource_or_ui_module, fun) do
    case apply(AshA2ui.Info, fun, [resource_or_ui_module]) do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end

  defp surface_id(resource_or_ui_module, resource) do
    case AshA2ui.Info.a2ui_surface_id(resource_or_ui_module) do
      {:ok, surface_id} -> surface_id
      :error -> default_surface_id(resource)
    end
  end

  # The declared `spec_version` DSL option, normalized to the version atom
  # the encoders and handler dispatch on. Defaults to :v0_9_1 (the DSL
  # default), so pre-1.0 surfaces are untouched. A per-resolve `:spec_version`
  # override (a transport pinning the wire version) wins over the DSL.
  defp spec_version(resource_or_ui_module, override) do
    case override || declared_spec_version(resource_or_ui_module) do
      "1.0" ->
        :v1_0

      "0.9.1" ->
        :v0_9_1

      other ->
        raise ArgumentError, "spec_version must be \"0.9.1\" or \"1.0\", got: #{inspect(other)}"
    end
  end

  # The DSL option has a default, so the Info getter always returns {:ok, _}.
  defp declared_spec_version(resource_or_ui_module) do
    {:ok, version} = AshA2ui.Info.a2ui_spec_version(resource_or_ui_module)
    version
  end

  # A declared action wins; otherwise fall back to the resource's primary
  # action of the matching type. No component of that kind -> no action.
  defp component_action(nil, _key, _resource, _type), do: nil

  defp component_action(component, key, resource, type) do
    Map.fetch!(component, key) || primary_action_name(resource, type)
  end

  # Effective field metadata for every field referenced by a component or
  # declared as a `field` entity, with label/widget defaults applied
  # (relationship-select fields default to `:choice_picker`).
  defp normalize_fields(resource, components, declared_fields, select_names) do
    declared = Map.new(declared_fields, &{&1.name, &1})

    components
    |> Enum.flat_map(&(&1.fields || []))
    |> Enum.concat(Map.keys(declared))
    |> Enum.uniq()
    |> Map.new(fn name ->
      field = declared[name] || %AshA2ui.Field{name: name}

      default_widget =
        if name in select_names do
          :choice_picker
        else
          default_widget(resource, name)
        end

      {name,
       %{
         field
         | label: field.label || humanize(name),
           widget: field.widget || default_widget
       }}
    end)
  end

  # Effective rendering list: hidden fields dropped, ordered by field order
  # (Enum.sort_by is stable, preserving declaration order on ties). Group
  # and row_layout field references are normalized against the effective
  # list (hidden fields drop out of groups and meta grids too) with their
  # label/meta defaults applied.
  defp normalize_component(component, fields) do
    effective =
      (component.fields || [])
      |> Enum.reject(&fields[&1].hidden)
      |> Enum.sort_by(&fields[&1].order)

    %{
      component
      | fields: effective,
        groups: Enum.map(component.groups, &normalize_group(&1, effective)),
        row_layout: normalize_row_layout(component.row_layout, effective)
    }
  end

  defp normalize_group(group, effective) do
    %{
      group
      | label: group.label || humanize(group.name),
        fields: Enum.filter(group.fields, &(&1 in effective))
    }
  end

  # `meta` defaults to the table's effective fields minus title and badge,
  # in field order; an explicit meta list keeps its declared order.
  defp normalize_row_layout(nil, _effective), do: nil

  defp normalize_row_layout(layout, effective) do
    meta =
      case layout.meta do
        nil -> effective -- Enum.reject([layout.title, layout.badge], &is_nil/1)
        meta -> Enum.filter(meta, &(&1 in effective))
      end

    %{layout | meta: meta}
  end

  # Calculations carry a type/constraints just like attributes; aggregates
  # (and unknown fields) fall back to the TypeMapper default (:text_field —
  # the widget is irrelevant for table display anyway).
  defp default_widget(resource, name) do
    case ResourceInfo.attribute(resource, name) || ResourceInfo.calculation(resource, name) do
      %{type: type, constraints: constraints} -> AshA2ui.TypeMapper.widget_for(type, constraints)
      nil -> AshA2ui.TypeMapper.widget_for(nil)
    end
  end

  defp primary_action_name(resource, type) do
    case Ash.Resource.Info.primary_action(resource, type) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp default_surface_id(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
