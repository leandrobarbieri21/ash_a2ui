defmodule AshA2ui.Verifiers.VerifyEditable do
  @moduledoc """
  Verifies at compile time that `editable` blocks (editing in place) are
  sound:

    * only `:table` and `:detail` components may declare an `editable`
      block,
    * a table may not combine `editable` with a `row_layout` (card rows
      render read-only meta values), and `visible` is a detail card's,
    * every editable field is one of the component's fields,
    * when the record's resource is resolvable (a table's target, a detail
      card's context's resource): the resolved `update_action` is an update
      action of the resource, and every editable field (a detail field's
      `edit` attribute, else the field) is accepted by it (an attribute in
      its `accept` list or an argument); a detail card's `visible` is a
      field of the resource.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Checks needing the target resource degrade
  gracefully when it cannot be resolved at verification time, matching the
  other verifiers.
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
    |> Enum.filter(& &1.editable)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, dsl_state, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_kind(component, key, module),
         :ok <- verify_no_row_layout(component, key, module),
         :ok <- verify_component_fields(component, key, module) do
      verify_update_action(component, key, dsl_state, module)
    end
  end

  defp verify_kind(%{name: :table, editable: %{visible: nil}}, _key, _module), do: :ok
  defp verify_kind(%{name: :detail}, _key, _module), do: :ok

  defp verify_kind(%{name: :table}, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable, :visible],
       message:
         "table #{inspect(key)}'s editable block cannot declare visible: it gates a " <>
           ":detail card's editing"
     )}
  end

  defp verify_kind(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable],
       message:
         "component #{inspect(key)} cannot declare an editable block: editing in place " <>
           "is only supported on :table and :detail components"
     )}
  end

  defp verify_no_row_layout(%{row_layout: nil}, _key, _module), do: :ok

  defp verify_no_row_layout(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :editable],
       message:
         "table #{inspect(key)} cannot combine an editable block with a row_layout: " <>
           "card rows render read-only meta values"
     )}
  end

  defp verify_component_fields(component, key, module) do
    component_fields = component.fields || []

    case Enum.find(component.editable.fields, &(&1 not in component_fields)) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :editable, :fields],
           message:
             "editable field #{inspect(unknown)} is not one of #{component.name} " <>
               "#{inspect(key)}'s fields #{inspect(component_fields)}"
         )}
    end
  end

  defp verify_update_action(component, key, dsl_state, module) do
    case record_resource(component, dsl_state) do
      nil ->
        :ok

      resource ->
        action_name =
          component.editable.update_action || primary_update_name(resource)

        verify_action(component, key, action_name, resource, dsl_state, module)
    end
  end

  defp verify_action(component, key, action_name, resource, dsl_state, module) do
    case action_name && ResourceInfo.action(resource, action_name) do
      %{type: :update} = action ->
        with :ok <- verify_accepted_fields(component, key, action, dsl_state, module) do
          verify_visible(component, key, resource, module)
        end

      _missing_or_not_update ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :editable, :update_action],
           message:
             "editable update_action #{inspect(action_name)} is not an update action " <>
               "of #{inspect(resource_name(resource))}"
         )}
    end
  end

  defp verify_accepted_fields(component, key, action, dsl_state, module) do
    accepted =
      MapSet.new(List.wrap(Map.get(action, :accept)) ++ Enum.map(action.arguments, & &1.name))

    edits = edit_attributes(component, dsl_state)

    case Enum.find(component.editable.fields, &(not MapSet.member?(accepted, edits[&1]))) do
      nil ->
        :ok

      field ->
        shown = if edits[field] == field, do: "", else: " (edited as #{inspect(edits[field])})"

        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :editable, :fields],
           message:
             "editable field #{inspect(field)}#{shown} is not accepted by update action " <>
               "#{inspect(action.name)} (accepts/arguments: #{inspect(MapSet.to_list(accepted))})"
         )}
    end
  end

  # Each editable field with the attribute its input edits: a detail
  # field's `edit`, else the field itself.
  defp edit_attributes(%{name: :detail, editable: editable}, dsl_state) do
    declared =
      dsl_state
      |> Verifier.get_entities([:a2ui])
      |> Enum.filter(&is_struct(&1, AshA2ui.Field))
      |> Map.new(&{&1.name, &1.edit})

    Map.new(editable.fields, &{&1, declared[&1] || &1})
  end

  defp edit_attributes(%{editable: editable}, _dsl_state),
    do: Map.new(editable.fields, &{&1, &1})

  defp verify_visible(%{editable: %{visible: nil}}, _key, _resource, _module), do: :ok

  defp verify_visible(%{editable: %{visible: visible}}, key, resource, module) do
    if resource_field?(resource, visible) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :component, key, :editable, :visible],
         message:
           "editable visible #{inspect(visible)} is not an attribute, calculation or " <>
             "aggregate of #{inspect(resource_name(resource))}"
       )}
    end
  end

  defp resource_field?(resource, name) do
    not is_nil(
      ResourceInfo.attribute(resource, name) || ResourceInfo.calculation(resource, name) ||
        ResourceInfo.aggregate(resource, name)
    )
  end

  # The resource of the record an editable component edits: a table's
  # target, a detail card's context's resource.
  defp record_resource(%{name: :detail, context: context}, dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.find(&(is_struct(&1, AshA2ui.Context) and &1.name == context))
    |> case do
      %{resource: resource} when is_atom(resource) and not is_nil(resource) ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource

      _undeclared ->
        nil
    end
  end

  defp record_resource(_table, dsl_state), do: target_resource(dsl_state)

  defp primary_update_name(resource) do
    case primary_update(resource) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp primary_update(resource) when is_atom(resource),
    do: ResourceInfo.primary_action(resource, :update)

  defp primary_update(dsl_state), do: ResourceInfo.primary_action(dsl_state, :update)

  defp target_resource(dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
    end
  end

  defp resource_name(resource) when is_atom(resource), do: resource
  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
