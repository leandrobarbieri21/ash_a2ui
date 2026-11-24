defmodule AshA2ui.Verifiers.VerifyRecalculate do
  @moduledoc """
  Verifies at compile time that every `recalculate` field (admin catalog
  3.15) can follow a person's unsaved changes:

    * it is drawn on a `:detail` card whose context has an editable card
      (the changes it follows),
    * it is not an editable field of a card of that context (an edited
      value shows the person's change, not a recalculation),
    * when the context's resource is resolvable, its data layer has
      transactions: the preview runs the update and rolls it back.

  Raises `Spark.Error.DslError` on failure.
  """

  use Spark.Dsl.Verifier

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:a2ui])

    details =
      Enum.filter(entities, &(is_struct(&1, AshA2ui.Component) and &1.name == :detail))

    contexts =
      for %AshA2ui.Context{} = context <- entities, into: %{}, do: {context.name, context}

    entities
    |> Enum.filter(&(is_struct(&1, AshA2ui.Field) and &1.recalculate == true))
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case verify_field(field, details, contexts, module) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_field(field, details, contexts, module) do
    drawn_in =
      for detail <- details, field.name in (detail.fields || []), uniq: true, do: detail.context

    edited =
      for %{editable: %{}} = detail <- details,
          detail.context in drawn_in,
          uniq: true,
          do: detail.context

    editable_here =
      Enum.find(
        details,
        &(&1.editable && &1.context in edited && field.name in &1.editable.fields)
      )

    cond do
      edited == [] ->
        error(
          module,
          field,
          "field #{inspect(field.name)} declares recalculate, but no :detail card draws it " <>
            "in a context with an editable card: there are no unsaved changes for it to follow"
        )

      editable_here ->
        error(
          module,
          field,
          "field #{inspect(field.name)} declares recalculate, but it is an editable field of " <>
            "#{inspect(AshA2ui.Component.key(editable_here))}: an edited value shows the " <>
            "person's change"
        )

      true ->
        verify_transactions(field, edited, contexts, module)
    end
  end

  defp verify_transactions(field, edited, contexts, module) do
    case Enum.find(edited, &(not transacts?(contexts[&1]))) do
      nil ->
        :ok

      context ->
        error(
          module,
          field,
          "field #{inspect(field.name)} declares recalculate, but context #{inspect(context)}'s " <>
            "resource #{inspect(contexts[context].resource)} has a data layer without " <>
            "transactions: the preview runs the update and rolls it back"
        )
    end
  end

  # Unresolvable at verification time counts as able, like the other
  # verifiers' resource checks.
  defp transacts?(%{resource: resource}) when is_atom(resource) and not is_nil(resource) do
    if Code.ensure_loaded?(resource) and ResourceInfo.resource?(resource),
      do: Ash.DataLayer.data_layer_can?(resource, :transact),
      else: true
  end

  defp transacts?(_context), do: true

  defp error(module, field, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:a2ui, :field, field.name, :recalculate],
       message: message
     )}
  end
end
