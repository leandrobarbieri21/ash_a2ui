defmodule AshA2ui.Dynamic.Parser do
  @moduledoc """
  Turns a JSON-decoded surface spec (see `AshA2ui.Dynamic`) into the same
  entity structs the `a2ui` DSL compiles to.

  Every entity is built through `Spark.Dsl.Entity.build/5` with the
  extension's own entity definitions, so Spark's option schemas (types,
  `one_of` values, required options, defaults) apply to dynamic specs exactly
  as they do to DSL blocks. The parser's own job is shape conversion —
  JSON strings/objects/arrays to the atoms, keyword lists, and tuples the
  schemas expect — plus the dynamic-only checks that need spec-level
  context (identifier format, widget/format/tone vocabulary, the link
  shape, resource-allowlist lookups for contexts, related tables and
  section sources).

  Identifier atoms (component/query/group/preset/context names and field
  references) are created from validated spec strings (`^[a-zA-Z]\\w*$`, at
  most 64 bytes). Creation is bounded by the spec limits enforced by
  `AshA2ui.Dynamic.spec_schema/1` and re-checked here; misspelled *field*
  references still become atoms, on purpose — the shared verifiers then
  reject them with the compile-time messages that list what is available,
  which is what lets an LLM self-correct.
  """

  alias AshA2ui.Dynamic.Error
  alias Spark.Dsl.Entity
  alias Spark.Options.ValidationError

  @name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/
  @max_name_bytes 64
  @max_list_entries 64

  # Every widget the encoder renders / format it applies. Arbitrary atoms
  # would silently fall back to TextField — reject them loudly instead.
  @widgets ~w(text_field check_box choice_picker date_time_input)
  @formats ~w(date)

  @top_level_keys ~w(resource title components queries fields actions contexts)

  @doc """
  Parses `spec` (a JSON-decoded, string-keyed map) into the `a2ui` section's
  entity structs, in the section's canonical order (contexts, queries,
  components, fields, actions).

  `allowlist` is the `%{"Name" => module}` resource allowlist (used to
  resolve context resources). Returns `{:ok, entities}` or
  `{:error, [%AshA2ui.Dynamic.Error{}]}` with every problem found.
  """
  @spec parse(map, %{String.t() => module}) ::
          {:ok, [struct]} | {:error, [Error.t()]}
  def parse(spec, allowlist) when is_map(spec) do
    with :ok <- check_unknown_keys(spec) do
      collect_entities(spec, allowlist)
    end
  end

  def parse(_spec, _allowlist) do
    {:error, [Error.new("", "the surface spec must be a JSON object")]}
  end

  defp collect_entities(spec, allowlist) do
    results = [
      parse_entities(spec, "contexts", &parse_context(&1, &2, allowlist)),
      parse_entities(spec, "queries", &parse_query/2),
      parse_entities(spec, "components", &parse_component(&1, &2, allowlist)),
      parse_entities(spec, "fields", &parse_field/2),
      parse_entities(spec, "actions", &parse_action/2)
    ]

    case Enum.flat_map(results, fn {_entities, errors} -> errors end) do
      [] -> {:ok, Enum.flat_map(results, fn {entities, _errors} -> entities end)}
      errors -> {:error, errors}
    end
  end

  # The spec linter: unknown top-level keys are a visible validation error —
  # one per key, sorted for deterministic tool loops — never silently
  # ignored. An LLM that mistyped several keys gets every correction in a
  # single round trip, matching the "every verifier runs" philosophy of
  # resolve/2's validation pipeline.
  defp check_unknown_keys(spec) do
    spec
    |> Map.keys()
    |> Enum.reject(&(&1 in @top_level_keys))
    |> Enum.sort_by(&to_string/1)
    |> case do
      [] ->
        :ok

      unknown ->
        {:error,
         Enum.map(unknown, fn key ->
           Error.new(
             to_string(key),
             "unknown spec key #{inspect(key)} — the spec supports: " <>
               Enum.join(@top_level_keys, ", ")
           )
         end)}
    end
  end

  defp parse_entities(spec, key, parser) do
    case Map.get(spec, key, []) do
      entries when is_list(entries) and length(entries) <= @max_list_entries ->
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} -> parser.(entry, "#{key}[#{index}]") end)
        |> Enum.reduce({[], []}, fn
          {:ok, entity}, {entities, errors} -> {entities ++ [entity], errors}
          {:error, new_errors}, {entities, errors} -> {entities, errors ++ new_errors}
        end)

      entries when is_list(entries) ->
        {[], [Error.new(key, "at most #{@max_list_entries} #{key} are supported")]}

      _not_a_list ->
        {[], [Error.new(key, "#{inspect(key)} must be an array")]}
    end
  end

  # --- components -------------------------------------------------------------

  @component_keys %{
    "kind" => :name,
    "name" => :as,
    "fields" => :fields,
    "read_action" => :read_action,
    "create_action" => :create_action,
    "update_action" => :update_action,
    "row_actions" => :row_actions,
    "query" => :query,
    "context_filter" => :context_filter,
    "require_context" => :require_context,
    "select_context" => :select_context,
    "context" => :context,
    "display" => :display,
    "date_field" => :date_field,
    "end_date_field" => :end_date_field,
    "granularity" => :granularity,
    "granularities" => :granularities
  }

  # Closed vocabularies, string -> atom by lookup (never created from
  # input).
  @displays %{"list" => :list, "board" => :board, "calendar" => :calendar}
  @granularities Map.new(AshA2ui.Calendar.granularities(), &{Atom.to_string(&1), &1})

  @component_nested ~w(row_layout columns groups nested_forms sections)

  defp parse_component(entry, path, allowlist) when is_map(entry) do
    with :ok <- require_kind(entry, path),
         :ok <- board_without_source(entry, path),
         {:ok, resource} <- component_resource(entry, path, allowlist),
         {:ok, opts} <-
           convert_options(
             Map.delete(entry, "resource"),
             @component_keys,
             ["resource" | @component_nested],
             path
           ),
         {:ok, nested} <- parse_component_nested(entry, path, allowlist) do
      opts = if resource, do: opts ++ [resource: resource], else: opts
      build_entity(:component, entity_def(:component), opts, nested, path)
    end
  end

  defp parse_component(_entry, path, _allowlist),
    do: {:error, [Error.new(path, "each component must be a JSON object")]}

  # A composed board's lanes are the enumerated values of `scope_by`:
  # resource-sourced lanes are declared in the DSL only.
  defp board_without_source(%{"display" => "board", "sections" => %{"source" => _}}, path) do
    {:error,
     [
       Error.new(
         "#{path}.sections.source",
         ~s(a composed board's lanes are the values of scope_by — drop "source" ) <>
           "(resource-sourced lanes are declared in the DSL only)"
       )
     ]}
  end

  defp board_without_source(_entry, _path), do: :ok

  # A related table's `resource` (a :table reading another resource, scoped
  # by a context): named like a context resource and resolved through the
  # allowlist, so a spec can only read resources the host offers. Whether
  # the component may carry one (tables only, read-only, its fields and
  # context_filter keys on that resource) is the shared verifiers' call.
  defp component_resource(entry, path, allowlist) do
    case Map.fetch(entry, "resource") do
      :error -> {:ok, nil}
      {:ok, name} -> allowlisted_resource(name, "#{path}.resource", allowlist, "resource")
    end
  end

  defp allowlisted_resource(name, path, allowlist, _option) when is_binary(name) do
    case Map.fetch(allowlist, name) do
      {:ok, resource} ->
        {:ok, resource}

      :error ->
        {:error,
         [
           Error.new(
             path,
             "resource #{inspect(name)} is not available to dynamic surfaces — " <>
               "use one of: #{Enum.join(Enum.sort(Map.keys(allowlist)), ", ")}"
           )
         ]}
    end
  end

  defp allowlisted_resource(_name, path, _allowlist, option),
    do: {:error, [Error.new(path, ~s(#{option} must name an allowlisted resource string))]}

  defp require_kind(entry, path) do
    if Map.has_key?(entry, "kind") do
      :ok
    else
      {:error,
       [
         Error.new(
           "#{path}.kind",
           ~s(each component must declare a "kind": "table", "form" or "detail")
         )
       ]}
    end
  end

  defp parse_component_nested(entry, path, allowlist) do
    component_def = entity_def(:component)
    [row_layout_def] = component_def.entities[:row_layout]
    [column_def] = component_def.entities[:columns]
    [group_def] = component_def.entities[:groups]
    [nested_form_def] = component_def.entities[:nested_forms]
    [sections_def] = component_def.entities[:sections]

    with {:ok, row_layout} <-
           parse_row_layout(Map.get(entry, "row_layout"), row_layout_def, path),
         {:ok, columns} <- parse_columns(Map.get(entry, "columns"), column_def, path),
         {:ok, groups} <- parse_groups(Map.get(entry, "groups"), group_def, path),
         {:ok, nested_forms} <-
           parse_nested_forms(Map.get(entry, "nested_forms"), nested_form_def, path),
         {:ok, sections} <-
           parse_sections(Map.get(entry, "sections"), sections_def, path, allowlist) do
      {:ok,
       [
         row_layout: row_layout,
         columns: columns,
         groups: groups,
         nested_forms: nested_forms,
         sections: sections
       ]}
    end
  end

  @row_layout_keys %{
    "title" => :title,
    "badge" => :badge,
    "badge_text" => :badge_text,
    "badge_tones" => :badge_tones,
    "meta" => :meta,
    "columns" => :columns
  }

  # The badge tone vocabulary, string -> atom over AshA2ui.RowLayout.tones/0:
  # a tone is looked up, never created from input.
  @tones Map.new(AshA2ui.RowLayout.tones(), &{Atom.to_string(&1), &1})

  defp parse_row_layout(nil, _def, _path), do: {:ok, []}

  defp parse_row_layout(entry, row_layout_def, path) when is_map(entry) do
    path = "#{path}.row_layout"

    with {:ok, opts} <- convert_options(entry, @row_layout_keys, [], path),
         {:ok, layout} <- build_entity(:row_layout, row_layout_def, opts, [], path) do
      {:ok, [layout]}
    end
  end

  defp parse_row_layout(_entry, _def, path),
    do: {:error, [Error.new("#{path}.row_layout", "row_layout must be a JSON object")]}

  @column_keys %{
    "name" => :name,
    "subtitle" => :subtitle,
    "icon" => :icon,
    "icon_names" => :icon_names,
    "icon_tones" => :icon_tones,
    "icon_labels" => :icon_labels,
    "more" => :more,
    "detail" => :detail,
    "detail_date" => :detail_date,
    "detail_text" => :detail_text,
    "detail_icon_names" => :detail_icon_names,
    "detail_icon_tones" => :detail_icon_tones
  }

  # The cell icon vocabulary, string -> atom over AshA2ui.Column.icons/0:
  # an icon is looked up, never created from input.
  @cell_icons Map.new(AshA2ui.Column.icons(), &{Atom.to_string(&1), &1})

  defp parse_columns(nil, _def, _path), do: {:ok, []}

  defp parse_columns(entries, column_def, path)
       when is_list(entries) and length(entries) <= @max_list_entries do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      column_path = "#{path}.columns[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(column_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @column_keys, [], column_path) do
          build_entity(:column, column_def, opts, [], column_path)
        end

      case result do
        {:ok, column} -> {:cont, {:ok, acc ++ [column]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_columns(_entries, _def, path),
    do:
      {:error,
       [
         Error.new(
           "#{path}.columns",
           "columns must be an array of at most #{@max_list_entries} objects"
         )
       ]}

  @group_keys %{"name" => :name, "label" => :label, "columns" => :columns, "fields" => :fields}

  defp parse_groups(nil, _def, _path), do: {:ok, []}

  defp parse_groups(entries, group_def, path) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      group_path = "#{path}.groups[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(group_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @group_keys, [], group_path) do
          build_entity(:group, group_def, opts, [], group_path)
        end

      case result do
        {:ok, group} -> {:cont, {:ok, acc ++ [group]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_groups(_entries, _def, path),
    do: {:error, [Error.new("#{path}.groups", "groups must be an array")]}

  @nested_form_keys %{
    "name" => :name,
    "label" => :label,
    "fields" => :fields,
    "option_label" => :option_label,
    "option_value" => :option_value,
    "option_sort" => :option_sort,
    "option_limit" => :option_limit,
    "option_search" => :option_search
  }

  # Nested relationship sub-forms, named by the action argument a
  # manage_relationship change consumes on the form's actions. All checks
  # that need resource knowledge (the manage_relationship change, the
  # interaction mode, option attributes) stay with VerifyNestedForms, which
  # runs over the resolved entities exactly as it does at compile time.
  defp parse_nested_forms(nil, _def, _path), do: {:ok, []}

  defp parse_nested_forms(entries, nested_form_def, path) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      nested_path = "#{path}.nested_forms[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(nested_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @nested_form_keys, [], nested_path) do
          build_entity(:nested_form, nested_form_def, opts, [], nested_path)
        end

      case result do
        {:ok, nested_form} -> {:cont, {:ok, acc ++ [nested_form]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_nested_forms(_entries, _def, path),
    do: {:error, [Error.new("#{path}.nested_forms", "nested_forms must be an array")]}

  @section_keys %{
    "scope_by" => :scope_by,
    "value" => :value,
    "read_action" => :read_action,
    "sort" => :sort,
    "limit" => :limit
  }

  # Sectioned tables: the dynamic-section config that expands a `:table`
  # template into one concrete table per record of its `source` at render
  # time. The source is named like a context resource — resolved through the
  # allowlist, so a spec can only enumerate sections of resources the host
  # offers. ("label" is handled like "resource" below: it names an attribute
  # here, while field/group labels are strings.)
  defp parse_sections(nil, _def, _path, _allowlist), do: {:ok, []}

  @enumerated_section_keys %{
    "scope_by" => :scope_by,
    "values" => :values,
    "labels" => :labels,
    "limit" => :limit,
    "swimlanes_by" => :swimlanes_by,
    "swimlane_values" => :swimlane_values,
    "swimlane_labels" => :swimlane_labels,
    "swimlane_tones" => :swimlane_tones
  }

  # Without a "source", the sections are the enumerated values of
  # `scope_by` (a board's lanes, optionally split by `swimlanes_by`). The
  # shared verifiers check every value and key against the enumeration;
  # AshA2ui.Dynamic additionally caps the cells of a composed board.
  defp parse_sections(entry, sections_def, path, _allowlist)
       when is_map(entry) and not is_map_key(entry, "source") do
    section_path = "#{path}.sections"

    with {:ok, opts} <- convert_options(entry, @enumerated_section_keys, [], section_path) do
      case build_entity(:sections, sections_def, opts, [], section_path) do
        {:ok, sections} -> {:ok, [sections]}
        error -> error
      end
    end
  end

  defp parse_sections(entry, sections_def, path, allowlist) when is_map(entry) do
    section_path = "#{path}.sections"

    with {:ok, source} <- sections_source(entry, section_path, allowlist),
         {:ok, label} <- optional_name(entry, "label", section_path),
         entry = Map.delete(entry, "label"),
         {:ok, opts} <-
           convert_options(Map.delete(entry, "source"), @section_keys, [], section_path) do
      opts = if label, do: [{:label, label} | opts], else: opts

      case build_entity(:sections, sections_def, [{:source, source} | opts], [], section_path) do
        {:ok, sections} -> {:ok, [sections]}
        error -> error
      end
    end
  end

  defp parse_sections(_entry, _def, path, _allowlist),
    do: {:error, [Error.new("#{path}.sections", "sections must be a JSON object")]}

  defp sections_source(entry, path, allowlist) do
    case Map.fetch(entry, "source") do
      {:ok, name} when is_binary(name) ->
        case Map.fetch(allowlist, name) do
          {:ok, resource} ->
            {:ok, resource}

          :error ->
            {:error,
             [
               Error.new(
                 "#{path}.source",
                 "resource #{inspect(name)} is not available to dynamic surfaces — " <>
                   "use one of: #{Enum.join(Enum.sort(Map.keys(allowlist)), ", ")}"
               )
             ]}
        end

      _missing_or_not_binary ->
        {:error, [Error.new("#{path}.source", ~s(sections must name a "source" resource string))]}
    end
  end

  # An option that is a name when present and absent when not.
  defp optional_name(entry, key, path) do
    case Map.fetch(entry, key) do
      {:ok, value} ->
        case convert_name(String.to_atom(key), value, path, true) do
          {:ok, name} -> {:ok, name}
          {:error, errors} -> {:error, errors}
        end

      :error ->
        {:ok, nil}
    end
  end

  # --- queries ----------------------------------------------------------------

  @query_keys %{
    "name" => :name,
    "search_fields" => :search_fields,
    "sortable" => :sortable,
    "filters" => :filters,
    "hidden_filters" => :hidden_filters,
    "range_filters" => :range_filters,
    "default_sort" => :default_sort,
    "default_preset" => :default_preset,
    "preset_picker" => :preset_picker,
    "apply_on_change" => :apply_on_change,
    "page_size" => :page_size,
    "max_page_size" => :max_page_size
  }

  defp parse_query(entry, path) when is_map(entry) do
    query_def = entity_def(:query)
    [preset_def] = query_def.entities[:presets]

    with {:ok, opts} <- convert_options(entry, @query_keys, ["presets"], path),
         {:ok, presets} <- parse_presets(Map.get(entry, "presets"), preset_def, path) do
      build_entity(:query, query_def, opts, [presets: presets], path)
    end
  end

  defp parse_query(_entry, path),
    do: {:error, [Error.new(path, "each query must be a JSON object")]}

  @preset_keys %{
    "name" => :name,
    "filter" => :filter,
    "read_action" => :read_action,
    "calendar_anchor" => :calendar_anchor
  }

  defp parse_presets(nil, _def, _path), do: {:ok, []}

  defp parse_presets(entries, preset_def, path) when is_list(entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      preset_path = "#{path}.presets[#{index}]"

      result =
        with true <- is_map(entry) || {:error, [Error.new(preset_path, "must be a JSON object")]},
             {:ok, opts} <- convert_options(entry, @preset_keys, [], preset_path) do
          build_entity(:preset, preset_def, opts, [], preset_path)
        end

      case result do
        {:ok, preset} -> {:cont, {:ok, acc ++ [preset]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp parse_presets(_entries, _def, path),
    do: {:error, [Error.new("#{path}.presets", "presets must be an array")]}

  # --- fields -------------------------------------------------------------------

  @field_keys %{
    "name" => :name,
    "label" => :label,
    "widget" => :widget,
    "format" => :format,
    "order" => :order,
    "hidden" => :hidden,
    "source" => :source,
    "relationship" => :relationship,
    "option_label" => :option_label,
    "option_value" => :option_value,
    "option_sort" => :option_sort,
    "option_limit" => :option_limit,
    "option_search" => :option_search,
    "link" => :link,
    "links" => :links,
    "link_label" => :link_label
  }

  defp parse_field(entry, path) when is_map(entry) do
    with {:ok, opts} <- convert_options(entry, @field_keys, [], path),
         :ok <- check_vocabulary(opts, :widget, @widgets, path),
         :ok <- check_vocabulary(opts, :format, @formats, path) do
      build_entity(:field, entity_def(:field), opts, [], path)
    end
  end

  defp parse_field(_entry, path),
    do: {:error, [Error.new(path, "each field must be a JSON object")]}

  defp check_vocabulary(opts, key, supported, path) do
    case Keyword.get(opts, key) do
      nil ->
        :ok

      value ->
        if to_string(value) in supported do
          :ok
        else
          {:error,
           [
             Error.new(
               "#{path}.#{key}",
               "#{key} #{inspect(to_string(value))} is not supported — " <>
                 "use one of: #{Enum.join(supported, ", ")}"
             )
           ]}
        end
    end
  end

  # --- actions --------------------------------------------------------------------

  @action_keys %{
    "name" => :name,
    "label" => :label,
    "refreshes" => :refreshes,
    "prompt_fields" => :prompt_fields,
    "prompt_title" => :prompt_title,
    "visible_when" => :visible_when
  }

  @action_nested ~w(via)

  defp parse_action(entry, path) when is_map(entry) do
    with {:ok, opts} <- convert_options(entry, @action_keys, @action_nested, path),
         {:ok, via} <- via_spec(Map.get(entry, "via"), path) do
      opts = if via, do: opts ++ [{:via, via}], else: opts
      build_entity(:action, entity_def(:action), opts, [], path)
    end
  end

  defp parse_action(_entry, path),
    do: {:error, [Error.new(path, "each action must be a JSON object")]}

  @via_regex ~r|\A(?<module>[A-Z][A-Za-z0-9_.]*)\.(?<function>[a-zA-Z_][a-zA-Z0-9_?!]*)/(?<arity>\d+)\z|
  @max_via_module_bytes 255

  @doc false
  # The spec shape of a `via` delegation: {"mfa": "Mod.fun/arity", "args":
  # [...]}. The arity is the delegate's full arity — the handler applies
  # `fun` with the dispatch context prepended to `args`, so arity must be
  # 1 + length(args). The module/function must already exist in the host
  # runtime (compile-time-safe: validated here, at resolve, never called).
  # Host TRUST is a separate gate: AshA2ui.Dynamic.resolve/2's
  # :via_allowlist decides which modules a spec may delegate to.
  def via_spec(entry, path)

  def via_spec(nil, _path), do: {:ok, nil}

  def via_spec(entry, path) when is_map(entry) do
    via_path = "#{path}.via"

    with {:ok, {module, function, arity}} <- via_mfa(Map.get(entry, "mfa"), via_path),
         {:ok, args} <- via_args(entry, arity, via_path),
         :ok <- via_exists?(module, function, arity, via_path) do
      {:ok, {module, function, args}}
    end
  end

  def via_spec(_entry, path) do
    {:error,
     [
       Error.new(
         "#{path}.via",
         ~s(via must be an object with an "mfa" string like "Mod.fun/arity" and optional "args")
       )
     ]}
  end

  # Splits a validated "Mod.fun/arity" string into the MFA parts (the
  # promoter reuses this to emit the DSL's tuple literal).
  @doc false
  @spec split_mfa_string(String.t()) :: {:ok, {String.t(), String.t(), non_neg_integer}} | :error
  def split_mfa_string(mfa) when is_binary(mfa) do
    case Regex.named_captures(@via_regex, mfa) do
      %{"module" => module, "function" => function, "arity" => arity} ->
        {:ok, {module, function, String.to_integer(arity)}}

      nil ->
        :error
    end
  end

  def split_mfa_string(_mfa), do: :error

  defp via_mfa(mfa, via_path) when is_binary(mfa) do
    case split_mfa_string(mfa) do
      {:ok, {module, function, arity}} ->
        # Bounded by the regex and byte size before the atom is created; the
        # existence check below then requires the atom to already exist.
        # sobelow_skip ["DOS.StringToAtom"]
        module_atom =
          if byte_size(module) <= @max_via_module_bytes,
            do: String.to_atom("Elixir." <> module),
            else: nil

        # sobelow_skip ["DOS.StringToAtom"]
        function_atom =
          if byte_size(function) <= @max_name_bytes,
            do: String.to_atom(function),
            else: nil

        if module_atom && function_atom do
          {:ok, {module_atom, function_atom, arity}}
        else
          via_mfa_error(mfa, via_path)
        end

      :error ->
        via_mfa_error(mfa, via_path)
    end
  end

  defp via_mfa(mfa, via_path), do: via_mfa_error(mfa, via_path)

  defp via_mfa_error(mfa, via_path) do
    {:error,
     [
       Error.new(
         "#{via_path}.mfa",
         "via #{inspect(mfa)} is not a valid \"Mod.fun/arity\" string — the delegate is " <>
           "called with the dispatch context prepended to \"args\""
       )
     ]}
  end

  defp via_args(entry, arity, via_path) do
    args = Map.get(entry, "args", [])

    cond do
      not is_list(args) ->
        {:error, [Error.new("#{via_path}.args", "via args must be an array")]}

      arity < 1 ->
        {:error,
         [
           Error.new(
             "#{via_path}.mfa",
             "via arity must be at least 1 — the delegate receives the dispatch context"
           )
         ]}

      length(args) != arity - 1 ->
        {:error,
         [
           Error.new(
             "#{via_path}.args",
             "via declares arity #{arity} with #{length(args)} args — arity must be " <>
               "1 + length(args) (the dispatch context is prepended)"
           )
         ]}

      true ->
        {:ok, args}
    end
  end

  defp via_exists?(module, function, arity, via_path) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error,
         [
           Error.new(
             "#{via_path}.mfa",
             "module #{inspect(module)} is not loaded — via delegates must already exist " <>
               "in the host runtime"
           )
         ]}

      not function_exported?(module, function, arity) ->
        {:error,
         [
           Error.new(
             "#{via_path}.mfa",
             "#{inspect(module)}.#{function}/#{arity} is not exported — the handler applies " <>
               "the delegate with the dispatch context prepended to its args"
           )
         ]}

      true ->
        :ok
    end
  end

  # --- contexts -------------------------------------------------------------------

  @context_keys %{
    "name" => :name,
    "label" => :label,
    "option_label" => :option_label,
    "option_value" => :option_value,
    "option_sort" => :option_sort,
    "option_limit" => :option_limit,
    "option_search" => :option_search,
    "depends_on" => :depends_on,
    "depends_on_path" => :depends_on_path,
    "auto_select_single" => :auto_select_single,
    "picker" => :picker
  }

  defp parse_context(entry, path, allowlist) when is_map(entry) do
    with {:ok, resource} <- context_resource(entry, path, allowlist),
         {:ok, opts} <- convert_options(Map.delete(entry, "resource"), @context_keys, [], path) do
      build_entity(:context, entity_def(:context), [{:resource, resource} | opts], [], path)
    end
  end

  defp parse_context(_entry, path, _allowlist),
    do: {:error, [Error.new(path, "each context must be a JSON object")]}

  defp context_resource(entry, path, allowlist) do
    case Map.fetch(entry, "resource") do
      {:ok, name} when is_binary(name) ->
        case Map.fetch(allowlist, name) do
          {:ok, resource} ->
            {:ok, resource}

          :error ->
            {:error,
             [
               Error.new(
                 "#{path}.resource",
                 "resource #{inspect(name)} is not available to dynamic surfaces — " <>
                   "use one of: #{Enum.join(Map.keys(allowlist), ", ")}"
               )
             ]}
        end

      _missing_or_not_binary ->
        {:error, [Error.new("#{path}.resource", ~s(each context must name a "resource" string))]}
    end
  end

  # --- generic option conversion ---------------------------------------------------

  # Converts a spec entry's JSON options into the keyword list
  # `Spark.Dsl.Entity.build/5` expects, using the entity's own Spark schema
  # to pick the target shape per key. Unknown keys are rejected with the
  # supported vocabulary.
  defp convert_options(entry, key_mapping, nested_keys, path) do
    entry
    |> Enum.reject(fn {key, _value} -> to_string(key) in nested_keys end)
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case convert_entry_option(key, value, key_mapping, nested_keys, path) do
        {:ok, converted} -> {:cont, {:ok, acc ++ [converted]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_entry_option(key, value, key_mapping, nested_keys, path) do
    case Map.fetch(key_mapping, to_string(key)) do
      {:ok, option} ->
        with {:ok, converted} <- convert_option(option, value, path) do
          {:ok, {option, converted}}
        end

      :error ->
        {:error,
         [
           Error.new(
             "#{path}.#{key}",
             "unknown key #{inspect(to_string(key))} — supported keys: " <>
               Enum.join(Map.keys(key_mapping) ++ nested_keys, ", ")
           )
         ]}
    end
  end

  # Option-shaped conversions, keyed by the DSL option name. Anything not
  # special-cased passes through for Spark's schema validation to type-check.
  defp convert_option(option, value, path),
    do: convert_shaped(option_shape(option), option, value, path)

  defp convert_shaped(:name, option, value, path), do: convert_name(option, value, path, true)
  defp convert_shaped(:name_list, option, value, path), do: convert_name_list(option, value, path)
  defp convert_shaped(:link, _option, value, path), do: convert_link(value, path)

  defp convert_shaped(:search_fields, _option, value, path),
    do: convert_search_fields(value, path)

  defp convert_shaped(:default_sort, _option, value, path), do: convert_default_sort(value, path)

  defp convert_shaped({:enum, values}, option, value, path),
    do: convert_enum(option, value, values, path)

  defp convert_shaped({:enum_list, values}, option, list, path) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case convert_enum(option, value, values, path) do
        {:ok, atom} -> {:cont, {:ok, acc ++ [atom]}}
        error -> {:halt, error}
      end
    end)
  end

  defp convert_shaped({:enum_list, _values}, option, _value, path),
    do: {:error, [Error.new("#{path}.#{option}", "#{option} must be an array")]}

  defp convert_shaped({:enum_keyword, values}, option, value, path),
    do: convert_keyword(option, value, path, &convert_enum(option, &1, values, path))

  defp convert_shaped(:icon_tone_keyword, option, value, path),
    do: convert_keyword(option, value, path, &convert_tone(&1, "#{path}.#{option}"))

  defp convert_shaped(:existing_name, option, value, path),
    do: convert_existing_name(option, value, path)

  defp convert_shaped(:raw, _option, value, _path), do: {:ok, value}

  defp convert_shaped(:value_list, option, value, path),
    do: convert_value_list(option, value, path)

  defp convert_shaped(:label_keyword, option, value, path),
    do: convert_value_keyword(option, value, path, &convert_label(option, &1, path))

  defp convert_shaped(:value_tone_keyword, option, value, path),
    do: convert_value_keyword(option, value, path, &convert_tone(&1, "#{path}.#{option}"))

  defp convert_shaped(keyword_shape, option, value, path),
    do: convert_keyword(option, value, path, keyword_value(keyword_shape, option, path))

  # The per-value conversion of a keyword-shaped (JSON object) option.
  defp keyword_value(:name_keyword, option, path), do: &convert_name(option, &1, path, true)
  defp keyword_value(:raw_keyword, _option, _path), do: &{:ok, &1}
  defp keyword_value(:string_keyword, option, path), do: &convert_string(option, &1, path)
  defp keyword_value(:tone_keyword, _option, path), do: &convert_tone(&1, path)

  defp option_shape(option)
       when option in [
              :name,
              :as,
              :read_action,
              :create_action,
              :update_action,
              :query,
              :select_context,
              :context,
              :widget,
              :format,
              :relationship,
              :option_label,
              :option_value,
              :option_sort,
              :title,
              :badge,
              :depends_on,
              :default_preset,
              :subtitle,
              :icon,
              :more,
              :detail,
              :detail_date,
              :value,
              :sort,
              :links,
              :link_label
            ],
       do: :name

  defp option_shape(option)
       when option in [
              :fields,
              :row_actions,
              :require_context,
              :option_search,
              :source,
              :sortable,
              :filters,
              :hidden_filters,
              :range_filters,
              :refreshes,
              :prompt_fields,
              :meta,
              :depends_on_path
            ],
       do: :name_list

  defp option_shape(:context_filter), do: :name_keyword
  defp option_shape(option) when option in [:visible_when, :filter], do: :raw_keyword
  defp option_shape(:badge_text), do: :string_keyword
  defp option_shape(option) when option in [:icon_labels, :detail_text], do: :string_keyword

  defp option_shape(option) when option in [:icon_names, :detail_icon_names],
    do: {:enum_keyword, @cell_icons}

  defp option_shape(option) when option in [:icon_tones, :detail_icon_tones],
    do: :icon_tone_keyword

  defp option_shape(:badge_tones), do: :tone_keyword
  defp option_shape(:link), do: :link
  defp option_shape(:search_fields), do: :search_fields
  defp option_shape(:default_sort), do: :default_sort
  defp option_shape(:display), do: {:enum, @displays}
  defp option_shape(:granularity), do: {:enum, @granularities}
  defp option_shape(:granularities), do: {:enum_list, @granularities}

  defp option_shape(option)
       when option in [:date_field, :end_date_field, :scope_by, :swimlanes_by],
       do: :existing_name

  defp option_shape(option) when option in [:values, :swimlane_values], do: :value_list
  defp option_shape(option) when option in [:labels, :swimlane_labels], do: :label_keyword
  defp option_shape(:swimlane_tones), do: :value_tone_keyword
  defp option_shape(_option), do: :raw

  defp convert_enum(option, value, values, path) do
    case is_binary(value) && Map.fetch(values, value) do
      {:ok, atom} ->
        {:ok, atom}

      _unknown ->
        {:error,
         [
           Error.new(
             "#{path}.#{option}",
             "#{option} must be one of: #{values |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
           )
         ]}
    end
  end

  # A calendar date field names an attribute of the resource, and every
  # attribute name is already an atom: an existing-atom lookup only (an
  # unknown name cannot be an attribute). The shared calendar rules then
  # check the attribute's type.
  defp convert_existing_name(option, value, path) do
    with true <-
           is_binary(value) and byte_size(value) <= @max_name_bytes and value =~ @name_regex,
         {:ok, atom} <- existing_atom(value) do
      {:ok, atom}
    else
      _unknown ->
        {:error,
         [
           Error.new(
             "#{path}.#{option}",
             "#{option} #{inspect(value)} is not an attribute of the resource — name one of " <>
               existing_name_hint(option)
           )
         ]}
    end
  end

  defp existing_name_hint(option) when option in [:date_field, :end_date_field],
    do: "its date or datetime attributes"

  defp existing_name_hint(_option),
    do: "its enumerated attributes (an Ash.Type.Enum or a one_of constraint)"

  defp existing_atom(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp convert_name(_option, value, _path)
       when is_binary(value) and byte_size(value) <= @max_name_bytes do
    if value =~ @name_regex do
      # Bounded by the spec limits; see the moduledoc.
      # sobelow_skip ["DOS.StringToAtom"]
      {:ok, String.to_atom(value)}
    else
      :error
    end
  end

  defp convert_name(_option, _value, _path), do: :error

  defp convert_name(option, value, path, wrap_error?) when wrap_error? do
    case convert_name(option, value, path) do
      {:ok, name} ->
        {:ok, name}

      :error ->
        {:error,
         [
           Error.new(
             "#{path}.#{option}",
             "#{inspect(value)} is not a valid name: names are strings of letters, " <>
               "digits and underscores, starting with a letter (at most " <>
               "#{@max_name_bytes} bytes)"
           )
         ]}
    end
  end

  defp convert_name_list(option, values, path)
       when is_list(values) and length(values) > @max_list_entries do
    {:error, [Error.new("#{path}.#{option}", "at most #{@max_list_entries} entries")]}
  end

  defp convert_name_list(option, values, path) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case convert_name(option, value, path, true) do
        {:ok, name} -> {:cont, {:ok, acc ++ [name]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_name_list(option, _values, path),
    do: {:error, [Error.new("#{path}.#{option}", "#{option} must be an array of names")]}

  defp convert_keyword(option, object, path, convert_value) when is_map(object) do
    object
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, name} <- convert_name(option, to_string(key), path, true),
           {:ok, converted} <- convert_value.(value) do
        {:cont, {:ok, acc ++ [{name, converted}]}}
      else
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_keyword(option, _object, path, _convert_value) do
    {:error,
     [Error.new("#{path}.#{option}", "#{option} must be a JSON object of key/value pairs")]}
  end

  # Enumerated values (a board's `values` / `swimlane_values`) become the
  # existing atom of the same name when there is one (atom enumerations, as
  # the DSL declares them) and stay strings otherwise: the board matches
  # them against the attribute's enumeration by string form, so no atom is
  # created from them.
  defp convert_value_list(option, values, path)
       when is_list(values) and length(values) <= @max_list_entries do
    if Enum.all?(values, &(is_binary(&1) and byte_size(&1) in 1..@max_name_bytes)) do
      {:ok, Enum.map(values, &enumerated_value/1)}
    else
      value_list_error(option, path)
    end
  end

  defp convert_value_list(option, _values, path), do: value_list_error(option, path)

  defp enumerated_value(value) do
    case existing_atom(value) do
      {:ok, atom} -> atom
      :error -> value
    end
  end

  defp value_list_error(option, path) do
    {:error,
     [
       Error.new(
         "#{path}.#{option}",
         "#{option} must be an array of at most #{@max_list_entries} value strings " <>
           "(each at most #{@max_name_bytes} bytes)"
       )
     ]}
  end

  # Keyword options keyed by an enumerated value (`labels`, `swimlane_tones`,
  # ...): the keys are looked up as existing atoms (an enumerated value that
  # is an atom already exists), never created; the shared verifier then
  # checks they are values of the attribute.
  defp convert_value_keyword(option, object, path, convert_value)
       when is_map(object) and map_size(object) <= @max_list_entries do
    object
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      with {:ok, name} <- value_key(option, to_string(key), path),
           {:ok, converted} <- convert_value.(value) do
        {:cont, {:ok, acc ++ [{name, converted}]}}
      else
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  defp convert_value_keyword(option, _object, path, _convert_value) do
    {:error,
     [
       Error.new(
         "#{path}.#{option}",
         "#{option} must be a JSON object of at most #{@max_list_entries} value/text pairs"
       )
     ]}
  end

  defp value_key(option, key, path) do
    case byte_size(key) <= @max_name_bytes && existing_atom(key) do
      {:ok, atom} ->
        {:ok, atom}

      _unknown ->
        {:error,
         [
           Error.new(
             "#{path}.#{option}",
             "#{option} key #{inspect(key)} is not one of the attribute's enumerated values"
           )
         ]}
    end
  end

  @max_label_length 60
  @label_regex ~r/^[\p{L}\p{N} .,:;'"!?()\/&+\-–]+$/u

  # Lane and swimlane headings are plain text: letters, digits, spaces and
  # light punctuation, at most 60 characters. No markup characters, so a
  # composed heading can never be read as Markdown or HTML.
  defp convert_label(option, value, path) do
    if is_binary(value) and String.length(value) in 1..@max_label_length and
         Regex.match?(@label_regex, value) do
      {:ok, value}
    else
      {:error,
       [
         Error.new(
           "#{path}.#{option}",
           "#{option} values must be plain text of 1 to #{@max_label_length} characters " <>
             "(letters, digits, spaces and . , : ; ' \" ! ? ( ) / & + - only), got: " <>
             inspect(value)
         )
       ]}
    end
  end

  defp convert_tone(value, path) do
    path = if String.ends_with?(path, "_tones"), do: path, else: "#{path}.badge_tones"

    case Map.fetch(@tones, value) do
      {:ok, tone} ->
        {:ok, tone}

      :error ->
        {:error,
         [
           Error.new(
             path,
             "tone #{inspect(value)} is not supported — use one of: " <>
               Enum.join(Enum.sort(Map.keys(@tones)), ", ")
           )
         ]}
    end
  end

  # A field's `link`: a to-one relationship name ("owner"), or an explicit
  # {"surface": "<key>", "path": ["subject_id"]} for bare-id / polymorphic
  # references. The surface key stays a string (the DSL accepts either; it
  # is only ever handed to the LinkResolver as a string); path steps are
  # names like every other field reference.
  defp convert_link(value, path) when is_binary(value), do: convert_name(:link, value, path, true)

  defp convert_link(%{"surface" => surface, "path" => steps} = value, path)
       when is_binary(surface) and map_size(value) == 2 do
    cond do
      surface == "" or byte_size(surface) > @max_name_bytes ->
        link_error(path)

      not (is_list(steps) and steps != []) ->
        link_error(path)

      true ->
        case convert_name_list(:link, steps, path) do
          {:ok, names} -> {:ok, {surface, names}}
          {:error, errors} -> {:error, errors}
        end
    end
  end

  defp convert_link(_value, path), do: link_error(path)

  defp link_error(path) do
    {:error,
     [
       Error.new(
         "#{path}.link",
         ~s(link must be a relationship name, or {"surface": "<surface key>", "path": ) <>
           ~s(["<attribute>", ...]} for a bare-id reference \(a non-empty surface key of at ) <>
           "most #{@max_name_bytes} bytes and a non-empty name path)"
       )
     ]}
  end

  defp convert_string(_option, value, _path) when is_binary(value), do: {:ok, value}

  defp convert_string(option, value, path),
    do: {:error, [Error.new("#{path}.#{option}", "#{inspect(value)} must be a string")]}

  # search_fields entries are names or name paths (["author", "email"]).
  defp convert_search_fields(values, path) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} when is_list(value) ->
        case convert_name_list(:search_fields, value, path) do
          {:ok, names} -> {:cont, {:ok, acc ++ [names]}}
          {:error, errors} -> {:halt, {:error, errors}}
        end

      value, {:ok, acc} ->
        case convert_name(:search_fields, value, path, true) do
          {:ok, name} -> {:cont, {:ok, acc ++ [name]}}
          {:error, errors} -> {:halt, {:error, errors}}
        end
    end)
  end

  defp convert_search_fields(_values, path) do
    {:error,
     [
       Error.new(
         "#{path}.search_fields",
         "search_fields must be an array of names or name paths (e.g. " <>
           ~s(["subject", ["author", "email"]])
       )
     ]}
  end

  # default_sort entries are {"field": ..., "direction": "asc" | "desc"}.
  defp convert_default_sort(values, path) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      %{"field" => field} = entry, {:ok, acc} ->
        direction = Map.get(entry, "direction", "asc")

        with true <-
               direction in ["asc", "desc"] ||
                 {:error,
                  [
                    Error.new(
                      "#{path}.default_sort",
                      ~s(direction #{inspect(direction)} must be "asc" or "desc")
                    )
                  ]},
             {:ok, name} <- convert_name(:default_sort, field, path, true) do
          {:cont, {:ok, acc ++ [{name, String.to_existing_atom(direction)}]}}
        else
          {:error, errors} -> {:halt, {:error, errors}}
        end

      _entry, {:ok, _acc} ->
        {:halt,
         {:error,
          [
            Error.new(
              "#{path}.default_sort",
              ~s|default_sort entries must be objects like {"field": "inserted_at", | <>
                ~s|"direction": "desc"}|
            )
          ]}}
    end)
  end

  defp convert_default_sort(_values, path),
    do: {:error, [Error.new("#{path}.default_sort", "default_sort must be an array")]}

  # --- entity building --------------------------------------------------------------

  # Spark's Entity.build validates the converted options against the same
  # option schema the DSL macros use — dynamic specs get identical type
  # checking, one_of enforcement, required options, and defaults.
  defp build_entity(entity_name, entity_def, opts, nested_entities, path) do
    case Entity.build(entity_def, opts, nested_entities, nil, nil) do
      {:ok, entity} ->
        {:ok, entity}

      {:error, %ValidationError{key: key, message: message}} ->
        {:error, [Error.new("#{path}.#{key}", message)]}

      {:error, error} ->
        {:error, [Error.new(path, "invalid #{entity_name}: #{error_text(error)}")]}
    end
  end

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error) when is_exception(error), do: Exception.message(error)
  defp error_text(error), do: inspect(error)

  defp entity_def(name) do
    [section] = AshA2ui.sections()
    Enum.find(section.entities, &(&1.name == name))
  end
end
