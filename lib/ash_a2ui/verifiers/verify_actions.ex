defmodule AshA2ui.Verifiers.VerifyActions do
  @moduledoc """
  Verifies at compile time that every action referenced by a component exists
  on the resolved resource with a compatible type:

    * `read_action` must exist and be of type `:read`,
    * `create_action` must exist and be of type `:create`,
    * `update_action` must exist and be of type `:update`,
    * every entry in `row_actions` must exist (any type — destroy and generic
      actions are allowed),

  and that `action` entity metadata is sound against the resource:

    * `prompt_fields` may only be declared on actions listed in a table's
      `row_actions`, and every entry must be an argument or accepted
      attribute of the Ash action (the prompt values are cast against them),
    * `visible_when` may only be declared on row or bulk actions; its keys must be
      public attributes or public expression calculations, and its values
      must cast to the field's type (`nil` and per-member list values
      included),
    * `via` (host-delegated dispatch) may only be declared on row or bulk
      actions,
      and is mutually exclusive with `prompt_fields` — the prompt collects
      values cast against the direct Ash action, which `via` bypasses.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure. Skipped when no resource can be resolved (standalone
  UI module without `for_resource`) — `AshA2ui.Info.resource!/1` reports that
  at runtime.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @typed_options [read_action: :read, create_action: :create, update_action: :update]

  @impl true
  def verify(dsl_state) do
    case target_resource(dsl_state) do
      nil ->
        :ok

      target ->
        module = Verifier.get_persisted(dsl_state, :module)

        with :ok <- verify_components(dsl_state, target, module) do
          verify_action_settings(dsl_state, target, module)
        end
    end
  end

  defp verify_components(dsl_state, target, module) do
    dsl_state
    |> components()
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, target, module) do
    # A related table's read_action belongs to its own resource (it has no
    # row actions: VerifyComponents).
    target = AshA2ui.Component.resource(component, target)

    with :ok <- verify_typed_actions(component, target, module) do
      verify_row_actions(component, target, module)
    end
  end

  defp verify_typed_actions(component, target, module) do
    Enum.reduce_while(@typed_options, :ok, fn {option, type}, :ok ->
      case verify_typed_action(component, Map.fetch!(component, option), option, type,
             target: target,
             module: module
           ) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_typed_action(_component, nil, _option, _type, _ctx), do: :ok

  defp verify_typed_action(component, name, option, type, ctx) do
    case Info.action(ctx[:target], name) do
      nil ->
        {:error,
         DslError.exception(
           module: ctx[:module],
           path: [:a2ui, :component, component.name, option],
           message: "#{option} #{inspect(name)} does not exist on #{inspect(resource_name(ctx))}"
         )}

      %{type: ^type} ->
        :ok

      %{type: actual} ->
        {:error,
         DslError.exception(
           module: ctx[:module],
           path: [:a2ui, :component, component.name, option],
           message:
             "#{option} #{inspect(name)} must be of type #{inspect(type)}, " <>
               "but it is a #{inspect(actual)} action"
         )}
    end
  end

  defp verify_row_actions(component, target, module) do
    case Enum.find(component.row_actions, &is_nil(Info.action(target, &1))) do
      nil ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, component.name, :row_actions],
           message:
             "row action #{inspect(missing)} does not exist on " <>
               inspect(resource_name(target: target, module: module))
         )}
    end
  end

  # --- action entity metadata (prompt_fields / visible_when) -----------------

  defp verify_action_settings(dsl_state, target, module) do
    row_action_names =
      dsl_state
      |> components()
      |> Enum.flat_map(& &1.row_actions)
      |> MapSet.new()

    # Bulk actions take visible_when and via per record (VerifyBulkActions
    # refuses prompt_fields on them).
    per_record_names =
      dsl_state
      |> components()
      |> Enum.flat_map(& &1.bulk_actions)
      |> MapSet.new()
      |> MapSet.union(row_action_names)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, AshA2ui.Action))
    |> Enum.reduce_while(:ok, fn setting, :ok ->
      case verify_action_setting(setting, {row_action_names, per_record_names}, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_action_setting(setting, {row_action_names, per_record_names}, target, module) do
    with :ok <- verify_row_action_only(setting, :prompt_fields, row_action_names, module),
         :ok <- verify_row_action_only(setting, :visible_when, per_record_names, module),
         :ok <- verify_row_action_only(setting, :via, per_record_names, module),
         :ok <- verify_via_exclusivity(setting, module),
         :ok <- verify_prompt_fields(setting, target, module) do
      verify_visible_when(setting, target, module)
    end
  end

  defp verify_row_action_only(setting, option, row_action_names, module) do
    if Map.fetch!(setting, option) in [nil, []] or MapSet.member?(row_action_names, setting.name) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:a2ui, :action, setting.name, option],
         message:
           "action #{inspect(setting.name)} declares #{option}, but it is not listed in " <>
             "any table's row_actions — #{option} only applies to row actions"
       )}
    end
  end

  # `via` reroutes the dispatch away from the direct Ash invocation;
  # prompt_fields configures exactly that invocation (its Modal values are
  # cast against the Ash action), so the two cannot coexist.
  defp verify_via_exclusivity(%{via: nil}, _module), do: :ok

  defp verify_via_exclusivity(%{prompt_fields: []}, _module), do: :ok

  defp verify_via_exclusivity(setting, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :action, setting.name, :via],
       message:
         "action #{inspect(setting.name)} declares both via and prompt_fields — they are " <>
           "mutually exclusive: prompt_fields collects values for the direct Ash action, " <>
           "which via bypasses"
     )}
  end

  # Prompt values are cast against the Ash action's arguments and accepted
  # attributes, so every prompt field must be one of them.
  defp verify_prompt_fields(%{prompt_fields: []}, _target, _module), do: :ok

  defp verify_prompt_fields(setting, target, module) do
    case Info.action(target, setting.name) do
      nil ->
        # Missing actions are reported by verify_row_actions.
        :ok

      action ->
        known =
          MapSet.new(Enum.map(action.arguments, & &1.name) ++ List.wrap(Map.get(action, :accept)))

        case Enum.find(setting.prompt_fields, &(not MapSet.member?(known, &1))) do
          nil ->
            :ok

          unknown ->
            {:error,
             DslError.exception(
               module: module,
               path: [:a2ui, :action, setting.name, :prompt_fields],
               message:
                 "prompt field #{inspect(unknown)} is neither an argument nor an accepted " <>
                   "attribute of action #{inspect(setting.name)} " <>
                   "(known: #{inspect(MapSet.to_list(known))})"
             )}
        end
    end
  end

  defp verify_visible_when(%{visible_when: []}, _target, _module), do: :ok

  defp verify_visible_when(setting, target, module) do
    Enum.reduce_while(setting.visible_when, :ok, fn {key, value}, :ok ->
      case verify_condition(setting, key, value, target, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # visible_when keys follow the same rules as query filters: public
  # attributes or expression-backed public calculations (the calc must be
  # loadable to evaluate the condition on fetched records).
  defp verify_condition(setting, key, value, target, module) do
    field =
      public_attribute(target, key) ||
        (expression_calculation?(target, key) && Info.public_calculation(target, key))

    cond do
      !field ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :action, setting.name, :visible_when],
           message:
             "visible_when key #{inspect(key)} on action #{inspect(setting.name)} must be " <>
               "a public attribute or an expression-backed public calculation of the resource"
         )}

      not castable_condition?(field, value) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :action, setting.name, :visible_when],
           message:
             "visible_when value #{inspect(value)} for #{inspect(key)} on action " <>
               "#{inspect(setting.name)} does not cast to the field's type"
         )}

      true ->
        :ok
    end
  end

  defp public_attribute(target, key) do
    case Info.attribute(target, key) do
      %{public?: true} = attribute -> attribute
      _private_or_missing -> nil
    end
  end

  # The same expression-backed requirement generic sorting has, so
  # `sortable?/3` doubles as the check.
  defp expression_calculation?(target, key) do
    not is_nil(Info.public_calculation(target, key)) and
      Info.sortable?(target, key, include_private?: false)
  end

  defp castable_condition?(_field, nil), do: true

  defp castable_condition?(field, values) when is_list(values) do
    Enum.all?(values, &castable_condition?(field, &1))
  end

  defp castable_condition?(field, value) do
    with {:ok, cast} <- Ash.Type.cast_input(field.type, value, field.constraints),
         {:ok, _cast} <- Ash.Type.apply_constraints(field.type, cast, field.constraints) do
      true
    else
      _error -> false
    end
  end

  # For on-resource mode the target is the DSL state map; name the module
  # being compiled instead.
  defp resource_name(ctx) do
    case ctx[:target] do
      target when is_atom(target) -> target
      _dsl_state -> ctx[:module]
    end
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
