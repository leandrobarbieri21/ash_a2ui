defmodule AshA2ui.Verifiers.VerifyExport do
  @moduledoc """
  Verifies at compile time that `export` blocks (CSV file export) are sound:

    * only `:table` and `:report` components may declare an `export` block,
    * declared `columns` are a subset of the component's declared `fields`
      (when both are declared — inferred table fields degrade gracefully).

  Raises `Spark.Error.DslError` (surfaced by Spark as a compile-time
  diagnostic) on failure.
  """

  use Spark.Dsl.Verifier

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
    |> Enum.filter(& &1.export)
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case verify_component(component, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(component, module) do
    key = AshA2ui.Component.key(component)

    with :ok <- verify_kind(component, key, module) do
      verify_columns(component, key, module)
    end
  end

  defp verify_kind(%{name: kind}, _key, _module) when kind in [:table, :report], do: :ok

  defp verify_kind(_component, key, module) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :component, key, :export],
       message:
         "component #{inspect(key)} cannot declare an export block: CSV export is only " <>
           "supported on :table and :report components"
     )}
  end

  defp verify_columns(%{export: %{columns: nil}}, _key, _module), do: :ok
  defp verify_columns(%{fields: nil}, _key, _module), do: :ok

  defp verify_columns(component, key, module) do
    case Enum.find(component.export.columns, &(&1 not in component.fields)) do
      nil ->
        :ok

      unknown ->
        {:error,
         DslError.exception(
           module: module,
           path: [:a2ui, :component, key, :export, :columns],
           message:
             "export column #{inspect(unknown)} is not one of component #{inspect(key)}'s " <>
               "fields #{inspect(component.fields)}"
         )}
    end
  end
end
