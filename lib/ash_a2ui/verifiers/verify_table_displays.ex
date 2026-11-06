defmodule AshA2ui.Verifiers.VerifyTableDisplays do
  @moduledoc """
  Verifies at compile time that timelines (`display :timeline`, see
  `AshA2ui.Timeline`) and matrices (`display :matrix`, see
  `AshA2ui.Matrix`) are sound. The rules are `AshA2ui.Timeline.validate/2`
  and `AshA2ui.Matrix.validate/2`, shared with composed surfaces
  (`AshA2ui.Dynamic` runs this verifier over every spec).

  Attribute checks are skipped when the table's resource cannot be resolved
  at verification time (cross-module compile ordering), matching the other
  verifiers.
  """

  use Spark.Dsl.Verifier

  alias AshA2ui.Component
  alias AshA2ui.Verifiers.VerifyCalendar
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, Component))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      resource = VerifyCalendar.table_resource(component, dsl_state)

      with :ok <- AshA2ui.Timeline.validate(component, resource),
           :ok <- AshA2ui.Matrix.validate(component, resource) do
        {:cont, :ok}
      else
        {:error, option, message} -> {:halt, error(component, module, option, message)}
      end
    end)
  end

  defp error(component, module, option, message) do
    key = Component.key(component)

    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, option],
       message: "component #{inspect(key)}: #{message}"
     )}
  end
end
