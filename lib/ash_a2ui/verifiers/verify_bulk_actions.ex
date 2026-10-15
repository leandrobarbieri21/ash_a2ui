defmodule AshA2ui.Verifiers.VerifyBulkActions do
  @moduledoc """
  Verifies at compile time that `bulk_actions` declarations are sound:

    * only `:table` components may declare `bulk_actions`,
    * a related table (`resource` set to another resource) may not declare
      `bulk_actions`, as it may not declare `row_actions`,
    * every entry names an existing action of type `:update`, `:destroy` or
      `:action` (generic),
    * a generic bulk action declares a `:record_id` argument (it is how the
      action learns which selected record each call is for; without it every
      call would run with the same empty input),
    * a bulk action may not declare `prompt_fields` (one shared prompt for
      many records is not supported),
    * the table's resource has a single primary key (the selection is a
      list of row ids),
    * the table is not a `display :board` (board lanes render without the
      selection toolbar, so the declaration would silently do nothing).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. The resource-dependent checks are skipped when no
  resource can be resolved (standalone UI module without `for_resource`).
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshA2ui.Component
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @bulk_types [:update, :destroy, :action]

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:a2ui])
    components = Enum.filter(entities, &(is_struct(&1, Component) and &1.bulk_actions != []))
    settings = entities |> Enum.filter(&is_struct(&1, AshA2ui.Action)) |> Map.new(&{&1.name, &1})
    target = target_resource(dsl_state)

    Enum.reduce_while(components, :ok, fn component, :ok ->
      case verify_component(component, settings, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(%Component{name: name} = component, _settings, _target, module)
       when name != :table do
    error(
      module,
      component,
      "component #{inspect(name)} cannot declare bulk_actions: only :table components run " <>
        "actions over a row selection"
    )
  end

  defp verify_component(%Component{resource: resource} = component, _settings, target, module)
       when not is_nil(resource) and resource != target do
    error(
      module,
      component,
      "related table #{inspect(Component.key(component))}: a related table is read-only, " <>
        "so it cannot declare bulk_actions (they run against the surface resource)"
    )
  end

  defp verify_component(%Component{display: :board} = component, _settings, _target, module) do
    error(
      module,
      component,
      "table #{inspect(Component.key(component))} is a display :board: board lanes have no " <>
        "selection toolbar, so bulk_actions are not supported on boards"
    )
  end

  defp verify_component(_component, _settings, nil, _module), do: :ok

  defp verify_component(component, settings, target, module) do
    with :ok <- verify_actions(component, target, module),
         :ok <- verify_no_prompts(component, settings, module) do
      verify_primary_key(component, target, module)
    end
  end

  defp verify_actions(component, target, module) do
    Enum.reduce_while(component.bulk_actions, :ok, fn name, :ok ->
      case verify_action(name, Info.action(target, name)) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, error(module, component, message)}
      end
    end)
  end

  defp verify_action(name, %{type: :action, arguments: arguments}) do
    if Enum.any?(arguments, &(&1.name == :record_id)) do
      :ok
    else
      {:error,
       "bulk action #{inspect(name)} is a generic action without a :record_id " <>
         "argument: a generic bulk action runs once per selected record and must " <>
         "declare `argument :record_id` to receive that record's id"}
    end
  end

  defp verify_action(_name, %{type: type}) when type in @bulk_types, do: :ok

  defp verify_action(name, nil) do
    {:error,
     "bulk action #{inspect(name)} does not exist on the resource: every " <>
       "bulk_actions entry must name an update, destroy or generic action"}
  end

  defp verify_action(name, %{type: type}) do
    {:error,
     "bulk action #{inspect(name)} is a #{inspect(type)} action: bulk_actions must " <>
       "name update, destroy or generic actions"}
  end

  defp verify_no_prompts(component, settings, module) do
    case Enum.find(component.bulk_actions, &match?(%{prompt_fields: [_ | _]}, settings[&1])) do
      nil ->
        :ok

      name ->
        error(
          module,
          component,
          "bulk action #{inspect(name)} declares prompt_fields: a bulk action cannot " <>
            "prompt for values (one shared prompt for many records is not supported)"
        )
    end
  end

  defp verify_primary_key(component, target, module) do
    case Info.primary_key(target) do
      [_single] ->
        :ok

      keys ->
        error(
          module,
          component,
          "bulk_actions require a single primary key (the selection is a list of row ids), " <>
            "but the resource's primary key is #{inspect(keys)}"
        )
    end
  end

  defp error(module, component, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, Component.key(component), :bulk_actions],
       message: message
     )}
  end

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end
end
