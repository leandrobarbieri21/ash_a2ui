defmodule AshA2ui.Verifiers.VerifySteps do
  @moduledoc """
  Verifies at compile time that wizard `step` declarations are sound:

    * `step` entities appear only on `:form` components,
    * a stepped form declares at least two steps, with unique names,
    * `review?` is allowed only on the last step, and only without `fields`;
      every other step declares at least one field,
    * every step field is one of the form's fields, and every form field
      belongs to exactly one step (none unassigned, none claimed twice),
    * steps are not mixed with `group` or `nested_form` entities on one form
      (groups and nested rows inside steps are a later item).

  Field-membership checks run against the component's field list as filled
  in by `AshA2ui.Transformers.InferFields`; components whose fields could
  not be resolved (standalone modules without a compilable `for_resource`)
  skip them.

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&match?(%AshA2ui.Component{steps: [_ | _]}, &1))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, module) do
    with :ok <- verify_placement(component, module),
         :ok <- verify_not_mixed(component, module),
         :ok <- verify_count(component, module),
         :ok <- verify_unique_names(component, module),
         :ok <- verify_review(component, module),
         :ok <- verify_fields_present(component, module),
         :ok <- verify_fields_known(component, module),
         :ok <- verify_fields_disjoint(component, module) do
      verify_fields_covered(component, module)
    end
  end

  defp verify_placement(%{name: :form}, _module), do: :ok

  defp verify_placement(component, module) do
    {:error,
     error(module, [:a2ui, :component, component.name],
       message:
         "component #{inspect(component.name)} declares a step: " <>
           "`step` entities are only supported on :form components"
     )}
  end

  defp verify_not_mixed(%{groups: [_ | _]}, module) do
    {:error,
     error(module, [:a2ui, :component, :form, :step],
       message:
         "the form declares both `step` and `group` entities: steps and groups cannot " <>
           "be mixed on one form (put the fields in steps)"
     )}
  end

  defp verify_not_mixed(%{nested_forms: [_ | _]}, module) do
    {:error,
     error(module, [:a2ui, :component, :form, :step],
       message:
         "the form declares both `step` and `nested_form` entities: nested forms are " <>
           "not supported on stepped forms"
     )}
  end

  defp verify_not_mixed(_component, _module), do: :ok

  defp verify_count(%{steps: [_single]}, module) do
    {:error,
     error(module, [:a2ui, :component, :form, :step],
       message: "the form declares a single step: a stepped form needs at least two steps"
     )}
  end

  defp verify_count(_component, _module), do: :ok

  defp verify_unique_names(component, module) do
    component.steps
    |> Enum.frequencies_by(& &1.name)
    |> Enum.find(fn {_name, count} -> count > 1 end)
    |> case do
      nil ->
        :ok

      {name, _count} ->
        {:error,
         error(module, [:a2ui, :component, :form, :step, name],
           message: "duplicate step #{inspect(name)}: step names must be unique within a form"
         )}
    end
  end

  defp verify_review(component, module) do
    last = List.last(component.steps)

    case Enum.find(component.steps, & &1.review?) do
      nil ->
        :ok

      %{name: name, fields: [_ | _]} ->
        {:error,
         error(module, [:a2ui, :component, :form, :step, name],
           message: "review step #{inspect(name)} declares fields: a review? step has no fields"
         )}

      %{name: name} = step when step != last ->
        {:error,
         error(module, [:a2ui, :component, :form, :step, name],
           message: "review step #{inspect(name)} is not the last step: review? must be last"
         )}

      _last_review ->
        :ok
    end
  end

  defp verify_fields_present(component, module) do
    case Enum.find(component.steps, &(not &1.review? and &1.fields == [])) do
      nil ->
        :ok

      step ->
        {:error,
         error(module, [:a2ui, :component, :form, :step, step.name],
           message: "step #{inspect(step.name)} declares no fields"
         )}
    end
  end

  defp verify_fields_known(%{fields: nil}, _module), do: :ok

  defp verify_fields_known(component, module) do
    known = MapSet.new(component.fields)

    Enum.reduce_while(component.steps, :ok, fn step, :ok ->
      case Enum.find(step.fields, &(not MapSet.member?(known, &1))) do
        nil ->
          {:cont, :ok}

        unknown ->
          {:halt,
           {:error,
            error(module, [:a2ui, :component, :form, :step, step.name],
              message: """
              step #{inspect(step.name)} references field #{inspect(unknown)}, which is not \
              one of the form's fields.

              Every step field must be in the form component's (declared or inferred) \
              fields list: #{inspect(component.fields)}
              """
            )}}
      end
    end)
  end

  defp verify_fields_disjoint(component, module) do
    component.steps
    |> Enum.flat_map(fn step -> Enum.map(step.fields, &{&1, step.name}) end)
    |> Enum.group_by(fn {field, _step} -> field end, fn {_field, step} -> step end)
    |> Enum.find(fn {_field, steps} -> length(steps) > 1 end)
    |> case do
      nil ->
        :ok

      {field, steps} ->
        {:error,
         error(module, [:a2ui, :component, :form, :step],
           message:
             "field #{inspect(field)} belongs to more than one step " <>
               "(#{inspect(steps)}): every form field belongs to exactly one step"
         )}
    end
  end

  defp verify_fields_covered(%{fields: nil}, _module), do: :ok

  defp verify_fields_covered(component, module) do
    assigned = component.steps |> Enum.flat_map(& &1.fields) |> MapSet.new()

    case Enum.reject(component.fields, &MapSet.member?(assigned, &1)) do
      [] ->
        :ok

      unassigned ->
        {:error,
         error(module, [:a2ui, :component, :form, :step],
           message:
             "form field(s) #{inspect(unassigned)} belong to no step: every form field " <>
               "belongs to exactly one step"
         )}
    end
  end

  defp error(module, path, opts) do
    DslError.exception([module: module, path: path] ++ opts)
  end
end
