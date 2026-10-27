defmodule AshA2ui.Dynamic.Promoter do
  @moduledoc """
  Generates a checked-in standalone UI module (`use AshA2ui.Standalone` with
  an `a2ui do ... end` block) from a validated `AshA2ui.Dynamic` surface
  spec — the "promote to code" step of the spec-as-artifact lifecycle.

  The generated source is formatted (with the extension's own
  `locals_without_parens`, derived from the DSL definition), compile-ready,
  and carries a provenance comment with the spec's content fingerprint.
  Promoting then resolving the generated module produces a surface
  equivalent to resolving the spec directly — the promotion changes *where*
  the declaration lives (reviewable code instead of stored data), never what
  it renders.

  Use through `AshA2ui.Dynamic.to_dsl_source/2`.
  """

  alias AshA2ui.Dynamic.Parser
  alias AshA2ui.Dynamic.Serializer

  # Spec keys per entity, in emitted order, shaped like the parser's
  # conversions (see AshA2ui.Dynamic.Parser.option_shape/1): the promoter is
  # the parser's inverse, JSON spec values back to DSL literals.
  @component_options [
    fields: :name_list,
    read_action: :name,
    create_action: :name,
    update_action: :name,
    row_actions: :name_list,
    query: :name,
    context_filter: :name_keyword,
    require_context: :name_list,
    select_context: :name,
    context: :name,
    display: :name,
    date_field: :name,
    end_date_field: :name,
    granularity: :name,
    granularities: :name_list
  ]

  @row_layout_options [
    title: :name,
    badge: :name,
    badge_text: :string_keyword,
    badge_tones: :name_keyword,
    meta: :name_list,
    columns: :raw
  ]

  @column_options [
    subtitle: :name,
    icon: :name,
    icon_names: :name_keyword,
    icon_tones: :name_keyword,
    icon_labels: :string_keyword,
    more: :name,
    detail: :name,
    detail_date: :name,
    detail_text: :string_keyword,
    detail_icon_names: :name_keyword,
    detail_icon_tones: :name_keyword
  ]

  @primary_action_options [
    label_from: :name,
    labels: :string_keyword,
    variants: :name_keyword,
    label: :raw,
    variant: :name
  ]

  @group_options [label: :raw, columns: :raw, fields: :name_list]

  @nested_form_options [
    label: :raw,
    fields: :name_list,
    option_label: :name,
    option_value: :name,
    option_sort: :name,
    option_limit: :raw,
    option_search: :name_list
  ]

  @section_options [
    scope_by: :name,
    label: :name,
    value: :name,
    read_action: :name,
    sort: :name,
    values: :value_list,
    labels: :string_keyword,
    swimlanes_by: :name,
    swimlane_values: :value_list,
    swimlane_labels: :string_keyword,
    swimlane_tones: :name_keyword,
    limit: :raw
  ]

  @query_options [
    search_fields: :search_fields,
    sortable: :name_list,
    range_filters: :name_list,
    filters: :name_list,
    hidden_filters: :name_list,
    default_preset: :name,
    preset_picker: :raw,
    apply_on_change: :raw,
    default_sort: :default_sort,
    page_size: :raw,
    max_page_size: :raw
  ]

  @preset_options [filter: :raw_keyword, read_action: :name, calendar_anchor: :raw]

  @field_options [
    label: :raw,
    widget: :name,
    format: :name,
    order: :raw,
    hidden: :raw,
    source: :name_list,
    relationship: :name,
    option_label: :name,
    option_value: :name,
    option_sort: :name,
    option_limit: :raw,
    option_search: :name_list,
    link: :link,
    links: :name,
    link_label: :name
  ]

  @action_options [
    label: :raw,
    refreshes: :name_list,
    prompt_fields: :name_list,
    prompt_title: :raw,
    visible_when: :raw_keyword,
    via: :via
  ]

  @context_options [
    label: :raw,
    option_label: :name,
    option_value: :name,
    option_sort: :name,
    option_limit: :raw,
    option_search: :name_list,
    depends_on: :name,
    depends_on_path: :name_list,
    auto_select_single: :raw,
    picker: :raw
  ]

  @doc """
  Generates the module source for a **pre-validated** spec (callers resolve
  first; see `AshA2ui.Dynamic.to_dsl_source/2`). Returns the formatted
  source string.
  """
  @spec generate(map, module, module, %{String.t() => module}, keyword) :: String.t()
  def generate(spec, module, resource, allowlist, opts) do
    surface_id = Keyword.get_lazy(opts, :surface_id, fn -> default_surface_id(module) end)
    spec_version = Keyword.get(opts, :spec_version, "0.9.1")

    body =
      [
        "for_resource #{inspect(resource)}",
        ~s(surface_id "#{surface_id}"),
        spec_version != "0.9.1" && ~s(spec_version "#{spec_version}"),
        Enum.map(Map.get(spec, "contexts", []), &context_block(&1, allowlist)),
        Enum.map(Map.get(spec, "queries", []), &query_block/1),
        Enum.map(Map.get(spec, "components", []), &component_block(&1, allowlist)),
        Enum.map(Map.get(spec, "fields", []), &field_block/1),
        Enum.map(Map.get(spec, "actions", []), &action_block/1)
      ]
      |> List.flatten()
      |> Enum.filter(& &1)

    source = """
    defmodule #{inspect(module)} do
      @moduledoc #{inspect(moduledoc(spec))}

      # Generated by AshA2ui.Dynamic.to_dsl_source/2 from a validated
      # agent-composed surface spec. Provenance:
      #   spec fingerprint: #{Serializer.fingerprint(spec)}
      #   spec format:      #{Serializer.spec_format()}
      #   resource:         #{inspect(resource)}
      use AshA2ui.Standalone

      a2ui do
        #{Enum.join(body, "\n")}
      end
    end
    """

    IO.iodata_to_binary([
      Code.format_string!(source, locals_without_parens: locals_without_parens()),
      "\n"
    ])
  end

  defp moduledoc(spec) do
    title = Map.get(spec, "title")

    [title, "Promoted from an agent-composed `AshA2ui.Dynamic` surface spec."]
    |> Enum.filter(& &1)
    |> Enum.join("\n\n")
  end

  defp default_surface_id(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end

  # --- entity blocks ----------------------------------------------------------------

  defp component_block(entry, allowlist) do
    args =
      case Map.get(entry, "name") do
        nil -> ":#{Map.fetch!(entry, "kind")}"
        name -> ":#{Map.fetch!(entry, "kind")}, :#{name}"
      end

    nested =
      [
        entry |> Map.get("row_layout") |> row_layout_block(),
        entry |> Map.get("columns", []) |> Enum.map(&column_block/1),
        entry |> Map.get("groups", []) |> Enum.map(&group_block/1),
        entry |> Map.get("nested_forms", []) |> Enum.map(&nested_form_block/1),
        entry |> Map.get("sections") |> sections_block(allowlist),
        entry |> Map.get("primary_action") |> primary_action_block()
      ]
      |> List.flatten()
      |> Enum.filter(& &1)

    block(
      "component #{args}",
      related_resource_line(entry, allowlist) ++ option_lines(entry, @component_options) ++ nested
    )
  end

  # A related table's resource, emitted as a module literal resolved through
  # the allowlist like a context's resource.
  defp related_resource_line(entry, allowlist) do
    case Map.fetch(entry, "resource") do
      {:ok, name} -> ["resource #{inspect(Map.fetch!(allowlist, name))}"]
      :error -> []
    end
  end

  defp row_layout_block(nil), do: nil

  defp row_layout_block(entry) do
    block("row_layout", option_lines(entry, @row_layout_options))
  end

  defp column_block(entry) do
    block(~s(column :#{Map.fetch!(entry, "name")}), option_lines(entry, @column_options))
  end

  defp primary_action_block(nil), do: nil

  defp primary_action_block(entry) do
    block("primary_action", option_lines(entry, @primary_action_options))
  end

  defp group_block(entry) do
    block(~s(group :#{Map.fetch!(entry, "name")}), option_lines(entry, @group_options))
  end

  defp nested_form_block(entry) do
    block(
      ~s(nested_form :#{Map.fetch!(entry, "name")}),
      option_lines(entry, @nested_form_options)
    )
  end

  # The section source is emitted as a module literal, resolved through the
  # allowlist like a context's resource.
  defp sections_block(nil, _allowlist), do: nil

  defp sections_block(entry, allowlist) do
    source_line =
      case Map.fetch(entry, "source") do
        {:ok, name} -> ["source #{inspect(Map.fetch!(allowlist, name))}"]
        # Source-less: a board's lanes are scope_by's values.
        :error -> []
      end

    block("sections", source_line ++ option_lines(entry, @section_options))
  end

  defp query_block(entry) do
    presets = entry |> Map.get("presets", []) |> Enum.map(&preset_block/1)

    block(
      "query :#{Map.fetch!(entry, "name")}",
      option_lines(entry, @query_options) ++ presets
    )
  end

  defp preset_block(entry) do
    block(~s(preset :#{Map.fetch!(entry, "name")}), option_lines(entry, @preset_options))
  end

  defp field_block(entry) do
    block("field :#{Map.fetch!(entry, "name")}", option_lines(entry, @field_options))
  end

  defp action_block(entry) do
    block("action :#{Map.fetch!(entry, "name")}", option_lines(entry, @action_options))
  end

  defp context_block(entry, allowlist) do
    resource = Map.fetch!(allowlist, Map.fetch!(entry, "resource"))

    block(
      "context :#{Map.fetch!(entry, "name")}",
      ["resource #{inspect(resource)}" | option_lines(entry, @context_options)]
    )
  end

  defp block(header, []), do: header

  defp block(header, lines) do
    "#{header} do\n#{Enum.join(lines, "\n")}\nend"
  end

  defp option_lines(entry, options) do
    for {option, shape} <- options,
        {:ok, value} <- [Map.fetch(entry, to_string(option))] do
      "#{option} #{render(shape, value)}"
    end
  end

  # --- value rendering (the parser's shape conversions, inverted) --------------------

  defp render(:name, value), do: ":#{value}"

  defp render(:name_list, values) do
    "[#{Enum.map_join(values, ", ", &":#{&1}")}]"
  end

  # Keyword-shaped JSON objects are emitted sorted by key — exactly the
  # order AshA2ui.Dynamic.Parser builds them in, so a promoted module
  # resolves to byte-identical entities.
  defp render(:name_keyword, object), do: keyword(object, &render(:name, &1))
  defp render(:raw_keyword, object), do: keyword(object, &render(:raw, &1))
  defp render(:string_keyword, object), do: keyword(object, &render(:raw, &1))

  defp render(:search_fields, values) do
    entries =
      Enum.map_join(values, ", ", fn
        path when is_list(path) -> render(:name_list, path)
        name -> ":#{name}"
      end)

    "[#{entries}]"
  end

  defp render(:default_sort, entries) do
    Enum.map_join(entries, ", ", fn entry ->
      "#{Map.fetch!(entry, "field")}: :#{Map.get(entry, "direction", "asc")}"
    end)
  end

  defp render(:raw, value), do: inspect(value)

  # Enumerated values: identifier-shaped ones as atom literals (how the DSL
  # declares them), anything else as a string; no atom is created here.
  defp render(:value_list, values) do
    "[#{Enum.map_join(values, ", ", &value_literal/1)}]"
  end

  # A field's link: a relationship name, or the {"surface", "path"} object
  # back to the DSL's {surface_key, id_path} tuple (surface as a string).
  defp render(:link, name) when is_binary(name), do: render(:name, name)

  defp render(:link, %{"surface" => surface, "path" => path}),
    do: "{#{inspect(surface)}, #{render(:name_list, path)}}"

  # The spec's {"mfa": "Mod.fun/arity", "args": [...]} back to the DSL's
  # tuple literal — the delegate exists (the parser validated it during the
  # resolve that preceded promotion), so rendering the function name as an
  # atom literal is safe.
  defp render(:via, %{"mfa" => mfa, "args" => args}) do
    {:ok, {module, function, _arity}} = Parser.split_mfa_string(mfa)

    # sobelow_skip ["DOS.StringToAtom"]
    "{#{inspect(String.to_atom("Elixir." <> module))}, :#{function}, #{inspect(args)}}"
  end

  defp keyword(object, render_value) do
    object
    |> Enum.sort()
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{render_value.(value)}" end)
  end

  # --- formatter configuration -------------------------------------------------------

  @doc """
  The `locals_without_parens` of the `a2ui` DSL, derived from the extension's
  own section/entity definitions — the same list `mix spark.formatter`
  exports in `.formatter.exs`. Generated sources are formatted with it so
  they are a fixed point of a host project's `mix format`.
  """
  @spec locals_without_parens() :: [{atom, pos_integer}]
  def locals_without_parens do
    [section] = AshA2ui.sections()

    schema_locals(section.schema)
    |> Enum.concat(entity_locals(section.entities))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp entity_locals(entities) do
    Enum.flat_map(entities, fn entity ->
      nested = entity.entities |> Keyword.values() |> List.flatten()

      builder_locals(entity) ++ schema_locals(entity.schema) ++ entity_locals(nested)
    end)
  end

  # An entity builder is callable with its required args, each optional arg,
  # and optionally a trailing do block: `component :table`, `component
  # :table do`, `component :table, :as do`, ...
  defp builder_locals(entity) do
    required = Enum.count(entity.args, &is_atom/1)
    total = length(entity.args)

    for args <- required..total, block <- 0..1, args + block > 0 do
      {entity.name, args + block}
    end
  end

  defp schema_locals(schema), do: Enum.map(Keyword.keys(schema), &{&1, 1})

  defp value_literal(value) do
    if value =~ ~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/, do: ":#{value}", else: inspect(value)
  end
end
