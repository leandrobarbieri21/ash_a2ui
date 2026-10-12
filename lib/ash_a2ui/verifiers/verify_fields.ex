defmodule AshA2ui.Verifiers.VerifyFields do
  @moduledoc """
  Verifies at compile time that:

    * every component field (declared or inferred) and every `field` override
      name is a public attribute, calculation, or aggregate of the resolved
      resource — a related table's (`resource`) fields of its own resource,
    * `:form` component fields never name a calculation or aggregate (they
      are not writable — table-only), and
    * `:form` component fields are a subset of the accepts + argument names of
      the form's create/update action(s).

  Fields declared with a `source`, `relationship`, `link` or `links` option
  are exempt from both checks here — `AshA2ui.Verifiers.VerifyRelationships` validates them
  against the relationship graph instead.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)
        known = known_field_names(target)
        exempt = relationship_field_names(dsl_state)

        with :ok <- verify_components(dsl_state, target, module, known, exempt) do
          # A field override may style a related table's column too.
          known =
            dsl_state
            |> related_resources(target)
            |> Enum.reduce(known, &MapSet.union(&2, known_field_names(&1)))

          verify_field_overrides(dsl_state, module, known, exempt)
        end
    end
  end

  # Field entities carrying a `source`, `relationship`, `link` or `links`
  # option name virtual columns / relationship selects / reference links
  # rather than resource fields; they are validated by VerifyRelationships.
  defp relationship_field_names(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(
      &(is_struct(&1, AshA2ui.Field) and (&1.source || &1.relationship || &1.link || &1.links))
    )
    |> MapSet.new(& &1.name)
  end

  defp verify_components(dsl_state, target, module, known, exempt) do
    dsl_state
    |> components()
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, target, module, known, exempt) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # :detail components render their CONTEXT's resource, not the surface's —
  # AshA2ui.Verifiers.VerifyContexts validates their fields instead.
  defp verify_component(%AshA2ui.Component{name: :detail}, _target, _module, _known, _exempt),
    do: :ok

  # :report fields are keys of the generic action's returned row maps, not
  # resource fields — AshA2ui.Verifiers.VerifyReports validates the report
  # shape instead.
  defp verify_component(%AshA2ui.Component{name: :report}, _target, _module, _known, _exempt),
    do: :ok

  # A related table's fields belong to its own resource.
  defp verify_component(
         %AshA2ui.Component{name: :table} = component,
         target,
         module,
         _known,
         exempt
       )
       when not is_nil(component.resource) and component.resource != target do
    if Code.ensure_loaded?(component.resource) and Info.resource?(component.resource),
      do: verify_known_fields(component, module, known_field_names(component.resource), exempt),
      else: :ok
  end

  defp verify_component(component, target, module, known, exempt) do
    with :ok <- verify_known_fields(component, module, known, exempt) do
      verify_form_fields(component, target, module, exempt)
    end
  end

  defp verify_known_fields(component, module, known, exempt) do
    case Enum.find(component.fields || [], &(&1 not in known and &1 not in exempt)) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, component.name, :fields],
           message: """
           component #{inspect(component.name)} references unknown field #{inspect(unknown)}.

           Every field must be a public attribute, calculation, or aggregate of the resource. \
           Available fields: #{inspect(MapSet.to_list(known))}
           """
         )}
    end
  end

  defp verify_form_fields(%AshA2ui.Component{name: :form} = component, target, module, exempt) do
    with :ok <- verify_form_fields_writable(component, target, module) do
      verify_form_fields_accepted(component, target, module, exempt)
    end
  end

  defp verify_form_fields(_component, _target, _module, _exempt), do: :ok

  # Calculations and aggregates are read-only projections — rendering them as
  # form inputs would emit a wire contract the action can never accept.
  defp verify_form_fields_writable(component, target, module) do
    case Enum.find(component.fields || [], &calculation_or_aggregate(target, &1)) do
      nil ->
        :ok

      rejected ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, :form, :fields],
           message:
             "component :form field #{inspect(rejected)} is " <>
               "#{calculation_or_aggregate(target, rejected)} — calculations and " <>
               "aggregates are not writable and cannot be form fields (render them as " <>
               "table columns instead)"
         )}
    end
  end

  defp calculation_or_aggregate(target, name) do
    cond do
      not is_nil(Info.public_calculation(target, name)) -> "a calculation"
      not is_nil(Info.public_aggregate(target, name)) -> "an aggregate"
      true -> nil
    end
  end

  defp verify_form_fields_accepted(component, target, module, exempt) do
    case form_inputs(target, component) do
      nil ->
        :ok

      allowed ->
        case Enum.find(component.fields || [], &(&1 not in allowed and &1 not in exempt)) do
          nil ->
            :ok

          rejected ->
            {:error,
             DslError.exception(
               module: module,
               path: [:a2ui, :component, :form, :fields],
               message: """
               component :form field #{inspect(rejected)} is not accepted by its create/update action(s).

               Form fields must be in the accepts or arguments of the form's actions. \
               Allowed fields: #{inspect(MapSet.to_list(allowed))}
               """
             )}
        end
    end
  end

  defp verify_field_overrides(dsl_state, module, known, exempt) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Field))
    |> Enum.reduce_while(:ok, fn field, :ok ->
      if field.name in known or field.name in exempt do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:a2ui, :field, field.name],
            message: """
            field #{inspect(field.name)} does not exist on the resource.

            Every field override must name a public attribute, calculation, or aggregate. \
            Available fields: #{inspect(MapSet.to_list(known))}
            """
          )}}
      end
    end)
  end

  # The accepts + argument names of the form's create/update action(s), or
  # `nil` when neither action resolves (VerifyActions reports missing/mistyped
  # actions).
  defp form_inputs(target, component) do
    [
      form_action(target, component.create_action, :create),
      form_action(target, component.update_action, :update)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      actions ->
        actions
        |> Enum.flat_map(fn action ->
          action.accept ++ Enum.map(action.arguments, & &1.name)
        end)
        |> MapSet.new()
    end
  end

  defp form_action(target, nil, type), do: Info.primary_action(target, type)

  defp form_action(target, name, type) do
    case Info.action(target, name) do
      %{type: ^type} = action -> action
      _ -> nil
    end
  end

  defp components(dsl_state) do
    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Component))
  end

  defp related_resources(dsl_state, target) do
    for %AshA2ui.Component{name: :table, resource: resource} <- components(dsl_state),
        not is_nil(resource) and resource != target,
        Code.ensure_loaded?(resource) and Info.resource?(resource),
        uniq: true,
        do: resource
  end

  defp known_field_names(target) do
    [
      Info.public_attributes(target),
      Info.public_calculations(target),
      Info.public_aggregates(target)
    ]
    |> Enum.concat()
    |> MapSet.new(& &1.name)
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
