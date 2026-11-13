defmodule AshA2ui.Verifiers.VerifyTableDisplays do
  @moduledoc """
  Verifies at compile time that a table's card header and caption
  (`heading`, `description`) stay on tables, that list rows and cards have a
  row layout, and that timelines (`display :timeline`, see
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

      with :ok <- validate_rows(component),
           :ok <- validate_card_header(component),
           :ok <- AshA2ui.Timeline.validate(component, resource),
           :ok <- AshA2ui.Matrix.validate(component, resource) do
        {:cont, :ok}
      else
        {:error, option, message} -> {:halt, error(component, module, option, message)}
      end
    end)
  end

  # List rows and cards draw their records from a row layout.
  defp validate_rows(%Component{display: display, row_layout: nil})
       when display in [:rows, :cards],
       do: {:error, :display, "display #{inspect(display)} requires a row_layout"}

  defp validate_rows(_component), do: :ok

  # A card header and caption head a table's own card; a board lane has none.
  defp validate_card_header(%Component{} = component) do
    problem =
      cond do
        component.name != :table -> "is for tables: it heads the table's card"
        component.display == :board -> "is not drawn on a board lane: it has no card"
        true -> nil
      end

    case problem && Enum.find([:heading, :description], &Map.get(component, &1)) do
      option when option in [:heading, :description] ->
        {:error, option, "#{option} #{problem}"}

      _none ->
        :ok
    end
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
