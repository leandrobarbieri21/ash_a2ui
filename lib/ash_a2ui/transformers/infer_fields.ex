defmodule AshA2ui.Transformers.InferFields do
  @moduledoc """
  Fills in `fields` for components that omit them:

    * `:table` components get the resource's public attributes (via
      `Ash.Resource.Info.public_attributes/1`), in declaration order,
      excluding primary key attributes — a related table's (`resource`)
      own resource's.
    * `:form` components get the create action's `accept` list (the
      component's `create_action` if set, otherwise the primary create),
      falling back to the update action's accepts when no create action
      matches.
    * `:detail` components get the **context's** resource's public
      attributes (details render the record selected into their `context`,
      which may be a different resource than the surface's).

  In standalone UI modules the target resource is the section's
  `for_resource`. When inference is impossible (no resolvable resource, no
  matching action, or no public attributes), `fields` is left as `nil` for
  verifiers/runtime to handle.

  Runs after all other transformers (`after?/1` returns `true`) so Ash has
  already expanded default actions and `accept :*` lists before inference.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Info
  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    target = target_resource(dsl_state)

    dsl_state
    |> Transformer.get_entities([:a2ui])
    |> Enum.filter(&(is_struct(&1, AshA2ui.Component) and is_nil(&1.fields)))
    |> Enum.reduce({:ok, dsl_state}, fn component, {:ok, dsl_state} ->
      case infer_fields(infer_target(target, component, dsl_state), component) do
        nil ->
          {:ok, dsl_state}

        fields ->
          {:ok,
           Transformer.replace_entity(
             dsl_state,
             [:a2ui],
             %{component | fields: fields},
             &(is_struct(&1, AshA2ui.Component) and &1.name == component.name and
                 &1.as == component.as and is_nil(&1.fields))
           )}
      end
    end)
  end

  # `:detail` components infer against the context's resource — details may
  # render a different resource than the surface's.
  defp infer_target(_target, %AshA2ui.Component{name: :detail} = component, dsl_state) do
    dsl_state
    |> Transformer.get_entities([:a2ui])
    |> Enum.find_value(fn
      %AshA2ui.Context{name: name, resource: resource} when name == component.context ->
        Code.ensure_loaded?(resource) and Info.resource?(resource) and resource

      _other ->
        nil
    end)
    |> case do
      resource when is_atom(resource) and resource not in [nil, false] -> resource
      _missing -> nil
    end
  end

  # A related table (`resource` on the component) infers against its own
  # resource.
  defp infer_target(_target, %AshA2ui.Component{name: :table, resource: resource}, _dsl_state)
       when not is_nil(resource) do
    if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
  end

  defp infer_target(target, _component, _dsl_state), do: target

  # Resolves what we introspect against: the compiled `for_resource` module in
  # standalone mode, or the in-flight DSL state itself in on-resource mode
  # (`Ash.Resource.Info` accepts both). Returns `nil` when nothing usable.
  defp target_resource(dsl_state) do
    case Transformer.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if ash_resource_dsl?(dsl_state), do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and Info.resource?(resource), do: resource
    end
  end

  defp ash_resource_dsl?(dsl_state) do
    Ash.Resource.Dsl in Transformer.get_persisted(dsl_state, :extensions, [])
  end

  defp infer_fields(nil, _component), do: nil

  # :report fields are row-map keys, not resource fields — they cannot be
  # inferred (VerifyReports requires them explicitly).
  defp infer_fields(_target, %AshA2ui.Component{name: :report}), do: nil

  defp infer_fields(target, %AshA2ui.Component{name: :detail}) do
    infer_fields(target, %AshA2ui.Component{name: :table})
  end

  defp infer_fields(target, %AshA2ui.Component{name: :table}) do
    target
    |> Info.public_attributes()
    |> Enum.reject(& &1.primary_key?)
    |> Enum.map(& &1.name)
    |> case do
      [] -> nil
      fields -> fields
    end
  end

  defp infer_fields(target, %AshA2ui.Component{name: :form} = component) do
    action =
      form_action(target, component.create_action, :create) ||
        form_action(target, component.update_action, :update)

    action && action.accept
  end

  defp form_action(target, nil, type), do: Info.primary_action(target, type)

  defp form_action(target, name, type) do
    case Info.action(target, name) do
      %{type: ^type} = action -> action
      _ -> nil
    end
  end
end
