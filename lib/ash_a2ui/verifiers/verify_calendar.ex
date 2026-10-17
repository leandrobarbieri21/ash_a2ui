defmodule AshA2ui.Verifiers.VerifyCalendar do
  @moduledoc """
  Verifies at compile time that calendars (`display :calendar`, see
  `AshA2ui.Calendar`) are sound:

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
      case verify_component(component, dsl_state, module) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp verify_component(%{display: :calendar} = component, dsl_state, module) do
    with :ok <- verify_table(component, module),
         :ok <- verify_required(component, module),
         :ok <- verify_granularity(component, module),
         :ok <- verify_compatible(component, module) do
      verify_fields(component, table_resource(component, dsl_state), module)
    end
  end

  defp verify_component(component, _dsl_state, module) do
    case Enum.find([:date_field, :end_date_field, :granularity], &Map.get(component, &1)) do
      nil ->
        :ok

      option ->
        error(
          component,
          module,
          option,
          "#{option} is only supported with display :calendar"
        )
    end
  end

  defp verify_table(%{name: :table}, _module), do: :ok

  defp verify_table(component, module) do
    error(component, module, :display, "display :calendar is only supported on :table components")
  end

  defp verify_required(%{date_field: nil} = component, module) do
    error(
      component,
      module,
      :display,
      "display :calendar needs a date_field: the date or datetime attribute that places " <>
        "each record on the calendar"
    )
  end

  defp verify_required(%{query: nil} = component, module) do
    error(
      component,
      module,
      :query,
      "display :calendar needs a query: the visible window is read through the table's " <>
        "query (its page size bounds the records shown per window)"
    )
  end

  defp verify_required(_component, _module), do: :ok

  defp verify_granularity(%{granularity: granularity} = component, module) do
    if is_nil(granularity) or granularity in AshA2ui.Calendar.granularities() do
      :ok
    else
      error(
        component,
        module,
        :granularity,
        "granularity must be one of #{inspect(AshA2ui.Calendar.granularities())}, got: " <>
          inspect(granularity)
      )
    end
  end

  defp verify_compatible(%{sections: sections} = component, module) when not is_nil(sections) do
    error(
      component,
      module,
      :sections,
      "a display :calendar table cannot declare a sections block"
    )
  end

  defp verify_compatible(%{bulk_actions: [_ | _]} = component, module) do
    error(
      component,
      module,
      :bulk_actions,
      "a display :calendar table cannot declare bulk_actions"
    )
  end

  defp verify_compatible(_component, _module), do: :ok

  defp verify_fields(_component, nil, _module), do: :ok

  defp verify_fields(component, resource, module) do
    with :ok <- verify_date_field(component, resource, :date_field, module),
         :ok <- verify_date_field(component, resource, :end_date_field, module) do
      if component.end_date_field == component.date_field do
        error(
          component,
          module,
          :end_date_field,
          "end_date_field must differ from date_field (#{inspect(component.date_field)})"
        )
      else
        :ok
      end
    end
  end

  defp verify_date_field(component, resource, option, module) do
    case Map.get(component, option) do
      nil ->
        :ok

      field ->
        if AshA2ui.Calendar.field_kind(resource, field) do
          :ok
        else
          error(
            component,
            module,
            option,
            "#{option} #{inspect(field)} must be a public :date or datetime attribute " <>
              "(:utc_datetime, :utc_datetime_usec, :datetime, :naive_datetime) of " <>
              inspect(resource_name(resource))
          )
        end
    end
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

  defp resource_name(resource) when is_atom(resource), do: resource
  defp resource_name(dsl_state), do: Verifier.get_persisted(dsl_state, :module)

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
