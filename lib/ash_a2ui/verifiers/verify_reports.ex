defmodule AshA2ui.Verifiers.VerifyReports do
  @moduledoc """
  Verifies at compile time that `:report` components (aggregate/report
  queries) are sound:

    * every `:report` declares an `action` and a non-empty `fields` list
      (the column allowlist — report columns are row-map keys and cannot be
      inferred),
    * the `action` / `params` options are only used on `:report` components,
    * a `:report` declares none of the table/form options
      (`read_action` / `create_action` / `update_action` / `row_actions` /
      `query` / context scoping / `sections` / `editable`),
    * when the target resource is resolvable: the `action` is a generic
      (`:action`-type) Ash action and every `params` entry names one of its
      arguments.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Resource-dependent checks degrade gracefully when
  the target cannot be resolved at verification time, matching the other
  verifiers.
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

    with :ok <- verify_report_options_placement(components, module) do
      components
      |> Enum.filter(&(&1.name == :report))
      |> Enum.reduce_while(:ok, &reduce_report(&1, &2, dsl_state, module))
    end
  end

  defp reduce_report(component, :ok, dsl_state, module) do
    case verify_report(component, dsl_state, module) do
      :ok -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp verify_report_options_placement(components, module) do
    case Enum.find(
           components,
           &(&1.name != :report and (&1.action || &1.params || &1.param_placeholders))
         ) do
      nil ->
        :ok

      component ->
        key = AshA2ui.Component.key(component)

        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key],
           message:
             "component #{inspect(key)} cannot declare `action`/`params`/`param_placeholders`: they are " <>
               ":report component options"
         )}
    end
  end

  defp verify_report(component, dsl_state, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_required(component, key, module),
         :ok <- verify_no_foreign_options(component, key, module) do
      verify_action(component, key, dsl_state, module)
    end
  end

  defp verify_required(component, key, module) do
    cond do
      is_nil(component.action) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :action],
           message: "report #{inspect(key)} must declare the generic `action` it runs"
         )}

      component.fields in [nil, []] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :fields],
           message:
             "report #{inspect(key)} must declare its `fields` (the column allowlist — " <>
               "report columns are keys of the returned row maps and cannot be inferred)"
         )}

      true ->
        :ok
    end
  end

  @foreign_options [
    :read_action,
    :create_action,
    :update_action,
    :query,
    :select_context,
    :context,
    :row_layout,
    :sections,
    :editable
  ]

  defp verify_no_foreign_options(component, key, module) do
    declared_lists =
      Enum.filter(
        [:row_actions, :context_filter, :require_context],
        &(Map.get(component, &1) != [])
      )

    case Enum.find(@foreign_options, &Map.get(component, &1)) || List.first(declared_lists) do
      nil ->
        :ok

      option ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, option],
           message:
             "report #{inspect(key)} cannot declare #{inspect(option)}: reports render " <>
               "computed rows of a generic action, not resource records"
         )}
    end
  end

  defp verify_action(component, key, dsl_state, module) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      resource ->
        case ResourceInfo.action(resource, component.action) do
          %{type: :action} = action ->
            verify_params(component, key, action, module)

          _missing_or_not_generic ->
            {:error,
             DslError.exception(
               module: module,
               path: [:a2ui, :component, key, :action],
               message:
                 "report action #{inspect(component.action)} is not a generic " <>
                   "(action-type) action of #{inspect(resource_name(resource))}"
             )}
        end
    end
  end

  defp verify_params(%{params: nil} = component, key, action, module),
    do: verify_placeholders(component, key, Enum.map(action.arguments, & &1.name), module)

  defp verify_params(component, key, action, module) do
    argument_names = MapSet.new(action.arguments, & &1.name)

    case Enum.find(component.params, &(not MapSet.member?(argument_names, &1))) do
      nil ->
        verify_placeholders(component, key, component.params, module)

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :params],
           message:
             "report param #{inspect(unknown)} is not an argument of action " <>
               "#{inspect(action.name)} (arguments: #{inspect(MapSet.to_list(argument_names))})"
         )}
    end
  end

  defp verify_placeholders(%{param_placeholders: nil}, _key, _params, _module), do: :ok

  defp verify_placeholders(component, key, params, module) do
    case Enum.find(Keyword.keys(component.param_placeholders), &(&1 not in params)) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :param_placeholders],
           message:
             "report param_placeholders names #{inspect(unknown)}, which is not one of " <>
               "the component's params (#{inspect(params)})"
         )}
    end
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

  defp resource_name(resource) when is_atom(resource), do: resource
  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)
end
