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
      lanes (it caps lanes, not cards per lane).

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
  end

  defp verify_component(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_table(component, key, module),
         :ok <- verify_no_select_context(component, key, module),
         :ok <- verify_scope_by(component, key, dsl_state, module) do
      case component.sections.source do
        nil -> verify_enumerated(component, key, dsl_state, module)
        _source -> verify_source(component, key, module)
      end
    end
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
        with :ok <- verify_known_values(sections.values || [], all, :values, key, module),
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
