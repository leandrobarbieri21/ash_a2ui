defmodule AshA2ui.Verifiers.VerifyCalendar do
  @moduledoc """
  Verifies at compile time that calendars (`display :calendar`, see
  `AshA2ui.Calendar`) are sound. The rules are `AshA2ui.Calendar.validate/2`,
  shared with composed surfaces (`AshA2ui.Dynamic` runs this verifier over
  every spec):

    * `display :calendar` appears only on `:table` components,
    * a calendar declares a `date_field` and a `query` (the window rides on
      the table's query),
    * `date_field` and `end_date_field` are public `:date` or datetime
      attributes of the table's resource (the surface resource, or a related
      table's `resource`), and are not the same attribute,
    * `granularity` is one of `AshA2ui.Calendar.granularities/0` (the DSL
      schema enforces it too),
    * a calendar declares no `sections` and no `bulk_actions`,
    * `date_field`, `end_date_field` and `granularity` are declared only with
      `display :calendar`.

  Attribute checks are skipped when the table's resource cannot be resolved
  at verification time (cross-module compile ordering), matching the other
  verifiers.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Component
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:a2ui])
    |> Enum.filter(&is_struct(&1, Component))
    |> Enum.reduce_while(:ok, fn component, :ok ->
      case AshA2ui.Calendar.validate(component, table_resource(component, dsl_state)) do
        :ok -> {:cont, :ok}
        {:error, option, message} -> {:halt, error(component, module, option, message)}
      end
    end)
  end

  # The resource a table reads: a related table's `resource`, else the
  # surface's (`for_resource` in a standalone module, the resource itself
  # otherwise). `nil` when it cannot be resolved yet.
  defp table_resource(%{resource: resource}, _dsl_state) when not is_nil(resource) do
    if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
  end

  defp table_resource(_component, dsl_state) do
    case Verifier.get_option(dsl_state, [:a2ui], :for_resource) do
      nil ->
        if Ash.Resource.Dsl in Verifier.get_persisted(dsl_state, :extensions, []),
          do: dsl_state

      resource ->
        if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource), do: resource
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
