defmodule AshA2ui.Dynamic.Importer do
  @moduledoc """
  Declared surface → dynamic surface spec: the composer's **Import**.

  Reads the `a2ui` section of a resource or `AshA2ui.Standalone` UI module
  through `AshA2ui.Info` and emits the equivalent `AshA2ui.Dynamic` spec
  map — the same vocabulary `AshA2ui.Dynamic.resolve/2` parses, so an
  imported spec resolves to a surface that renders like the declared one.

  Import is honest about the spec's boundaries: a declared feature with no
  spec vocabulary (inline editing, file export, plus the section options
  that live outside the spec — `surface_id`, `record_label`,
  `spec_version`) becomes a **visible rejection** carrying the reason,
  never a silent drop. The composer shows rejections in the inspector; the
  spec itself contains exactly what the dynamic stack can honor.

  The inverse direction (spec → DSL source) is
  `AshA2ui.Dynamic.to_dsl_source/2`.
  """

  defmodule Rejection do
    @moduledoc """
    One declared feature the spec vocabulary cannot represent.

    * `path` — where the feature was declared (e.g. `"components[0].sections"`).
    * `feature` — the DSL option or entity that was dropped.
    * `reason` — why the spec vocabulary cannot carry it (and, where one
      exists, what to use instead).
    """

    @derive {Jason.Encoder, only: [:path, :feature, :reason]}
    defstruct [:path, :feature, :reason]

    @type t :: %__MODULE__{path: String.t(), feature: String.t(), reason: String.t()}

    @doc false
    def new(path, feature, reason), do: %__MODULE__{path: path, feature: feature, reason: reason}

    @doc """
    One `"path (feature): reason"` line per rejection — the plain-text
    rendering the inspector shows.
    """
    @spec messages([t()]) :: [String.t()]
    def messages(rejections) do
      Enum.map(rejections, fn %__MODULE__{path: path, feature: feature, reason: reason} ->
        "#{path} (#{feature}): #{reason}"
      end)
    end
  end

  alias AshA2ui.Component
  alias Spark.Dsl.Extension

  @doc """
  Imports `resource_or_ui_module`'s declared `a2ui` section into a spec.

  Returns `{:ok, spec, rejections}` — the spec plus every feature that could
  not be represented — or `{:error, rejection}` when the module has no `a2ui`
  section at all (there is nothing to import, not merely something to drop).
  """
  @spec import(module) :: {:ok, map, [Rejection.t()]} | {:error, Rejection.t()}
  def import(resource_or_ui_module) do
    loaded? = Code.ensure_loaded?(resource_or_ui_module)

    # `spark_dsl_config/0` is the callback every Spark DSL module carries;
    # guarding on it keeps `Spark.extensions/1` off plain modules.
    surface? =
      loaded? and function_exported?(resource_or_ui_module, :spark_dsl_config, 0) and
        AshA2ui in Spark.extensions(resource_or_ui_module)

    if surface? do
      {spec, rejections} = build_spec(resource_or_ui_module)
      {:ok, spec, rejections}
    else
      {:error,
       Rejection.new(
         "",
         "a2ui",
         "#{inspect(resource_or_ui_module)} declares no AshA2ui surface — nothing to import"
       )}
    end
  end

  # --- spec assembly -----------------------------------------------------------------

  defp build_spec(module) do
    {components, component_rejections} = component_specs(module)
    {queries, query_rejections} = query_specs(module)
    fields = field_specs(module)
    {actions, action_rejections} = action_specs(module)
    {contexts, context_rejections} = context_specs(module)

    resource = AshA2ui.Info.resource!(module)

    spec =
      %{"resource" => short_name(resource)}
      |> put_title(module)
      |> put_entities("components", components)
      |> put_entities("queries", queries)
      |> put_entities("fields", fields)
      |> put_entities("actions", actions)
      |> put_entities("contexts", contexts)

    rejections =
      section_rejections(module) ++
        component_rejections ++ query_rejections ++ action_rejections ++ context_rejections

    {spec, rejections}
  end

  # Section options: the spec carries only the title. Everything else that
  # shapes a declared surface lives outside the spec vocabulary — named
  # visibly, with where it belongs instead.
  defp put_title(spec, module) do
    case Extension.get_opt(module, [:a2ui], :title, nil) do
      title when is_binary(title) -> Map.put(spec, "title", title)
      _ -> spec
    end
  end

  defp section_rejections(module) do
    # Section options live outside the spec vocabulary. `spec_version` has a
    # schema default ("0.9.1"), so only a value that differs from the default
    # is a real declaration worth rejecting — the default is silence.
    notes = [
      {:surface_id, Extension.get_opt(module, [:a2ui], :surface_id, nil),
       "surface ids are resolve/deploy metadata — pass it as the resolve :surface_id option"},
      {:record_label, Extension.get_opt(module, [:a2ui], :record_label, nil),
       "record labels drive the v2 task labels and have no spec key — keep them in the promoted module"},
      {:spec_version, Extension.get_opt(module, [:a2ui], :spec_version, "0.9.1"),
       "the wire version is a resolve option (:spec_version), not part of the spec"}
    ]

    for {option, value, note} <- notes,
        not is_nil(value),
        {option, value} != {:spec_version, "0.9.1"} do
      Rejection.new(
        "a2ui.#{option}",
        to_string(option),
        "declared #{inspect(value)} — #{note}"
      )
    end
  end

  defp put_entities(spec, _key, []), do: spec
  defp put_entities(spec, key, entities), do: Map.put(spec, key, entities)

  # --- components --------------------------------------------------------------------

  defp component_specs(module) do
    AshA2ui.Info.components(module)
    |> Enum.with_index()
    |> Enum.flat_map_reduce([], fn {component, index}, acc ->
      path = "components[#{index}]"

      if component.name in [:table, :form, :detail] do
        {spec, rejections} = component_entry(component, path)
        {[spec], acc ++ rejections}
      else
        # The spec's kind vocabulary is table/form/detail; anything else the
        # DSL accepts (reports) stays in the promoted module — visibly.
        {[],
         acc ++
           [
             Rejection.new(
               path,
               to_string(component.name),
               "spec component kinds are table/form/detail only — keep this one in the promoted module"
             )
           ]}
      end
    end)
  end

  defp component_entry(%Component{} = component, path) do
    spec =
      %{"kind" => to_string(component.name)}
      |> put_component_name(component)
      |> put_list("fields", component.fields)
      |> put_opt("read_action", component.read_action)
      |> put_opt("create_action", component.create_action)
      |> put_opt("update_action", component.update_action)
      |> put_list("row_actions", component.row_actions)
      |> put_opt("query", component.query)
      |> put_keyword("context_filter", component.context_filter, :name)
      |> put_list("require_context", component.require_context)
      |> put_opt("select_context", component.select_context)
      |> put_opt("context", component.context)
      |> put_row_layout(component.row_layout)
      |> put_groups(component.groups)
      |> put_nested_forms(component.nested_forms)
      |> put_sections(component.sections)

    {spec, component_rejections(component, path)}
  end

  # Declared component features with no spec vocabulary: rejected with the
  # reason, never dropped.
  defp component_rejections(component, path) do
    for {feature, note} <- [
          {:editable, "inline cell editing has no spec vocabulary"},
          {:export, "file export has no spec vocabulary — keep it in the declared surface"},
          {:action, "generic-action tables have no spec vocabulary"},
          {:params, "generic-action tables have no spec vocabulary"},
          {:bulk_actions,
           "bulk actions have no spec vocabulary — keep them in the declared surface"}
        ],
        value = Map.get(component, feature),
        value not in [nil, false, []] do
      Rejection.new(
        "#{path}.#{feature}",
        to_string(feature),
        "declared on this component — #{note}"
      )
    end
  end

  # Only table/detail components may carry a distinguishing name — the form
  # is unique by its kind, and the resolver rejects a named :form. `as:` is
  # the DSL's distinguishing name; the kind stands in when it is absent.
  defp put_component_name(spec, %Component{name: kind} = component)
       when kind in [:table, :detail] do
    Map.put(spec, "name", to_string(component.as || kind))
  end

  defp put_component_name(spec, _form), do: spec

  defp put_row_layout(spec, nil), do: spec

  defp put_row_layout(spec, layout) do
    row_layout =
      %{}
      |> put_opt("title", layout.title)
      |> put_opt("badge", layout.badge)
      |> put_keyword("badge_text", layout.badge_text, :raw)
      |> put_list("meta", layout.meta)
      |> put_value("columns", layout.columns)

    Map.put(spec, "row_layout", row_layout)
  end

  defp put_groups(spec, []), do: spec

  defp put_groups(spec, groups) do
    entries =
      Enum.map(groups, fn group ->
        %{"name" => to_string(group.name)}
        |> put_value("label", group.label)
        |> put_value("columns", group.columns)
        |> put_list("fields", group.fields)
      end)

    Map.put(spec, "groups", entries)
  end

  # Nested relationship sub-forms: `name` is the managed action argument;
  # the other keys mirror the field entity's option vocabulary. Defaults
  # (option_limit) stay unspoken — silence is the default, like the DSL.
  defp put_nested_forms(spec, []), do: spec

  defp put_nested_forms(spec, nested_forms) do
    entries =
      Enum.map(nested_forms, fn nested ->
        %{"name" => to_string(nested.name)}
        |> put_value("label", nested.label)
        |> put_list("fields", nested.fields)
        |> put_opt("option_label", nested.option_label)
        |> put_opt("option_value", nested.option_value)
        |> put_opt("option_sort", nested.option_sort)
        |> put_value("option_limit", if(nested.option_limit == 100, do: nil))
        |> put_list("option_search", nested.option_search)
      end)

    Map.put(spec, "nested_forms", entries)
  end

  # Sectioned tables carry their dynamic-section config verbatim — the
  # faithful representation (the runtime expansion yields a dynamic number
  # of tables, so a per-section unrolling cannot round-trip). The source is
  # named by its allowlist name; defaults (limit) stay unspoken.
  defp put_sections(spec, nil), do: spec

  defp put_sections(spec, sections) do
    section =
      %{"source" => short_name(sections.source), "scope_by" => to_string(sections.scope_by)}
      |> put_opt("label", sections.label)
      |> put_opt("value", sections.value)
      |> put_opt("read_action", sections.read_action)
      |> put_opt("sort", sections.sort)
      |> put_value("limit", if(sections.limit == 50, do: nil))

    Map.put(spec, "sections", section)
  end

  # --- queries -----------------------------------------------------------------------

  defp query_specs(module) do
    specs =
      Enum.map(AshA2ui.Info.queries(module), fn query ->
        %{"name" => to_string(query.name)}
        |> put_list("search_fields", query.search_fields)
        |> put_list("sortable", query.sortable)
        |> put_list("filters", query.filters)
        |> put_list("range_filters", query.range_filters)
        |> put_default_sort(query.default_sort)
        |> put_opt("default_preset", query.default_preset)
        |> put_value("page_size", query.page_size)
        |> put_value("max_page_size", query.max_page_size)
        |> put_presets(query.presets)
      end)

    {specs, []}
  end

  defp put_presets(spec, []), do: spec

  defp put_presets(spec, presets) do
    entries =
      Enum.map(presets, fn preset ->
        %{"name" => to_string(preset.name)}
        |> put_keyword("filter", preset.filter, :raw)
        |> put_opt("read_action", preset.read_action)
      end)

    Map.put(spec, "presets", entries)
  end

  # --- fields ------------------------------------------------------------------------

  defp field_specs(module) do
    Enum.map(AshA2ui.Info.fields(module), fn field ->
      %{"name" => to_string(field.name)}
      |> put_value("label", field.label)
      |> put_opt("widget", field.widget)
      |> put_opt("format", field.format)
      |> put_value("order", field.order)
      |> put_value("hidden", field.hidden)
      |> put_list("source", field.source)
      |> put_opt("relationship", field.relationship)
      |> put_opt("option_label", field.option_label)
      |> put_opt("option_value", field.option_value)
      |> put_opt("option_sort", field.option_sort)
      |> put_value("option_limit", field.option_limit)
      |> put_list("option_search", field.option_search)
    end)
  end

  # --- actions -----------------------------------------------------------------------

  defp action_specs(module) do
    resource = AshA2ui.Info.resource!(module)
    components = AshA2ui.Info.components(module)

    # The actions a spec-declared component can reach: row actions, the
    # form's create/update (including primary defaults). An `action` entity
    # reachable ONLY through a rejected feature (inline editing commits
    # through its update_action) would make the spec unresolvable — it is
    # rejected visibly alongside the feature that carried it.
    reachable = MapSet.new(reachable_from_spec(components, resource))

    AshA2ui.Info.action_settings(module)
    |> Enum.with_index()
    |> Enum.flat_map_reduce([], fn {action, index}, acc ->
      path = "actions[#{index}]"

      if MapSet.member?(reachable, action.name) do
        spec =
          %{"name" => to_string(action.name)}
          |> put_list("refreshes", action.refreshes)
          |> put_list("prompt_fields", action.prompt_fields)
          |> put_value("prompt_title", action.prompt_title)
          |> put_keyword("visible_when", action.visible_when, :raw)
          |> put_via(Map.get(action, :via))

        {[spec], acc}
      else
        # A compile-verified declared surface only carries reachable actions,
        # so this can only be an action whose reachability rode on a rejected
        # feature: the editable block's update_action.
        {[],
         acc ++
           [
             Rejection.new(
               path,
               to_string(action.name),
               "action #{inspect(action.name)} is only reachable through its component's " <>
                 "editable block (inline editing has no spec vocabulary) — the action's " <>
                 "metadata is rejected with it, or the spec would not resolve"
             )
           ]}
      end
    end)
  end

  # The action names a spec-declared component can reach: every component's
  # row actions and typed actions, plus the primary create/update the form
  # falls back to.
  defp reachable_from_spec(components, resource) do
    Enum.flat_map(components, fn component ->
      component.row_actions ++
        Enum.reject([component.create_action, component.update_action], &is_nil/1)
    end)
    |> Enum.concat(primary_action_names(resource))
    |> Enum.uniq()
  end

  defp primary_action_names(resource) do
    [:create, :update]
    |> Enum.map(fn type ->
      case Ash.Resource.Info.primary_action(resource, type) do
        %{name: name} -> name
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # `via` re-points a row action at a host-provided MFA. The spec carries it
  # as "Mod.fun/arity" (the delegate's full arity — the handler prepends the
  # dispatch context to the extra args) plus the args array. Resolving the
  # spec requires the module in the host's :via_allowlist, so a stored spec
  # never silently re-points an action at code the host has not sanctioned.
  defp put_via(spec, nil), do: spec

  defp put_via(spec, {module, function, args}) do
    arity = 1 + length(args)

    Map.put(spec, "via", %{
      "mfa" => "#{inspect(module)}.#{function}/#{arity}",
      "args" => args
    })
  end

  # --- contexts ----------------------------------------------------------------------

  defp context_specs(module) do
    {Enum.map(AshA2ui.Info.contexts(module), fn context ->
       %{"name" => to_string(context.name), "resource" => short_name(context.resource)}
       |> put_value("label", context.label)
       |> put_opt("option_label", context.option_label)
       |> put_opt("option_value", context.option_value)
       |> put_opt("option_sort", context.option_sort)
       |> put_value("option_limit", context.option_limit)
       |> put_list("option_search", context.option_search)
       |> put_opt("depends_on", context.depends_on)
       |> put_list("depends_on_path", context.depends_on_path)
       |> put_value("auto_select_single", context.auto_select_single)
       |> put_value("picker", context.picker)
     end), []}
  end

  # --- value conversion --------------------------------------------------------------

  defp short_name(module), do: module |> Module.split() |> List.last()

  defp put_opt(spec, _key, nil), do: spec
  defp put_opt(spec, key, name) when is_atom(name), do: Map.put(spec, key, to_string(name))
  defp put_opt(spec, key, name) when is_binary(name), do: Map.put(spec, key, name)

  defp put_value(spec, _key, nil), do: spec
  defp put_value(spec, key, value), do: Map.put(spec, key, value)

  defp put_list(spec, _key, nil), do: spec
  defp put_list(spec, _key, []), do: spec
  defp put_list(spec, key, names), do: Map.put(spec, key, Enum.map(names, &entry_name/1))

  defp entry_name(name) when is_atom(name), do: to_string(name)
  defp entry_name(path) when is_list(path), do: Enum.map(path, &to_string/1)
  defp entry_name(name) when is_binary(name), do: name

  # DSL keyword shapes → JSON objects with string keys (the parser's
  # `:raw_keyword` / `:string_keyword` / `:name_keyword` input shape).
  defp put_keyword(spec, _key, nil, _mode), do: spec
  defp put_keyword(spec, _key, [], _mode), do: spec

  defp put_keyword(spec, key, keyword, mode) when is_list(keyword) do
    object =
      Map.new(keyword, fn {keyword_key, value} ->
        value =
          case mode do
            :name -> entry_name(value)
            :raw -> value
          end

        {keyword_key(keyword_key), value}
      end)

    Map.put(spec, key, object)
  end

  defp keyword_key(key) when is_atom(key), do: to_string(key)
  defp keyword_key(key) when is_binary(key), do: key

  defp put_default_sort(spec, []), do: spec

  defp put_default_sort(spec, sort) when is_list(sort) do
    entries =
      Enum.map(sort, fn {field, direction} ->
        %{"field" => to_string(field), "direction" => to_string(direction)}
      end)

    Map.put(spec, "default_sort", entries)
  end
end
