defmodule AshA2ui.Verifiers.VerifyPrimaryAction do
  @moduledoc """
  Verifies at compile time that `primary_action` declarations are sound:

    * `primary_action` appears only on `:table` components,
    * the table has a row click to draw: a `select_context`, or a `:form`
      component on the surface with the table reading the surface's own
      resource (the View task),
    * `label_from` is a public attribute, calculation or aggregate of the
      table's resource,
    * `labels` and `variants` are declared only alongside `label_from`,
      `labels` values are strings and `variants` values are
      `AshA2ui.PrimaryAction.variants/0`.

  Skipped for the resource checks when no resource can be resolved
  (standalone UI module without a compilable `for_resource`).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshA2ui.PrimaryAction
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    components = components(dsl_state)
    form? = Enum.any?(components, &(&1.name == :form))
    target = target_resource(dsl_state)

    components
    |> Enum.filter(& &1.primary_action)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, form?, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, form?, target, module) do
    key = AshA2ui.Component.key(component)
    action = component.primary_action

    with :ok <- verify_table(component, key, module),
         :ok <- verify_row_click(component, form?, key, module),
         :ok <- verify_mappings(action, key, module) do
      verify_label_from(action, component, target, key, module)
    end
  end

  defp verify_table(%{name: :table}, _key, _module), do: :ok

  defp verify_table(_component, key, module) do
    error(
      module,
      key,
      "component #{inspect(key)} declares a primary_action: `primary_action` is only " <>
        "supported on :table components"
    )
  end

  # The primary action IS the row click; a table without one has nothing to
  # draw.
  defp verify_row_click(%{select_context: context}, _form?, _key, _module)
       when not is_nil(context),
       do: :ok

  defp verify_row_click(%{resource: nil}, true, _key, _module), do: :ok

  defp verify_row_click(_component, _form?, key, module) do
    error(
      module,
      key,
      "table #{inspect(key)} declares a primary_action but has no row click to draw: " <>
        "declare `select_context`, or a :form component on the surface (the View task " <>
        "of a table over the surface's own resource)"
    )
  end

  defp verify_mappings(%{label_from: nil, labels: labels, variants: variants}, key, module)
       when labels != [] or variants != [] do
    error(
      module,
      key,
      "the primary_action of table #{inspect(key)} declares labels or variants without " <>
        "label_from: they are picked by the label_from field's value"
    )
  end

  defp verify_mappings(action, key, module) do
    cond do
      not Enum.all?(action.labels, fn {_value, label} -> is_binary(label) end) ->
        error(
          module,
          key,
          "the primary_action of table #{inspect(key)} has a non-string label in " <>
            "labels: #{inspect(action.labels)}"
        )

      not Enum.all?(action.variants, fn {_value, variant} ->
        variant in PrimaryAction.variants()
      end) ->
        error(
          module,
          key,
          "the primary_action of table #{inspect(key)} has an unknown variant in " <>
            "variants: #{inspect(action.variants)} (variants are " <>
            "#{inspect(PrimaryAction.variants())})"
        )

      true ->
        :ok
    end
  end

  defp verify_label_from(%{label_from: nil}, _component, _target, _key, _module), do: :ok
  defp verify_label_from(_action, _component, nil, _key, _module), do: :ok

  defp verify_label_from(action, component, target, key, module) do
    resource = AshA2ui.Component.resource(component, target)
    name = action.label_from

    if public_field?(resource, name) do
      :ok
    else
      error(
        module,
        key,
        "the primary_action of table #{inspect(key)} has label_from #{inspect(name)}, which " <>
          "is not a public attribute, calculation or aggregate of the table's resource"
      )
    end
  end

  defp public_field?(resource, name) do
    Enum.any?(
      [
        Info.public_attribute(resource, name),
        Info.public_calculation(resource, name),
        Info.public_aggregate(resource, name)
      ],
      & &1
    )
  end

  defp error(module, key, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :primary_action],
       message: message
     )}
  end

  defp components(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
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
