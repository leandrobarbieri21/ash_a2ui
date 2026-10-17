defmodule AshA2ui.Verifiers.VerifySections do
  @moduledoc """
  Verifies at compile time that `sections` blocks (dynamic table sets) are
  sound:

    * only `:table` components may declare a `sections` block,
    * a list-mode sectioned table may not also declare `select_context`
      (a board may: each card carries the per-row select control, which
      dispatches `context_select` with the card's id — nothing in it
      depends on the runtime lane name),
    * `scope_by` is a public attribute of the surface's resource,
    * `label` / `value` / `sort`, when declared, are public attributes of the
      section `source`,
    * `read_action`, when declared, is a read action of the source,
    * a source with a composite primary key requires an explicit `value`,
    * with a `source`, `values` and `labels` are not declared (they shape
      source-less sections only),
    * without a `source` (a board's enumerated lanes, see `AshA2ui.Board`):
      `label` / `value` / `sort` / `read_action` are not declared, `scope_by`
      has enumerable values (an `Ash.Type.Enum` or a `one_of` constraint),
      every `values` entry is one of them, and every `labels` key is one of
      them; no two lanes share a runtime name (a value listed twice, or two
      values that sanitize alike), and `limit` is not below the number of
      lanes (it caps lanes, not cards per lane),
    * swimlanes (`swimlanes_by`, a board's second axis): only on a
      `display :board` without a `source`, on a public attribute or
      calculation other than `scope_by` with enumerable values; every
      `swimlane_values` entry and every `swimlane_labels` / `swimlane_tones`
      key is one of them, every tone is in the `badge_tones` vocabulary
      (`AshA2ui.RowLayout.tones/0`), no two swimlanes (and no two cells)
      share a runtime name, the `swimlane_*` options require
      `swimlanes_by`, and `limit` is not below the number of cells,
    * `values` and `swimlane_values` are not empty,
    * across the surface, a board's runtime names (lanes or cells, swimlane
      rows, stage columns) neither equal another table's key nor extend one
      another at an underscore (`board_high` and `board_high_total`), since
      component ids append `_<suffix>` to a runtime name.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped checks degrade gracefully when the target
  resource cannot be resolved at verification time (cross-module compile
  ordering), matching the other verifiers.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    components =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, AshA2ui.Component))

    components
    |> Enum.filter(& &1.sections)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, dsl_state, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      :ok -> verify_runtime_names(components, dsl_state, module)
      error -> error
    end
  end

  defp verify_component(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_table(component, key, module),
         :ok <- verify_no_select_context(component, key, module),
         :ok <- verify_scope_by(component, key, dsl_state, module),
         :ok <- verify_mode(component, key, dsl_state, module) do
      verify_swimlanes(component, key, dsl_state, module)
    end
  end

  defp verify_mode(component, key, dsl_state, module) do
    case component.sections.source do
      nil -> verify_enumerated(component, key, dsl_state, module)
      _source -> verify_source(component, key, module)
    end
  end

  # --- swimlanes (a board's second axis) ---

  @swimlane_options [:swimlane_values, :swimlane_labels, :swimlane_tones]

  defp verify_swimlanes(%{sections: %{swimlanes_by: nil} = sections}, key, _dsl_state, module) do
    case Enum.find(@swimlane_options, &(Map.fetch!(sections, &1) not in [nil, []])) do
      nil ->
        :ok

      option ->
        sections_error(module, key, option, "sections option #{option} requires swimlanes_by")
    end
  end

  defp verify_swimlanes(component, key, dsl_state, module) do
    sections = component.sections

    cond do
      not is_nil(sections.source) ->
        sections_error(
          module,
          key,
          :swimlanes_by,
          "swimlanes_by requires sections without a source (a board's enumerated lanes)"
        )

      component.display != :board ->
        sections_error(
          module,
          key,
          :swimlanes_by,
          "swimlanes_by splits a board into rows: table #{inspect(key)} needs display :board"
        )

      sections.swimlanes_by == sections.scope_by ->
        sections_error(
          module,
          key,
          :swimlanes_by,
          "swimlanes_by #{inspect(sections.swimlanes_by)} is the lane attribute (scope_by): " <>
            "swimlanes need a second attribute"
        )

      true ->
        case target_resource(dsl_state) do
          nil -> verify_swimlane_tones(sections, key, module)
          resource -> verify_swimlane_attribute(sections, key, resource, module)
        end
    end
  end

  defp verify_swimlane_attribute(sections, key, resource, module) do
    attribute = sections.swimlanes_by

    if public_attribute?(resource, attribute) or public_calculation?(resource, attribute) do
      verify_swimlane_values(sections, key, resource, module)
    else
      sections_error(
        module,
        key,
        :swimlanes_by,
        "swimlanes_by #{inspect(attribute)} is not a public attribute or calculation of " <>
          "#{inspect(resource_name(resource))}"
      )
    end
  end

  defp verify_swimlane_values(sections, key, resource, module) do
    case AshA2ui.Board.enumerated_values(resource, sections.swimlanes_by) do
      {:ok, all} ->
        swimlanes =
          Enum.map(sections.swimlane_values || all, &AshA2ui.Board.match_value(&1, all))

        with :ok <-
               verify_known_swimlane_values(
                 sections.swimlane_values || [],
                 all,
                 :swimlane_values,
                 key,
                 module
               ),
             :ok <-
               verify_known_swimlane_values(
                 Keyword.keys(sections.swimlane_labels),
                 all,
                 :swimlane_labels,
                 key,
                 module
               ),
             :ok <-
               verify_known_swimlane_values(
                 Keyword.keys(sections.swimlane_tones),
                 all,
                 :swimlane_tones,
                 key,
                 module
               ),
             :ok <- verify_not_empty(sections.swimlane_values, :swimlane_values, key, module),
             :ok <- verify_swimlane_tones(sections, key, module),
             :ok <- verify_distinct_swimlanes(sections, swimlanes, key, module) do
          verify_cells(sections, swimlanes, key, resource, module)
        end

      :error ->
        sections_error(
          module,
          key,
          :swimlanes_by,
          "swimlanes need enumerable values: swimlanes_by " <>
            "#{inspect(sections.swimlanes_by)} is neither an Ash.Type.Enum nor " <>
            "constrained by one_of"
        )
    end
  end

  defp verify_known_swimlane_values(values, all, option, key, module) do
    case Enum.find(values, &is_nil(AshA2ui.Board.match_value(&1, all))) do
      nil ->
        :ok

      unknown ->
        sections_error(
          module,
          key,
          option,
          "#{option} entry #{inspect(unknown)} is not an enumerated value of " <>
            "swimlanes_by (#{Enum.map_join(all, ", ", &inspect/1)})"
        )
    end
  end

  defp verify_swimlane_tones(sections, key, module) do
    tones = AshA2ui.RowLayout.tones()

    case Enum.find(sections.swimlane_tones, fn {_value, tone} -> tone not in tones end) do
      nil ->
        :ok

      {value, tone} ->
        sections_error(
          module,
          key,
          :swimlane_tones,
          "swimlane_tones for #{inspect(value)} must be one of " <>
            "#{Enum.map_join(tones, ", ", &inspect/1)}, got: #{inspect(tone)}"
        )
    end
  end

  # Every swimlane is a row with its own component ids and data-model paths
  # (`AshA2ui.Board.swimlane_name/2`): no value listed twice, no two values
  # that sanitize alike.
  defp verify_distinct_swimlanes(sections, swimlanes, key, module) do
    clash =
      swimlanes
      |> Enum.group_by(&AshA2ui.Board.swimlane_name(key, &1))
      |> Enum.find(fn {_name, values} -> length(values) > 1 end)

    case clash do
      nil ->
        :ok

      {name, values} ->
        option = if sections.swimlane_values, do: :swimlane_values, else: :swimlanes_by

        message =
          case Enum.uniq(values) do
            [value] ->
              "swimlane_values lists #{inspect(value)} more than once: each swimlane " <>
                "is rendered once, as #{name}"

            distinct ->
              "swimlane values #{Enum.map_join(distinct, " and ", &inspect/1)} collide " <>
                "on the runtime name #{name}: list only one of them in swimlane_values"
          end

        sections_error(module, key, option, message)
    end
  end

  # Cell names join a lane and a swimlane name with `__`; a value with a
  # leading or trailing non-alphanumeric run can make two cells meet.
  defp verify_cells(sections, swimlanes, key, resource, module) do
    case AshA2ui.Board.enumerated_values(resource, sections.scope_by) do
      {:ok, all} ->
        lanes = Enum.map(sections.values || all, &AshA2ui.Board.match_value(&1, all))

        with :ok <- verify_cell_names(lanes, swimlanes, key, module) do
          verify_cell_limit(sections, resource, lanes, swimlanes, key, module)
        end

      :error ->
        :ok
    end
  end

  # On a swimlaned board `limit` caps the cells: every cell is a table with
  # its own page read and count, issued on every render and on every
  # refresh of the board, so the cell count is the board's read cost.
  defp verify_cell_limit(sections, resource, lanes, swimlanes, key, module) do
    case AshA2ui.Board.cell_count(resource, sections) do
      {:ok, cells} when sections.limit >= cells ->
        :ok

      {:ok, cells} ->
        sections_error(
          module,
          key,
          :limit,
          "limit #{sections.limit} is below the #{cells} cells (#{length(lanes)} lanes x " <>
            "#{length(swimlanes)} swimlanes): on a swimlaned board limit caps the cells, and " <>
            "each cell is two reads (its page and its count) on every render and every " <>
            "refresh of the board; narrow values or swimlane_values, or raise limit"
        )

      # The enumerability checks run first, so this is not reached today;
      # it keeps a reordering of checks a diagnostic instead of a crash.
      :error ->
        sections_error(
          module,
          key,
          :limit,
          "cannot count the board's cells: scope_by #{inspect(sections.scope_by)} and " <>
            "swimlanes_by #{inspect(sections.swimlanes_by)} both need enumerable values " <>
            "(an Ash.Type.Enum or a one_of constraint)"
        )
    end
  end

  defp verify_cell_names(lanes, swimlanes, key, module) do
    clash =
      for(swimlane <- swimlanes, lane <- lanes, do: {lane, swimlane})
      |> Enum.group_by(fn {lane, swimlane} -> AshA2ui.Board.cell_name(key, lane, swimlane) end)
      |> Enum.find(fn {_name, cells} -> length(cells) > 1 end)

    case clash do
      nil ->
        :ok

      {name, cells} ->
        sections_error(
          module,
          key,
          :swimlanes_by,
          "cells #{Enum.map_join(cells, " and ", &inspect/1)} collide on the runtime " <>
            "name #{name}: rename a lane or swimlane value"
        )
    end
  end

  # An empty `values` or `swimlane_values` enumerates nothing: the board
  # (heading, create button and every lane) would render as nothing at all.
  defp verify_not_empty([], option, key, module) do
    sections_error(
      module,
      key,
      option,
      "#{option} [] leaves the board with nothing to show: list at least one value, " <>
        "or drop #{option} to show every value"
    )
  end

  defp verify_not_empty(_values, _option, _key, _module), do: :ok

  # --- runtime names across the surface ---

  # The encoder builds component ids by putting a runtime name after a
  # leading noun and appending `_<suffix>` (`lane_<cell>_total`,
  # `swimlane_<swimlane>_cells`, `table_cell_<table>_<field>`, ...), and a
  # table's runtime name is also its data-model key (`/records/<name>`).
  # So a board's runtime names may neither equal another table's key, nor
  # extend one another at an underscore (lanes `:high` and `:high_total`
  # give two `lane_board_high_total` ids). Checked per id family: tables
  # (lanes, or a swimlaned board's cells), swimlane rows and stage columns.
  defp verify_runtime_names(components, dsl_state, module) do
    case target_resource(dsl_state) do
      nil -> :ok
      resource -> do_verify_runtime_names(components, resource, module)
    end
  end

  defp do_verify_runtime_names(components, resource, module) do
    boards =
      for %{name: :table, sections: %{source: nil}} = component <- components,
          names <- List.wrap(board_names(component, resource)),
          do: {AshA2ui.Component.key(component), names}

    plain_keys =
      for %{name: :table, sections: nil} = component <- components,
          into: %{},
          do: {to_string(AshA2ui.Component.key(component)), AshA2ui.Component.key(component)}

    # Swimlane rows and stage columns first: a clash there is the root of
    # the matching clash between cells.
    [_swimlanes, _stages, tables] =
      families =
      for family <- [:swimlanes, :stages, :tables] do
        for {key, names} <- boards, name <- Map.fetch!(names, family), do: {name, key}
      end

    with :ok <- verify_against_plain_tables(tables, plain_keys, module) do
      Enum.find_value(families, :ok, &prefix_clash(&1, module))
    end
  end

  defp prefix_clash(family, module) do
    case verify_name_prefixes(family, module) do
      :ok -> nil
      error -> error
    end
  end

  # The runtime names of a source-less board whose values all resolve
  # (the per-component checks have passed): `nil` when they do not.
  defp board_names(component, resource) do
    sections = component.sections
    key = AshA2ui.Component.key(component)

    with {:ok, lanes} <- chosen(resource, sections.scope_by, sections.values),
         {:ok, swimlanes} <- chosen_swimlanes(resource, sections) do
      lane_names = Enum.map(lanes, &AshA2ui.Sections.section_name(key, &1))

      case swimlanes do
        [] ->
          %{tables: lane_names, swimlanes: [], stages: []}

        swimlanes ->
          %{
            tables:
              for(sw <- swimlanes, lane <- lanes, do: AshA2ui.Board.cell_name(key, lane, sw)),
            swimlanes: Enum.map(swimlanes, &AshA2ui.Board.swimlane_name(key, &1)),
            stages: lane_names
          }
      end
    else
      :error -> nil
    end
  end

  defp chosen_swimlanes(_resource, %{swimlanes_by: nil}), do: {:ok, []}

  defp chosen_swimlanes(resource, sections),
    do: chosen(resource, sections.swimlanes_by, sections.swimlane_values)

  defp chosen(resource, attribute, values) do
    case AshA2ui.Board.enumerated_values(resource, attribute) do
      {:ok, all} -> {:ok, Enum.map(values || all, &AshA2ui.Board.match_value(&1, all))}
      :error -> :error
    end
  end

  defp verify_against_plain_tables(table_names, plain_keys, module) do
    case Enum.find(table_names, fn {name, _key} -> Map.has_key?(plain_keys, name) end) do
      nil ->
        :ok

      {name, key} ->
        sections_error(
          module,
          key,
          :scope_by,
          "board #{inspect(key)} expands into a table named #{name}, which is also the key " <>
            "of table #{inspect(Map.fetch!(plain_keys, name))}: the two would share " <>
            "/records/#{name} and their component ids; rename one of them"
        )
    end
  end

  defp verify_name_prefixes(family, module) do
    clash =
      for {name, key} <- family,
          {other, _other_key} <- family,
          String.starts_with?(other, name <> "_"),
          do: {key, name, other}

    case clash do
      [] ->
        :ok

      [{key, name, other} | _rest] ->
        sections_error(
          module,
          key,
          :scope_by,
          "runtime names #{name} and #{other} can produce the same component id: " <>
            "component ids append _<suffix> to a runtime name, and #{other} is #{name} " <>
            "plus _#{String.replace_prefix(other, name <> "_", "")}; rename or drop one " <>
            "of the values"
        )
    end
  end

  defp sections_error(module, key, option, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections, option],
       message: message
     )}
  end

  defp verify_table(%{name: :table}, _key, _module), do: :ok

  defp verify_table(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections],
       message:
         "component #{inspect(key)} cannot declare a sections block: dynamic table " <>
           "sets are only supported on :table components"
     )}
  end

  defp verify_no_select_context(%{select_context: nil}, _key, _module), do: :ok
  defp verify_no_select_context(%{display: :board}, _key, _module), do: :ok

  defp verify_no_select_context(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections],
       message:
         "table #{inspect(key)} cannot combine a sections block with select_context: " <>
           "per-row context selection on sectioned tables is supported on boards " <>
           "(display :board) only"
     )}
  end

  defp verify_scope_by(component, key, dsl_state, module) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      resource ->
        if public_attribute?(resource, component.sections.scope_by) or
             public_calculation?(resource, component.sections.scope_by) do
          :ok
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :component, key, :sections, :scope_by],
             message:
               "scope_by #{inspect(component.sections.scope_by)} is not a public " <>
                 "attribute or calculation of #{inspect(resource_name(resource))}"
           )}
        end
    end
  end

  defp verify_source(component, key, module) do
    sections = component.sections
    source = sections.source

    with :ok <-
           verify_source_only(
             sections,
             [:values],
             key,
             module,
             "applies only to sections without a source"
           ),
         :ok <- verify_labels_without_source(sections, key, module) do
      verify_source_attributes(sections, source, key, module)
    end
  end

  defp verify_labels_without_source(%{labels: []}, _key, _module), do: :ok

  defp verify_labels_without_source(_sections, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections, :labels],
       message:
         "labels shape source-less sections only: with a source, headings come " <>
           "from the source's label attribute"
     )}
  end

  defp verify_source_attributes(sections, source, key, module) do
    if Code.ensure_loaded?(source) and ResourceInfo.resource?(source) do
      with :ok <- verify_source_attribute(sections, :label, key, module),
           :ok <- verify_source_attribute(sections, :value, key, module),
           :ok <- verify_source_attribute(sections, :sort, key, module),
           :ok <- verify_read_action(sections, key, module) do
        verify_value_inferable(sections, key, module)
      end
    else
      :ok
    end
  end

  # --- source-less sections (enumerated values) ---

  defp verify_enumerated(component, key, dsl_state, module) do
    sections = component.sections

    with :ok <-
           verify_source_only(
             sections,
             [:label, :value, :sort, :read_action],
             key,
             module,
             "requires a source"
           ) do
      case target_resource(dsl_state) do
        nil -> :ok
        resource -> verify_enumerable(sections, key, resource, module)
      end
    end
  end

  # Options that belong to one mode only: `values` without a source,
  # `label`/`value`/`sort`/`read_action` with one.
  defp verify_source_only(sections, options, key, module, requirement) do
    case Enum.find(options, &(not is_nil(Map.fetch!(sections, &1)))) do
      nil ->
        :ok

      option ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, option],
           message: "sections option #{option} #{requirement}"
         )}
    end
  end

  defp verify_enumerable(sections, key, resource, module) do
    labelled = Keyword.keys(sections.labels)

    case AshA2ui.Board.enumerated_values(resource, sections.scope_by) do
      {:ok, all} ->
        with :ok <- verify_not_empty(sections.values, :values, key, module),
             :ok <- verify_known_values(sections.values || [], all, :values, key, module),
             :ok <- verify_known_values(labelled, all, :labels, key, module),
             lanes = Enum.map(sections.values || all, &AshA2ui.Board.match_value(&1, all)),
             :ok <- verify_distinct_lanes(sections, lanes, key, module) do
          verify_lane_limit(sections, lanes, key, module)
        end

      :error ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, :scope_by],
           message:
             "sections without a source need enumerable values: scope_by " <>
               "#{inspect(sections.scope_by)} is neither an Ash.Type.Enum nor " <>
               "constrained by one_of"
         )}
    end
  end

  defp verify_known_values(values, all, option, key, module) do
    case Enum.find(values, &is_nil(AshA2ui.Board.match_value(&1, all))) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, option],
           message:
             "#{option} entry #{inspect(unknown)} is not an enumerated value of " <>
               "scope_by (#{Enum.map_join(all, ", ", &inspect/1)})"
         )}
    end
  end

  # Every lane is a table with its own component ids and data-model paths
  # (`AshA2ui.Sections.section_name/2`), so two lanes may not share a
  # runtime name: neither a value listed twice in `values` (`:open` and
  # `"open"` are the same value) nor two values that sanitize alike
  # (`:"in-progress"` and `:in_progress`).
  defp verify_distinct_lanes(sections, lanes, key, module) do
    clash =
      lanes
      |> Enum.group_by(&AshA2ui.Sections.section_name(key, &1))
      |> Enum.find(fn {_name, values} -> length(values) > 1 end)

    case clash do
      nil ->
        :ok

      {name, values} ->
        option = if sections.values, do: :values, else: :scope_by

        message =
          case Enum.uniq(values) do
            [value] ->
              "values lists #{inspect(value)} more than once: each lane is " <>
                "rendered once, as #{name}"

            distinct ->
              "lane values #{Enum.map_join(distinct, " and ", &inspect/1)} collide " <>
                "on the runtime name #{name}: list only one of them in values"
          end

        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, option],
           message: message
         )}
    end
  end

  # Without a source, `limit` caps the number of lanes, not the cards per
  # lane (a lane's page size comes from its query); a limit below the lane
  # count would drop the trailing lanes silently.
  defp verify_lane_limit(%{limit: limit}, lanes, _key, _module) when limit >= length(lanes),
    do: :ok

  defp verify_lane_limit(sections, lanes, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :sections, :limit],
       message:
         "limit #{sections.limit} is below the #{length(lanes)} lanes " <>
           "(#{Enum.map_join(lanes, ", ", &inspect/1)}): without a source, limit " <>
           "caps the number of lanes, not the cards per lane (set a lane's page " <>
           "size with its query's page_size); narrow the lanes with values instead"
     )}
  end

  defp verify_source_attribute(sections, option, key, module) do
    case Map.fetch!(sections, option) do
      nil ->
        :ok

      name ->
        if public_attribute?(sections.source, name) do
          :ok
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:a2ui, :component, key, :sections, option],
             message:
               "#{option} #{inspect(name)} is not a public attribute of the section " <>
                 "source #{inspect(sections.source)}"
           )}
        end
    end
  end

  defp verify_read_action(%{read_action: nil}, _key, _module), do: :ok

  defp verify_read_action(sections, key, module) do
    case ResourceInfo.action(sections.source, sections.read_action) do
      %{type: :read} ->
        :ok

      _missing_or_not_read ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, :read_action],
           message:
             "read_action #{inspect(sections.read_action)} is not a read action of the " <>
               "section source #{inspect(sections.source)}"
         )}
    end
  end

  defp verify_value_inferable(%{value: nil} = sections, key, module) do
    case ResourceInfo.primary_key(sections.source) do
      [_single] ->
        :ok

      composite ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :sections, :value],
           message:
             "cannot infer the section value: #{inspect(sections.source)} has a " <>
               "composite primary key #{inspect(composite)} — set value explicitly"
         )}
    end
  end

  defp verify_value_inferable(_sections, _key, _module), do: :ok

  defp public_attribute?(resource, name) do
    match?(%{public?: true}, ResourceInfo.attribute(resource, name))
  end

  # A public calculation can scope sections too: the runtime filter
  # (`scope_by == value`) works for calculations the same way it does for
  # attributes, and a derived lane key — a status-to-board-column mapping,
  # say — is a calculation by nature.
  defp public_calculation?(resource, name) do
    match?(%{public?: true}, ResourceInfo.calculation(resource, name))
  end

  # The resource whose attributes scope_by must exist on: for_resource in a
  # standalone UI module, the resource itself otherwise. Unresolvable (e.g.
  # not yet compiled) -> checks are skipped, like VerifyFields.
  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end

  defp resource_name(dsl_state_or_module) when is_atom(dsl_state_or_module),
    do: dsl_state_or_module

  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
