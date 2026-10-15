defmodule AshA2ui.Verifiers.VerifyComponents do
  @moduledoc """
  Verifies at compile time that the surface's component set is sound:

    * component keys (`as` name, or the kind for unnamed components) are
      unique — in particular, at most one `:table` and one `:detail` may
      omit their names,
    * at most one `:form` component is declared,
    * only `:table` and `:detail` components may carry an `as` name,
    * only `:table` components may name a `resource` (a related table), it
      must be an Ash resource, and a related table is read-only — no
      `row_actions`, `editable` or `sections`,

  and that `action` entities (per-action refresh metadata) are sound:

    * action names are unique,
    * every `action` names an action reachable from the surface (listed in a
      table's `row_actions` or `bulk_actions`, or the form's create/update
      action),
    * every `refreshes` entry names a declared `:table` component key.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Unlike the other verifiers this one needs no
  resolved resource — it checks the DSL section against itself.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Component
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    components = entities(dsl_state, AshA2ui.Component)
    actions = entities(dsl_state, AshA2ui.Action)

    with :ok <- verify_named_tables_only(components, module),
         :ok <- verify_related_tables(components, target_resource(dsl_state), module),
         :ok <- verify_unique_keys(components, module),
         :ok <- verify_single_form(components, module),
         :ok <- verify_unique_action_names(actions, module),
         :ok <- verify_action_references(actions, components, dsl_state, module) do
      verify_refresh_targets(actions, components, module)
    end
  end

  defp verify_named_tables_only(components, module) do
    case Enum.find(
           components,
           &(&1.name not in [:table, :detail, :report] and not is_nil(&1.as))
         ) do
      nil ->
        :ok

      component ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, component.name],
           message:
             "component #{inspect(component.name)} cannot be named #{inspect(component.as)}: " <>
               "only :table, :detail and :report components may carry a distinguishing name"
         )}
    end
  end

  # A related table reads another resource as the surface's actor; it shows
  # rows, it does not act on them (row actions, inline edits and sections are
  # all dispatched against the surface resource).
  defp verify_related_tables(components, target, module) do
    Enum.reduce_while(components, :ok, fn component, :ok ->
      case verify_related_table(component, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_related_table(%Component{resource: nil}, _target, _module), do: :ok

  defp verify_related_table(%Component{name: name} = component, _target, module)
       when name != :table do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, Component.key(component), :resource],
       message:
         "component #{inspect(name)} cannot name a resource: only :table components " <>
           "may read another resource (a related table)"
     )}
  end

  defp verify_related_table(%Component{resource: resource} = component, target, module) do
    key = Component.key(component)

    cond do
      not (Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource)) ->
        related_error(module, key, :resource, "#{inspect(resource)} is not an Ash resource")

      resource == target ->
        :ok

      component.row_actions != [] ->
        related_error(
          module,
          key,
          :row_actions,
          "a related table is read-only: row_actions are dispatched against the surface " <>
            "resource, not #{inspect(resource)}"
        )

      not is_nil(component.editable) ->
        related_error(module, key, :editable, "a related table is read-only: no editable block")

      not is_nil(component.sections) ->
        related_error(module, key, :sections, "a related table cannot declare sections")

      true ->
        :ok
    end
  end

  defp related_error(module, key, option, detail) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, option],
       message: "related table #{inspect(key)}: #{detail}"
     )}
  end

  defp verify_unique_keys(components, module) do
    components
    |> Enum.frequencies_by(&Component.key/1)
    |> Enum.find(fn {_key, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {key, _count} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key],
           message:
             "duplicate component name #{inspect(key)}: component names must be unique — " <>
               "give each additional :table a distinguishing name " <>
               "(`component :table, :my_name do ... end`)"
         )}
    end
  end

  defp verify_single_form(components, module) do
    if Enum.count(components, &(&1.name == :form)) > 1 do
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :component, :form],
         message: "at most one :form component may be declared per surface"
       )}
    else
      :ok
    end
  end

  defp verify_unique_action_names(actions, module) do
    actions
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :action, name],
           message: "duplicate action entity #{inspect(name)}: action names must be unique"
         )}
    end
  end

  # An `action` entity is refresh metadata for a client-reachable action:
  # a row action of some table, a table's editable update_action (inline
  # cell editing), or the form's create/update action (including the
  # primary-action defaults a form or editable block falls back to, when
  # the resource is resolvable).
  defp verify_action_references(actions, components, dsl_state, module) do
    reachable = reachable_actions(components, dsl_state)

    case Enum.find(actions, &(not MapSet.member?(reachable, &1.name))) do
      nil ->
        :ok

      action ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :action, action.name],
           message: """
           action #{inspect(action.name)} is not reachable from any component.

           `action` entities attach refresh metadata to a table's row_actions entry or \
           to the form's create/update action. \
           Reachable actions: #{inspect(MapSet.to_list(reachable))}
           """
         )}
    end
  end

  defp reachable_actions(components, dsl_state) do
    target = target_resource(dsl_state)
    form = Enum.find(components, &(&1.name == :form))

    components
    |> Enum.flat_map(fn component ->
      component.row_actions ++
        component.bulk_actions ++
        Enum.reject([component.create_action, component.update_action], &is_nil/1)
    end)
    |> Enum.concat(form_defaults(form, target))
    |> Enum.concat(editable_actions(components, target))
    |> MapSet.new()
  end

  # The update actions editable blocks commit through (declared, or the
  # primary update they fall back to when the resource is resolvable).
  defp editable_actions(components, target) do
    components
    |> Enum.filter(& &1.editable)
    |> Enum.flat_map(&editable_action(&1.editable.update_action, target))
  end

  defp editable_action(nil, nil), do: []

  defp editable_action(nil, target) do
    case ResourceInfo.primary_action(target, :update) do
      %{name: name} -> [name]
      nil -> []
    end
  end

  defp editable_action(declared, _target), do: [declared]

  # The primary create/update actions a form falls back to when it omits
  # create_action/update_action.
  defp form_defaults(nil, _target), do: []
  defp form_defaults(_form, nil), do: []

  defp form_defaults(form, target) do
    [{form.create_action, :create}, {form.update_action, :update}]
    |> Enum.filter(fn {declared, _type} -> is_nil(declared) end)
    |> Enum.flat_map(fn {_declared, type} ->
      case ResourceInfo.primary_action(target, type) do
        %{name: name} -> [name]
        nil -> []
      end
    end)
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end

  defp verify_refresh_targets(actions, components, module) do
    table_keys =
      components
      |> Enum.filter(&(&1.name == :table))
      |> MapSet.new(&Component.key/1)

    Enum.reduce_while(actions, :ok, fn action, :ok ->
      case Enum.find(List.wrap(action.refreshes), &(not MapSet.member?(table_keys, &1))) do
        nil ->
          {:cont, :ok}

        unknown ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:a2ui, :action, action.name, :refreshes],
              message: """
              action #{inspect(action.name)} refreshes unknown table component #{inspect(unknown)}.

              Every refreshes entry must name a declared :table component (the unnamed table \
              is :table). Declared tables: #{inspect(MapSet.to_list(table_keys))}
              """
            )}}
      end
    end)
  end

  defp entities(dsl_state, struct_module) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, struct_module))
  end
end
